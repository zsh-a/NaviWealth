use camino::Utf8PathBuf;
use clap::Subcommand;
use miette::Result;

use crate::{
    catalog::{CatalogSummary, build_prompt_manifest, read_catalog},
    print_json,
};

#[derive(Debug, Subcommand)]
pub(crate) enum CatalogCommand {
    Summary {
        catalog: Utf8PathBuf,
    },
    Agents {
        catalog: Utf8PathBuf,
    },
    Tools {
        catalog: Utf8PathBuf,
    },
    ProposalKinds {
        catalog: Utf8PathBuf,
    },
    PromptBlocks {
        catalog: Utf8PathBuf,
    },
    PromptManifest {
        catalog: Utf8PathBuf,
        #[arg(long)]
        agent_id: Option<String>,
    },
}

pub(crate) async fn run_catalog_command(command: CatalogCommand) -> Result<()> {
    match command {
        CatalogCommand::Summary { catalog } => {
            let catalog = read_catalog(catalog).await?;
            let summary = CatalogSummary::from_catalog(&catalog);
            print_json(&summary)
        }
        CatalogCommand::Agents { catalog } => {
            let catalog = read_catalog(catalog).await?;
            print_json(&catalog.agents)
        }
        CatalogCommand::Tools { catalog } => {
            let catalog = read_catalog(catalog).await?;
            print_json(&catalog.tools)
        }
        CatalogCommand::ProposalKinds { catalog } => {
            let catalog = read_catalog(catalog).await?;
            print_json(&catalog.proposal_kinds)
        }
        CatalogCommand::PromptBlocks { catalog } => {
            let catalog = read_catalog(catalog).await?;
            print_json(&catalog.prompt_blocks)
        }
        CatalogCommand::PromptManifest { catalog, agent_id } => {
            let catalog = read_catalog(catalog).await?;
            let manifest = build_prompt_manifest(&catalog, agent_id.as_deref())?;
            print_json(&manifest)
        }
    }
}
