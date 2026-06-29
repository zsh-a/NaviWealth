use camino::Utf8PathBuf;
use miette::{Result, miette};
use serde_json::{Value, json};

use crate::trace_store::read_json;

pub(crate) async fn read_command_input(
    input: Option<Utf8PathBuf>,
    input_json: Option<String>,
) -> Result<Value> {
    match (input, input_json) {
        (Some(_), Some(_)) => Err(miette!("use only one of --input or --input-json")),
        (Some(path), None) => read_json(path).await,
        (None, Some(value)) => serde_json::from_str(&value)
            .map_err(|e| miette!("failed to parse --input-json as JSON: {e}")),
        (None, None) => Ok(json!({})),
    }
}
