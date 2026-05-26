use serde::Deserialize;
use sha1::{Digest, Sha1};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KevCatalog {
    pub title: String,
    pub catalog_version: String,
    pub date_released: String,
    pub count: u64,
    pub vulnerabilities: Vec<KevEntry>,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct KevEntry {
    #[serde(rename = "cveID")]
    pub cve_id: String,
    pub vendor_project: String,
    pub product: String,
    pub vulnerability_name: String,
    pub date_added: String,
    pub short_description: String,
    pub required_action: String,
    pub due_date: String,
    #[serde(default)]
    pub known_ransomware_campaign_use: String,
    #[serde(default)]
    pub notes: String,
}


pub struct KevClient {
    url: String,
}

impl KevClient {
    pub fn new(url: &str) -> Self {
        Self { url: url.to_string() }
    }

    /// Download the feed and return (raw_bytes, sha1_hex).
    pub fn fetch_bytes(&self) -> Result<(Vec<u8>, String), Box<dyn std::error::Error>> {
        let resp = ureq::get(&self.url).call()?;

        let mut bytes = Vec::new();
        resp.into_reader().read_to_end(&mut bytes)?;

        let mut hasher = Sha1::new();
        hasher.update(&bytes);
        let sha1 = hex::encode(hasher.finalize());

        Ok((bytes, sha1))
    }
}

pub fn parse_catalog(bytes: &[u8]) -> Result<KevCatalog, Box<dyn std::error::Error>> {
    let catalog: KevCatalog = serde_json::from_slice(bytes)?;
    Ok(catalog)
}
