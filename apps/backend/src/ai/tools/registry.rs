use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use serde_json::Value;

use super::super::anthropic::ToolSchema;
use super::super::policy::ToolDescriptor;
use super::ToolCtx;
use crate::error::AppError;

#[async_trait(?Send)]
pub trait Tool: Sync {
    fn descriptor(&self) -> ToolDescriptor;
    fn input_schema(&self) -> Value;
    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError>;
}

pub struct ToolRegistry {
    tools: HashMap<&'static str, Arc<dyn Tool>>,
}

impl ToolRegistry {
    pub fn new(tools: impl IntoIterator<Item = Arc<dyn Tool>>) -> Self {
        let tools = tools
            .into_iter()
            .map(|tool| (tool.descriptor().name, tool))
            .collect();
        Self { tools }
    }

    pub fn get(&self, name: &str) -> Option<&dyn Tool> {
        self.tools.get(name).map(Arc::as_ref)
    }

    pub fn descriptors(&self) -> Vec<ToolDescriptor> {
        let mut descriptors: Vec<ToolDescriptor> =
            self.tools.values().map(|tool| tool.descriptor()).collect();
        descriptors.sort_by(|a, b| a.name.cmp(b.name));
        descriptors
    }

    pub fn schemas(&self) -> Vec<ToolSchema> {
        let mut schemas: Vec<ToolSchema> = self
            .tools
            .values()
            .map(|tool| {
                let descriptor = tool.descriptor();
                ToolSchema {
                    name: descriptor.name.into(),
                    description: description_for(descriptor.name).into(),
                    input_schema: tool.input_schema(),
                }
            })
            .collect();
        schemas.sort_by(|a, b| a.name.cmp(&b.name));
        schemas
    }
}

fn description_for(name: &str) -> &'static str {
    match name {
        "propose_trade" => crate::ai::tools::propose_trade::DESCRIPTION,
        "propose_expense" => crate::ai::tools::propose_expense::DESCRIPTION,
        "propose_liability_payment" => crate::ai::tools::propose_liability_payment::DESCRIPTION,
        "propose_account_create" => crate::ai::tools::propose_account_create::DESCRIPTION,
        "propose_asset_valuation" => crate::ai::tools::propose_asset_valuation::DESCRIPTION,
        _ => "",
    }
}
