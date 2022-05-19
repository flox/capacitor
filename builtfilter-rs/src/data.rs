use std::collections::HashMap;

use serde::{ser::SerializeSeq, Deserialize, Serialize};
use serde_json::Value;

pub type DerivationPath = String;
pub type SubstituterUrl = String;

#[derive(Serialize, Deserialize)]
pub struct BuildItem {
    pub element: Element,
    #[serde(default)]
    pub cache: CacheMetaCollection,

    #[serde(flatten)]
    _other: HashMap<String, Value>,
}

/// Represents all cache entries of all rerivations found in one substituter
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Element {
    pub store_paths: Vec<DerivationPath>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub original_url: Option<String>,
    #[serde(flatten)]
    _other: HashMap<String, Value>,
}

/// Represents all cache entries of all rerivations found in one substituter
#[derive(Serialize, Deserialize)]
pub struct CacheMeta {
    #[serde(rename = "cacheUrl")]
    pub cache_url: String,
    pub state: CacheState,
    pub narinfo: Vec<Narinfo>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CacheState {
    Hit,
    Miss,
}

fn default_true() -> bool {
    true
}
/// Narinfo represents the json formatted nar info
/// as returned by `nix path-info`
#[derive(Serialize, Deserialize, Clone)]
pub struct Narinfo {
    #[serde(default = "default_true")]
    pub valid: bool,
    pub path: DerivationPath,
    #[serde(flatten)]
    _other: HashMap<String, Value>,
}

#[derive(Default)]
pub struct CacheMetaCollection(HashMap<SubstituterUrl, CacheMeta>);

impl<'de> Deserialize<'de> for CacheMetaCollection {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let metas: Vec<CacheMeta> = Vec::deserialize(deserializer)?;
        let pairs = metas.into_iter().map(|meta| (meta.cache_url.clone(), meta));
        Ok(CacheMetaCollection(HashMap::from_iter(pairs)))
    }
}

impl Serialize for CacheMetaCollection {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let count = self.0.len();

        let mut ser = serializer.serialize_seq(Some(count))?;
        for meta in self.0.values() {
            ser.serialize_element(meta)?
        }
        ser.end()
    }
}

impl CacheMetaCollection {
    pub fn add(&mut self, cache_meta: CacheMeta) -> () {
        self.0.insert(cache_meta.cache_url.clone(), cache_meta);
    }
}
