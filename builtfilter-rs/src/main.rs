use anyhow::{self, Result};
use futures::prelude::*;
use futures::stream::{self, StreamExt as _};
use reqwest;
use serde::de::IntoDeserializer;
use serde::{Deserialize, Serialize};
use serde_json::{self, Deserializer, StreamDeserializer, Value};
use std::collections::HashMap;
use std::io;
use std::io::stdout;
use std::process::Output;
use std::sync::Arc;

use log::{debug, error, info};
use par_stream::prelude::ParStreamExt as _;
use par_stream::prelude::StreamExt as _;
use tokio::process::Command;

use clap::Parser;

/// Simple program to greet a person
#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Args {
    #[clap(short, long, default_value = "https://cache.nixos.org")]
    substituter: SubstituterUrl,
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();

    let args = Args::parse();
    process_json_stream(args).await?;

    Ok(())
}

async fn process_json_stream(args: Args) -> Result<()> {
    let args = Arc::new(args);

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
            move || fetch_substituter(args, item)
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

async fn fetch_substituter(args: Arc<Args>, mut item: BuildItem) -> Result<BuildItem> {
    let f = item
        .element
        .storePaths
        .iter()
        .map(|derivation| make_command(&args.substituter, derivation).output());

    let narinfo: Vec<Narinfo> = futures::future::try_join_all(f)
        .await?
        .iter()
        .map(|output| {
            //   debug!("Stdout: {}", String::from_utf8(output.stdout.clone()).unwrap());
            //   debug!("StdErr: {}", String::from_utf8(output.stderr.clone()).unwrap());
            serde_json::from_slice(&output.stdout)
        })
        .collect::<Result<_, _>>()?;

    let cache_meta = CacheMeta {
        cacheUrl: args.substituter.to_string(),
        narinfo,
    };

    item.cacheMeta = Some(vec![cache_meta]);

    Ok(item)
}

fn make_command(substituter: &SubstituterUrl, derivation: &DerivationPath) -> Command {
    let mut command = Command::new("nix");
    command
        .arg("path-info")
        .arg("--json")
        .args(&["--eval-store", "auto"])
        .args(&["--store", substituter])
        .arg(derivation);

    command
}

type DerivationPath = String;
type SubstituterUrl = String;

#[derive(Serialize, Deserialize)]
struct BuildItem {
    element: Element,
    cacheMeta: Option<Vec<CacheMeta>>,

    #[serde(flatten)]
    _other: HashMap<String, Value>,
}

/// Represents all cache entries of all rerivations found in one substituter
#[derive(Serialize, Deserialize)]
struct Element {
    storePaths: Vec<DerivationPath>,
    #[serde(flatten)]
    _other: HashMap<String, Value>,
}

/// Represents all cache entries of all rerivations found in one substituter
#[derive(Serialize, Deserialize)]
struct CacheMeta {
    cacheUrl: String,
    narinfo: Vec<Narinfo>,
}

/// Narinfo represents the json formatted nar info
/// as returned by `nix path-info`
///
/// TODO: we may want to extend this in the future, hence its own type
#[derive(Serialize, Deserialize)]
struct Narinfo(Value);
