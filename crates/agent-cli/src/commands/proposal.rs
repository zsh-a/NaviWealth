use agent_core::{
    AgentProposalStore, ApprovalDecision, ApprovalDecisionKind, PROTOCOL_VERSION, ProposalEnvelope,
    ProposalId, ProposalStatus, RunId,
};
use agent_store::FileProposalStore;
use camino::Utf8PathBuf;
use clap::Subcommand;
use miette::{IntoDiagnostic, Result, miette};

use crate::{
    catalog::read_catalog,
    cli_input::read_command_input,
    print_json,
    proposal::{
        ProposalAction, ProposalActionResponse, ProposalDecisionResponse,
        append_proposal_action_trace_event, append_proposal_created_trace_event,
        append_proposal_decision_trace_event, execute_proposal_action_with_store,
        parse_approval_decision, proposal_action_tool,
    },
    tools::{CliServices, ToolOverrides, tool_overrides},
};

#[derive(Debug, Subcommand)]
pub(crate) enum ProposalCommand {
    Create {
        #[arg(long)]
        run_id: String,
        #[arg(long)]
        agent_id: String,
        #[arg(long)]
        kind: String,
        #[arg(long)]
        summary: String,
        #[arg(long)]
        payload: Option<Utf8PathBuf>,
        #[arg(long)]
        payload_json: Option<String>,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
    List {
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long)]
        run_id: Option<String>,
    },
    Inspect {
        proposal_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
    Decide {
        proposal_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long)]
        decision: String,
        #[arg(long)]
        comment: Option<String>,
    },
    Apply {
        proposal_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long)]
        catalog: Utf8PathBuf,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
    },
    Undo {
        proposal_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long)]
        catalog: Utf8PathBuf,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
    },
}

pub(crate) async fn run_proposal_command(command: ProposalCommand) -> Result<()> {
    match command {
        ProposalCommand::Create {
            run_id,
            agent_id,
            kind,
            summary,
            payload,
            payload_json,
            store,
        } => {
            let payload = read_command_input(payload, payload_json).await?;
            let proposal = ProposalEnvelope::new(RunId(run_id), agent_id, kind, summary, payload);
            let store_path = store;
            let store = FileProposalStore::new(store_path.clone())
                .await
                .into_diagnostic()?;
            store
                .create_proposal(proposal.clone())
                .await
                .into_diagnostic()?;
            append_proposal_created_trace_event(&store_path, &proposal).await?;
            print_json(&proposal)
        }
        ProposalCommand::List { store, run_id } => {
            let store = FileProposalStore::new(store).await.into_diagnostic()?;
            let run_id = run_id.map(RunId);
            let proposals = store
                .list_proposals(run_id.as_ref())
                .await
                .into_diagnostic()?;
            print_json(&proposals)
        }
        ProposalCommand::Inspect { proposal_id, store } => {
            let store = FileProposalStore::new(store).await.into_diagnostic()?;
            let proposal = store
                .get_proposal(&ProposalId(proposal_id.clone()))
                .await
                .into_diagnostic()?
                .ok_or_else(|| miette!("proposal '{proposal_id}' was not found"))?;
            print_json(&proposal)
        }
        ProposalCommand::Decide {
            proposal_id,
            store,
            decision,
            comment,
        } => {
            let store_path = store;
            let store = FileProposalStore::new(store_path.clone())
                .await
                .into_diagnostic()?;
            let proposal_id = ProposalId(proposal_id);
            let mut proposal = store
                .get_proposal(&proposal_id)
                .await
                .into_diagnostic()?
                .ok_or_else(|| miette!("proposal '{}' was not found", proposal_id.0))?;
            let decision = parse_approval_decision(&decision)?;
            proposal.status = match decision {
                ApprovalDecisionKind::Approve => ProposalStatus::Approved,
                ApprovalDecisionKind::Deny => ProposalStatus::Denied,
            };
            store
                .update_proposal(proposal.clone())
                .await
                .into_diagnostic()?;
            let response = ProposalDecisionResponse {
                decision: ApprovalDecision {
                    protocol_version: PROTOCOL_VERSION.to_owned(),
                    proposal_id,
                    decision,
                    decided_at: time::OffsetDateTime::now_utc(),
                    comment,
                },
                proposal,
            };
            append_proposal_decision_trace_event(&store_path, &response).await?;
            print_json(&response)
        }
        ProposalCommand::Apply {
            proposal_id,
            store,
            catalog,
            tool_host,
            mock_tool,
            tool_source,
        } => {
            let response = execute_proposal_action(
                ProposalId(proposal_id),
                store,
                catalog,
                tool_overrides(tool_host, mock_tool, tool_source).await?,
                ProposalAction::Apply,
            )
            .await?;
            print_json(&response)
        }
        ProposalCommand::Undo {
            proposal_id,
            store,
            catalog,
            tool_host,
            mock_tool,
            tool_source,
        } => {
            let response = execute_proposal_action(
                ProposalId(proposal_id),
                store,
                catalog,
                tool_overrides(tool_host, mock_tool, tool_source).await?,
                ProposalAction::Undo,
            )
            .await?;
            print_json(&response)
        }
    }
}

async fn execute_proposal_action(
    proposal_id: ProposalId,
    store_path: Utf8PathBuf,
    catalog_path: Utf8PathBuf,
    tool_overrides: ToolOverrides,
    action: ProposalAction,
) -> Result<ProposalActionResponse> {
    let catalog = read_catalog(catalog_path).await?;
    let store = FileProposalStore::new(store_path.clone())
        .await
        .into_diagnostic()?;
    let services = CliServices::new(tool_overrides);
    let mut proposal = store
        .get_proposal(&proposal_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("proposal '{}' was not found", proposal_id.0))?;
    let tool = proposal_action_tool(&catalog, &proposal.kind)?;
    let response =
        execute_proposal_action_with_store(&store, &services, &mut proposal, tool, action).await?;
    append_proposal_action_trace_event(&store_path, &response).await?;
    Ok(response)
}
