use anyhow::{self, bail, Context, Result};
use data::{BuildItem, DerivationPath, Narinfo, SubstituterUrl};
use futures::prelude::*;
use futures::stream;

use serde_json::{self, Deserializer};

use std::ffi::OsStr;
use std::fs::{File, OpenOptions};
use std::io;

use std::path::{Path, PathBuf};
use std::process::ExitStatus;
use std::sync::{Arc, RwLock};
use std::time::SystemTime;

use log::{debug, error, info};
use par_stream::prelude::ParStreamExt as _;
use tokio::process::Command;

use clap::Parser;

mod cache;
use cache::{Cache, CacheItem};

use crate::data::{CacheMeta, CacheState};
mod data;

/// Simple program to greet a person
#[derive(Parser, Debug, Clone)]
#[clap(author, version, about, long_about = None)]
struct Args {
    #[clap(short, long, default_value = "https://cache.nixos.org")]
    substituter: SubstituterUrl,

    #[clap(short, long)]
    cache_db: Option<PathBuf>,

    #[clap(long)]
    url: Option<String>,

    #[clap(long)]
    original_url: Option<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();

    let args = Args::parse();

    // Create a cache from specified cache file or only in-memory
    let fetch_cache = if let Some(path) = &args.cache_db {
        if !(Path::new(path).exists()) {
            info!("Cache file at `{path:?}` not found, starting with in-memory cache");
            Cache::default()
        } else {
            let reader = io::BufReader::new(File::open(path)?);
            serde_json::from_reader(reader)?
        }
    } else {
        info!("Using in-memory cache");
        Cache::default()
    };

    // Prepare shared data
    let args = Arc::new(args);
    let fetch_cache = Arc::new(RwLock::new(fetch_cache));

    // read json object stream from stdin process and send send result to stdout
    process_json_stream(args.clone(), fetch_cache.clone()).await?;

    // update cache file
    if let Some(path) = &args.cache_db {
        let file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(path)?;
        let writer = io::BufWriter::new(file);
        serde_json::to_writer(writer, &*fetch_cache.read().unwrap())
            .with_context(|| "Failed writing cache")?;
    }

    Ok(())
}

async fn process_json_stream(args: Arc<Args>, fetch_cache: Arc<RwLock<Cache>>) -> Result<()> {
    let stdin = io::stdin();
    let deserializer_iter = Deserializer::from_reader(stdin).into_iter().filter_map(
        |res: Result<BuildItem, serde_json::Error>| {
            if let Some(error) = res.as_ref().err() {
                error!("Deserialization Error: {error}");
                return None;
            }
            res.ok()
        },
    );

    let json_stream = stream::iter(deserializer_iter);

    let _x = json_stream
        .par_map_unordered(None, move |item| {
            let args = args.clone();
            let fetch_cache = fetch_cache.clone();
            move || fetch_substituter(args, fetch_cache, item)
        })
        .for_each(|item| async {
            match item.await {
                Ok(item) => serde_json::to_writer(io::stdout(), &item).unwrap(),
                Err(e) => error!("Error while fetching: {e}"),
            }
            ()
        })
        .await;

    Ok(())
}

async fn fetch_substituter(
    args: Arc<Args>,
    fetch_cache: Arc<RwLock<Cache>>,
    mut item: BuildItem,
) -> Result<BuildItem> {
    // Lookup store paths in the cache separate uncached ones
    let (cached, uncached): (
        Vec<(&DerivationPath, Option<Narinfo>)>,
        Vec<(&DerivationPath, Option<Narinfo>)>,
    ) = item
        .element
        .store_paths
        .iter()
        .map(|drv| {
            let substituter = args.substituter.to_owned();
            let drv_key = (*drv).to_owned();
            (
                drv,
                fetch_cache
                    .read()
                    .unwrap()
                    .get(&(substituter, drv_key))
                    .cloned()
                    .map(|ci| ci.narinfo),
            )
        })
        .partition(|(_, opt)| opt.is_some());

    // Check wheter uncached
    let uncached = uncached.iter().map(|(drv, _)| *drv).collect::<Vec<_>>();
    let narinfo: Vec<Narinfo> = if uncached.is_empty() {
        info!("All inputs cached");
        Vec::new()
    } else {
        let mut command = make_command(&args.substituter, uncached);

        let output = command.output().await?;

        if !ExitStatus::success(&output.status) {
            // TODO: error handling
            bail!("nix path-info: {}", String::from_utf8_lossy(&output.stderr))
        }
        if !output.stderr.is_empty() {
            warn!("nix path-info: {}", String::from_utf8_lossy(&output.stderr))
        }
        serde_json::from_slice(&output.stdout)?
    };

    let (mut hits, misses): (Vec<Narinfo>, Vec<Narinfo>) =
        narinfo.into_iter().partition(|info| info.valid);

    let cache_meta = if !misses.is_empty() {
        info!(
            "cache misses: {:?}",
            misses.into_iter().map(|info| info.path).collect::<Vec<_>>()
        );
        CacheMeta {
            cache_url: args.substituter.to_string(),
            state: CacheState::Miss,
            narinfo: vec![],
        }
    } else {
        hits.extend(cached.into_iter().map(|(_, info)| info.unwrap()));
        let mut cache = fetch_cache.write().unwrap();
        hits.iter().cloned().for_each(|info| {
            cache.insert(
                (args.substituter.to_owned(), info.path.to_owned()),
                CacheItem {
                    ts: SystemTime::now(),
                    narinfo: info,
                },
            );
        });

        CacheMeta {
            cache_url: args.substituter.to_string(),
            narinfo: hits,
            state: CacheState::Hit,
        }
    };

    item.element.url = args.url.clone();
    item.element.original_url = args.original_url.clone();
    item.cache.add(cache_meta);

    Ok(item)
}

fn make_command(
    substituter: &SubstituterUrl,
    derivation: impl IntoIterator<Item = impl AsRef<OsStr>>,
) -> Command {
    let mut command = Command::new("nix");
    command
        .arg("path-info")
        .arg("--json")
        .args(&["--eval-store", "auto"])
        .args(&["--store", substituter]) // select custom substituter is specified
        .args(derivation.into_iter());

    debug!("{:?}", command.as_std());

    command
}
