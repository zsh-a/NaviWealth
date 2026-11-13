//! An explicit host approval binds a single recognition to the visible target.

use thiserror::Error;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UploadTarget {
    pub provider: String,
    pub base_url: String,
    pub model: String,
}

impl UploadTarget {
    pub fn new(provider: &str, base_url: &str, model: &str) -> Self {
        Self {
            provider: provider.trim().to_owned(),
            base_url: base_url.trim().trim_end_matches('/').to_owned(),
            model: model.trim().to_owned(),
        }
    }

    fn valid(&self) -> bool {
        !self.provider.is_empty()
            && !self.model.is_empty()
            && self.model.len() <= 200
            && (self.base_url.starts_with("https://") || self.base_url.starts_with("http://"))
    }
}

/// Not serializable and with private fields: a persisted account is not consent.
/// The host calls [`Consent::approve`] only after the user explicitly accepts
/// this target (or an existing user-granted permission matches that target).
#[derive(Debug)]
pub struct Consent {
    target: UploadTarget,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Error)]
pub enum ConsentError {
    #[error("Photo upload was not approved")]
    NotApproved,
    #[error("The upload target changed after approval")]
    TargetChanged,
    #[error("The upload target is invalid")]
    InvalidTarget,
}

impl Consent {
    pub fn approve(target: UploadTarget, approved: bool) -> Result<Self, ConsentError> {
        if !approved {
            return Err(ConsentError::NotApproved);
        }
        if !target.valid() {
            return Err(ConsentError::InvalidTarget);
        }
        Ok(Self { target })
    }

    pub fn check(&self, target: &UploadTarget) -> Result<(), ConsentError> {
        if &self.target == target {
            Ok(())
        } else {
            Err(ConsentError::TargetChanged)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn approval_binds_provider_address_and_model() {
        let target = UploadTarget::new("anthropic", "https://example.com/v1/", "model-a");
        assert_eq!(
            Consent::approve(target.clone(), false).unwrap_err(),
            ConsentError::NotApproved
        );
        let consent = Consent::approve(target.clone(), true).unwrap();
        assert_eq!(consent.check(&target), Ok(()));
        for changed in [
            UploadTarget::new("openai", &target.base_url, &target.model),
            UploadTarget::new(&target.provider, "https://other.example/v1", &target.model),
            UploadTarget::new(&target.provider, &target.base_url, "model-b"),
        ] {
            assert_eq!(consent.check(&changed), Err(ConsentError::TargetChanged));
        }
    }
}
