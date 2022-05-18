use anyhow::{self, bail, Context, Result};
use futures::prelude::*;
use futures::stream::{self, Collect, StreamExt as _};
use serde::{Deserialize, Serialize};
use serde_json::{self, Deserializer, Value};
use serde_with::serde_as;
use std::collections::{HashMap, HashSet};
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read};

use std::path::{Path, PathBuf};
use std::process::ExitStatus;
use std::sync::{Arc, RwLock};
use std::time::SystemTime;

use log::{debug, error, info};
use par_stream::prelude::ParStreamExt as _;
use tokio::process::Command;

use clap::Parser;

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

    let args = Arc::new(args);
    let fetch_cache = Arc::new(RwLock::new(fetch_cache));

    process_json_stream(args.clone(), fetch_cache.clone()).await?;

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

    let uncached = uncached.iter().map(|(drv, _)| *drv).collect::<Vec<_>>();
    let narinfo: Vec<Narinfo> = if uncached.is_empty() {
        info!("All inputs cached");
        Vec::new()
    } else {
        let mut command = make_command(&args.substituter, uncached);

        let output = command.output().await?;

        if !ExitStatus::success(&output.status) {
            bail!("nix path-info: {}", String::from_utf8_lossy(&output.stdout))
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
    item.cache = Some(vec![cache_meta]);

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
        .args(&["--store", substituter])
        .args(derivation.into_iter());

    debug!("{:?}", command.as_std());

    command
}

type DerivationPath = String;
type SubstituterUrl = String;

#[derive(Serialize, Deserialize)]
struct BuildItem {
    element: Element,
    cache: Option<Vec<CacheMeta>>,

    #[serde(flatten)]
    _other: HashMap<String, Value>,
}

/// Represents all cache entries of all rerivations found in one substituter
#[derive(Serialize, Deserialize)]
#[serde(rename_all="camelCase")]
struct Element {
    store_paths: Vec<DerivationPath>,
    #[serde(skip_serializing_if = "Option::is_none")]
    url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    original_url: Option<String>,
    #[serde(flatten)]
    _other: HashMap<String, Value>,
}

/// Represents all cache entries of all rerivations found in one substituter
#[derive(Serialize, Deserialize)]
struct CacheMeta {
    #[serde(rename = "cacheUrl")]
    cache_url: String,
    state: CacheState,
    narinfo: Vec<Narinfo>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
enum CacheState {
    Hit,
    Miss,
}

fn default_true() -> bool {
    true
}
/// Narinfo represents the json formatted nar info
/// as returned by `nix path-info`
#[derive(Serialize, Deserialize, Clone)]
struct Narinfo {
    #[serde(default = "default_true")]
    valid: bool,
    path: DerivationPath,
    #[serde(flatten)]
    _other: HashMap<String, Value>,
}

#[serde_as]
#[derive(Serialize, Deserialize, Clone, Default)]
struct Cache(#[serde_as(as = "Vec<(_,_)>")] HashMap<(String, String), CacheItem>);

impl Cache {
    fn get(&self, key: &(String, String)) -> Option<&CacheItem> {
        self.0.get(key)
    }

    fn insert(&mut self, key: (String, String), value: CacheItem) -> Option<CacheItem> {
        self.0.insert(key, value)
    }
}

#[derive(Serialize, Deserialize, Clone)]
struct CacheItem {
    ts: SystemTime,
    narinfo: Narinfo,
}
