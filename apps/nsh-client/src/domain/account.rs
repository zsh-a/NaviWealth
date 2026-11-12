//! The user's own model account: where photos go and with which key. The
//! key lives only on this device and is sent only to the account's base
//! URL; there is no NaviWealth relay.

use serde::{Deserialize, Serialize};

/// The API a model account speaks.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Provider {
    /// Anthropic's Messages API.
    #[default]
    Anthropic,
    /// The OpenAI Chat Completions API, as many providers and local
    /// servers offer it.
    OpenAiCompatible,
}

impl Provider {
    /// Both, in the order the settings show them.
    pub const ALL: [Provider; 2] = [Provider::Anthropic, Provider::OpenAiCompatible];

    /// The base URL a new account starts with.
    pub fn default_base_url(self) -> &'static str {
        match self {
            Provider::Anthropic => "https://api.anthropic.com/v1",
            Provider::OpenAiCompatible => "https://api.openai.com/v1",
        }
    }

    /// The model a new account starts with; OpenAI-compatible servers name
    /// their own, so the user types it.
    pub fn default_model(self) -> &'static str {
        match self {
            Provider::Anthropic => "claude-opus-5-5",
            Provider::OpenAiCompatible => "",
        }
    }

    /// Whether requests need an API key (local OpenAI-compatible servers
    /// often take none).
    pub fn requires_key(self) -> bool {
        self == Provider::Anthropic
    }
}

/// A configured account. The key is kept apart from the rest (it is never
/// serialized with it).
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct ModelAccount {
    pub provider: Provider,
    pub base_url: String,
    pub model: String,
    #[serde(skip)]
    pub api_key: String,
}

/// Which field of an account is wrong.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccountError {
    /// Not an `https://` (or `http://`) URL with a host.
    BaseUrl,
    /// Empty, or containing spaces.
    Model,
    /// Missing where the provider needs one.
    ApiKey,
}

impl ModelAccount {
    /// A new account of `provider` with its defaults and no key.
    pub fn new(provider: Provider) -> Self {
        Self {
            provider,
            base_url: provider.default_base_url().to_owned(),
            model: provider.default_model().to_owned(),
            api_key: String::new(),
        }
    }

    /// The base URL without surrounding spaces or a trailing slash.
    pub fn normalized_base_url(&self) -> String {
        self.base_url.trim().trim_end_matches('/').to_owned()
    }

    /// The host requests go to (`api.anthropic.com`), for people to read.
    pub fn host(&self) -> String {
        let base = self.normalized_base_url();
        let rest = base
            .strip_prefix("https://")
            .or_else(|| base.strip_prefix("http://"))
            .unwrap_or(&base);
        rest.split(['/', '?', '#'])
            .next()
            .unwrap_or(rest)
            .to_owned()
    }

    /// Whether requests would travel unencrypted.
    pub fn is_cleartext(&self) -> bool {
        self.normalized_base_url().starts_with("http://")
    }

    /// Every field's first problem, in the order the form shows them.
    pub fn validate(&self) -> Vec<AccountError> {
        let mut errors = Vec::new();
        let base = self.normalized_base_url();
        let scheme_ok = base.starts_with("https://") || base.starts_with("http://");
        if !scheme_ok || self.host().is_empty() || base.contains(char::is_whitespace) {
            errors.push(AccountError::BaseUrl);
        }
        let model = self.model.trim();
        if model.is_empty() || model.contains(char::is_whitespace) {
            errors.push(AccountError::Model);
        }
        if self.provider.requires_key() && self.api_key.trim().is_empty() {
            errors.push(AccountError::ApiKey);
        }
        errors
    }

    /// Whether photos can be sent with it.
    pub fn is_ready(&self) -> bool {
        self.validate().is_empty()
    }

    /// What consent to send photos is tied to: changing the provider, the
    /// server or the model asks again.
    pub fn fingerprint(&self) -> String {
        let provider = match self.provider {
            Provider::Anthropic => "anthropic",
            Provider::OpenAiCompatible => "openai",
        };
        format!(
            "{provider}|{}|{}",
            self.normalized_base_url().to_ascii_lowercase(),
            self.model.trim()
        )
    }

    /// The key as the settings show it at rest: its last four characters.
    pub fn masked_key(&self) -> String {
        let key = self.api_key.trim();
        if key.is_empty() {
            return String::new();
        }
        let tail: String = key
            .chars()
            .rev()
            .take(4)
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect();
        format!("••••{tail}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_are_ready_once_keyed() {
        let mut account = ModelAccount::new(Provider::Anthropic);
        assert_eq!(account.validate(), vec![AccountError::ApiKey]);
        account.api_key = "sk-ant-123456".into();
        assert!(account.is_ready());
        assert_eq!(account.host(), "api.anthropic.com");
        assert_eq!(account.masked_key(), "••••3456");
    }

    #[test]
    fn openai_compatible_servers_name_their_model_and_may_skip_the_key() {
        let mut account = ModelAccount::new(Provider::OpenAiCompatible);
        assert_eq!(account.validate(), vec![AccountError::Model]);
        account.model = "qwen-vl-max".into();
        account.base_url = "http://192.168.1.20:11434/v1/".into();
        assert!(account.is_ready());
        assert!(account.is_cleartext());
        assert_eq!(account.host(), "192.168.1.20:11434");
        assert_eq!(
            account.normalized_base_url(),
            "http://192.168.1.20:11434/v1"
        );
    }

    #[test]
    fn rejects_bad_urls_and_models() {
        let mut account = ModelAccount::new(Provider::Anthropic);
        account.api_key = "k".into();
        account.base_url = "ftp://example.com".into();
        account.model = "claude opus".into();
        assert_eq!(
            account.validate(),
            vec![AccountError::BaseUrl, AccountError::Model]
        );
        account.base_url = "https://".into();
        assert!(account.validate().contains(&AccountError::BaseUrl));
    }

    #[test]
    fn consent_follows_the_destination() {
        let mut a = ModelAccount::new(Provider::Anthropic);
        a.api_key = "one".into();
        let mut b = a.clone();
        b.api_key = "two".into();
        b.base_url = "https://API.anthropic.com/v1/".into();
        assert_eq!(a.fingerprint(), b.fingerprint());
        b.model = "claude-haiku-5-5".into();
        assert_ne!(a.fingerprint(), b.fingerprint());
    }

    #[test]
    fn the_key_is_never_serialized() {
        let mut account = ModelAccount::new(Provider::Anthropic);
        account.api_key = "secret".into();
        let json = serde_json::to_string(&account).unwrap();
        assert!(!json.contains("secret"));
        let back: ModelAccount = serde_json::from_str(&json).unwrap();
        assert!(back.api_key.is_empty());
    }
}
