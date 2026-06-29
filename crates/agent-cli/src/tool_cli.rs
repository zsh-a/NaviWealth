use agent_core::AgentServices;
use camino::Utf8PathBuf;
use clap::Subcommand;
use miette::{Result, miette};

use crate::{
    catalog::read_catalog,
    cli_input::read_command_input,
    print_json,
    tools::{
        CliServices, builtin_tools, load_tool_source_specs, load_tool_sources, source_has_tool,
        tool_overrides,
    },
};

#[derive(Debug, Subcommand)]
pub(crate) enum ToolCommand {
    List {
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
    },
    Call {
        name: String,
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
        #[arg(long)]
        input: Option<Utf8PathBuf>,
        #[arg(long)]
        input_json: Option<String>,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
    },
}

pub(crate) async fn run_tool_command(command: ToolCommand) -> Result<()> {
    match command {
        ToolCommand::List {
            catalog,
            tool_source,
        } => {
            let mut tools = match catalog {
                Some(path) => read_catalog(path).await?.tools,
                None => builtin_tools(),
            };
            tools.extend(load_tool_source_specs(tool_source).await?);
            print_json(&tools)
        }
        ToolCommand::Call {
            name,
            catalog,
            tool_source,
            input,
            input_json,
            tool_host,
            mock_tool,
        } => {
            let input = read_command_input(input, input_json).await?;
            let sources = load_tool_sources(tool_source.clone()).await?;
            let has_catalog = catalog.is_some();
            let in_catalog = match catalog {
                Some(path) => read_catalog(path)
                    .await?
                    .tools
                    .iter()
                    .any(|tool| tool.name == name),
                None => false,
            };
            let in_sources = source_has_tool(&sources, &name);
            if !in_catalog && !in_sources && (has_catalog || !sources.is_empty()) {
                return Err(miette!(
                    "tool '{name}' is not present in the active catalog or configured tool sources"
                ));
            }
            let services =
                CliServices::new(tool_overrides(tool_host, mock_tool, tool_source).await?);
            let output = services
                .call_tool(&name, input)
                .await
                .map_err(|err| miette!(err.record.message))?;
            print_json(&output)
        }
    }
}
