use std::{collections::HashMap, time::SystemTime};

use serde::{Deserialize, Serialize};
use serde_with::serde_as;

use crate::data::Narinfo;

#[serde_as]
#[derive(Serialize, Deserialize, Clone, Default)]
pub struct Cache(#[serde_as(as = "Vec<(_,_)>")] HashMap<(String, String), CacheItem>);

impl Cache {
    pub fn get(&self, key: &(String, String)) -> Option<&CacheItem> {
        self.0.get(key)
    }

    pub fn insert(&mut self, key: (String, String), value: CacheItem) -> Option<CacheItem> {
        self.0.insert(key, value)
    }
}

#[derive(Serialize, Deserialize, Clone)]
pub struct CacheItem {
    pub ts: SystemTime,
    pub narinfo: Narinfo,
}
