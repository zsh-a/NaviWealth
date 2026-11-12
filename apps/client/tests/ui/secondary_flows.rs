use super::*;

#[test]
fn mock_ai_streams_a_reply() {
    let mut app = app();
    open_global(&mut app, "tab-chat");
    app.wait_for("id:chat-input").unwrap();
    app.type_text("id:chat-input", "你好").unwrap();
    app.press("id:chat-send").unwrap();
    app.wait_for("text:已连接模拟模型（开发模式）。真实模型请在设置中配置自己的 API Key。")
        .unwrap();
}

#[test]
fn enable_knowledge_from_settings_and_create_note() {
    let mut app = app();
    // Knowledge starts off: no 笔记 tab yet.
    open_global(&mut app, "tab-settings");
    app.wait_for("text:领域").unwrap();
    app.wait_for("id:domain-toggle-knowledge").unwrap();

    // Flip the switch: the tab appears, the switch reads 已启用.
    app.press("id:domain-toggle-knowledge").unwrap();
    app.wait_for("text:已启用").unwrap();
    // Optional domains live in the workspace picker, while Finance keeps four tabs.
    root(&mut app);
    app.press("id:workspace-more").unwrap();
    app.press("id:domain-switcher").unwrap();
    app.wait_for("id:domain-knowledge").unwrap();
    app.press("id:domain-knowledge").unwrap();
    app.wait_for("id:open-note-form").unwrap();
    app.press("id:open-note-form").unwrap();
    app.type_text("id:note-title", "第一篇笔记").unwrap();
    app.type_text("id:note-content", "nsh 客户端第一条笔记")
        .unwrap();
    app.press("id:note-save").unwrap();

    // The note is visible in the list.
    app.wait_for("text:第一篇笔记").unwrap();
    app.wait_for("text:nsh 客户端第一条笔记").unwrap();
}

/// The scripted mock marker turns the user text into a real
/// finance_record_expense tool call, so the confirmation loop runs end to
/// end: card appears → 批准 → the entry lands in the ledger.
#[test]
fn ai_write_confirm_flow_approve_lands_in_ledger() {
    let mut app = app();

    // Create the funding account first (unique name for this test).
    app.wait_for("id:open-account-form").unwrap();
    app.press("id:open-account-form").unwrap();
    app.type_text("id:account-name", "AI确认账户").unwrap();
    app.type_text("id:account-opening", "500").unwrap();
    app.press("id:account-save").unwrap();
    app.wait_for("text:AI确认账户").unwrap();

    // The scripted marker makes the mock model call the write tool.
    open_global(&mut app, "tab-chat");
    app.wait_for("id:chat-input").unwrap();
    app.type_text("id:chat-input", "记一笔：9.9|dining|AI确认账户")
        .unwrap();
    app.press("id:chat-send").unwrap();

    // The confirmation card renders the write summary with both actions.
    app.wait_for("text:AI 写入请求 · finance_record_expense")
        .unwrap();
    app.wait_for("id:confirm-approve-0").unwrap();
    app.wait_for("id:confirm-deny-0").unwrap();

    // Approve: the card reports the write, the ledger shows the entry.
    app.press("id:confirm-approve-0").unwrap();
    app.wait_for_within(
        "text:已写入支出 9.9 CNY（餐饮，AI确认账户）",
        std::time::Duration::from_secs(5),
    )
    .unwrap();

    go_tab(&mut app, "tab-ledger");
    app.wait_for("text:-9.90").unwrap();
    app.wait_for("text:AI确认账户").unwrap();
}

/// Denying a pending write keeps the database untouched: the card shows
/// the rejection and no ledger line appears for that amount.
#[test]
fn ai_write_confirm_flow_deny_keeps_ledger_untouched() {
    let mut app = app();

    app.wait_for("id:open-account-form").unwrap();
    app.press("id:open-account-form").unwrap();
    app.type_text("id:account-name", "AI拒绝账户").unwrap();
    app.type_text("id:account-opening", "300").unwrap();
    app.press("id:account-save").unwrap();
    app.wait_for("text:AI拒绝账户").unwrap();

    open_global(&mut app, "tab-chat");
    app.wait_for("id:chat-input").unwrap();
    app.type_text("id:chat-input", "记一笔：7.7|dining|AI拒绝账户")
        .unwrap();
    app.press("id:chat-send").unwrap();
    app.wait_for("text:AI 写入请求 · finance_record_expense")
        .unwrap();
    app.wait_for("id:confirm-deny-0").unwrap();

    // Reject: the card flips to the rejected state.
    app.press("id:confirm-deny-0").unwrap();
    app.wait_for("text:已拒绝，未写入任何数据").unwrap();

    // Nothing was written: no ledger line for the denied amount.
    go_tab(&mut app, "tab-ledger");
    app.wait_for_gone(
        "text:AI拒绝账户  7.7 CNY",
        std::time::Duration::from_secs(2),
    )
    .unwrap();
}

/// The chat keeps a multi-turn history: a second send produces a fresh
/// turn (its scripted tool call opens a new confirm card), and 清空会话
/// drops bubbles and cards (plus the persisted session).
#[test]
fn chat_history_multi_turn_and_clear() {
    let mut app = app();

    // The second turn's scripted write needs an account to exist.
    app.wait_for("id:open-account-form").unwrap();
    app.press("id:open-account-form").unwrap();
    app.type_text("id:account-name", "AI历史账户").unwrap();
    app.press("id:account-save").unwrap();
    app.wait_for("text:AI历史账户").unwrap();

    open_global(&mut app, "tab-chat");
    app.wait_for("id:chat-input").unwrap();

    // Turn 1: a plain mock reply.
    app.type_text("id:chat-input", "第一轮").unwrap();
    app.press("id:chat-send").unwrap();
    app.wait_for("text:已连接模拟模型（开发模式）。真实模型请在设置中配置自己的 API Key。")
        .unwrap();

    // Turn 2 (after the first turn settled): the scripted marker makes
    // the mock model call the write tool again — a new card, a new turn.
    app.wait(std::time::Duration::from_millis(300)).unwrap();
    app.type_text("id:chat-input", "记一笔：3.3|dining|AI历史账户")
        .unwrap();
    app.press("id:chat-send").unwrap();
    app.wait_for("text:AI 写入请求 · finance_record_expense")
        .unwrap();
    app.wait_for("id:confirm-approve-0").unwrap();
    app.wait_for("text:第一轮").unwrap();

    // 清空会话 drops bubbles and the pending card (nothing was written).
    app.press("id:chat-clear").unwrap();
    app.wait_for_gone("text:第一轮", std::time::Duration::from_secs(3))
        .unwrap();
    app.wait_for_gone(
        "text:AI 写入请求 · finance_record_expense",
        std::time::Duration::from_secs(3),
    )
    .unwrap();
    go_tab(&mut app, "tab-ledger");
    app.wait_for_gone(
        "text:AI历史账户  3.3 CNY",
        std::time::Duration::from_secs(2),
    )
    .unwrap();
}
