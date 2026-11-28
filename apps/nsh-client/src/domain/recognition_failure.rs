//! Allowlisted diagnostics. No provider text, credentials or record content.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResponseFailure {
    Json,
    Schema,
    Protocol,
    Tool,
    OutputLimit,
    Stream,
    Configuration,
    Request,
    History,
    Records,
    Questions,
    ImageReference,
    Worker,
    Cancelled,
    Provider,
}
impl ResponseFailure {
    pub fn code(self) -> &'static str {
        match self {
            Self::Json => "recognition_invalid_json",
            Self::Schema => "recognition_schema_mismatch",
            Self::Protocol => "recognition_invalid_response",
            Self::Tool => "recognition_invalid_tool",
            Self::OutputLimit => "recognition_output_limit",
            Self::Stream => "provider_stream_incomplete",
            Self::Configuration => "recognition_configuration",
            Self::Request => "recognition_invalid_request",
            Self::History => "recognition_unsupported_history",
            Self::Records => "capture_invalid_records",
            Self::Questions => "capture_invalid_questions",
            Self::ImageReference => "capture_invalid_image_reference",
            Self::Worker => "recognition_worker_interrupted",
            Self::Cancelled => "recognition_cancelled",
            Self::Provider => "provider_error",
        }
    }
}
