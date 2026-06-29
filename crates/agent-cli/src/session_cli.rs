use agent_core::{AgentSessionStore, SessionId, ThreadId};
use agent_store::FileSessionStore;
use camino::Utf8PathBuf;
use clap::Subcommand;
use miette::{IntoDiagnostic, Result};

use crate::{
    print_json,
    session::{create_session, fork_thread, show_session},
};

#[derive(Debug, Subcommand)]
pub(crate) enum SessionCommand {
    Create {
        #[arg(long)]
        title: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
    List {
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
    Show {
        session_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
    Fork {
        session_id: String,
        parent_thread_id: String,
        #[arg(long)]
        title: Option<String>,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
}

pub(crate) async fn run_session_command(command: SessionCommand) -> Result<()> {
    match command {
        SessionCommand::Create { title, store } => {
            let report = create_session(store, title).await?;
            print_json(&report)
        }
        SessionCommand::List { store } => {
            let store = FileSessionStore::new(store).await.into_diagnostic()?;
            let sessions = store.list_sessions().await.into_diagnostic()?;
            print_json(&sessions)
        }
        SessionCommand::Show { session_id, store } => {
            let report = show_session(store, SessionId(session_id)).await?;
            print_json(&report)
        }
        SessionCommand::Fork {
            session_id,
            parent_thread_id,
            title,
            store,
        } => {
            let report = fork_thread(
                store,
                SessionId(session_id),
                ThreadId(parent_thread_id),
                title,
            )
            .await?;
            print_json(&report)
        }
    }
}
