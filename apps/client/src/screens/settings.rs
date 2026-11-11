//! 设置: backend/account, AI profile, sync, encrypted backup, about.
//! Dense sections; every action reports its result inline.

use std::path::PathBuf;
use std::sync::Arc;

use nsh_base::theme;
use nsh_core::prelude::*;

use crate::ai::LlmProfile;
use crate::domains::{self, DomainsState};
use crate::state::Services;
use crate::ui;

/// A quiet section card: one surface per section, never nested. Children
/// are built before the macro and passed as expressions.
macro_rules! section {
    ($title:expr $(, $child:expr)* $(,)?) => {{
        let mut card = view()
            .gap_3()
            .p_4()
            .rounded(move || px(crate::ui::card_radius()))
            .bg(move || theme().card)
            .child(
                text($title)
                    .text_sm()
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(move || theme().muted_foreground),
            );
        $( card = card.child($child); )*
        card
    }};
}

fn reactive_text(signal: Signal<String>) -> impl IntoElement {
    text(move || signal.get())
}

#[allow(non_snake_case)]
pub fn SettingsScreen() -> impl IntoElement {
    let services: Arc<Services> = use_context::<Arc<Services>>().expect("services context");
    let domains_state: DomainsState = use_context::<DomainsState>().expect("domains state context");

    // Backend / account.
    let base_url: Signal<String> = signal(String::new());
    let email: Signal<String> = signal(String::new());
    let password: Signal<String> = signal(String::new());
    let auth_status: Signal<String> = signal(String::new());
    {
        let services = services.clone();
        spawn(async move {
            let url = services.base_url().await;
            base_url.set(url);
            let (user, owner) = services.auth_status().await;
            auth_status.set(match user {
                Some(user) => format!("已登录 {user}（数据空间 {owner}）"),
                None => format!("本地模式（数据空间 {owner}）"),
            });
        });
    }

    // AI profile.
    let ai_provider: Signal<String> = signal("openai".to_owned());
    let ai_base_url: Signal<String> = signal(String::new());
    let ai_model: Signal<String> = signal(String::new());
    let ai_key: Signal<String> = signal(String::new());
    let ai_status: Signal<String> = signal(String::new());
    {
        let services = services.clone();
        spawn(async move {
            if let Some(profile) = services.llm_profile().await {
                ai_provider.set(profile.provider.clone());
                ai_base_url.set(profile.base_url.clone());
                ai_model.set(profile.model.clone());
                ai_key.set(profile.api_key.clone());
                ai_status.set("已保存".to_owned());
            } else {
                ai_status.set("未配置：请填入你自己的模型服务".to_owned());
            }
        });
    }

    // Backup + sync.
    let backup_passphrase: Signal<String> = signal(String::new());
    let import_path: Signal<String> = signal(String::new());
    let backup_status: Signal<String> = signal(String::new());
    let sync_status: Signal<String> = signal(String::new());
    let sync_busy: Signal<bool> = signal(false);

    // Pipes: created under the screen's owner so their callbacks may set
    // signals; background jobs report through them.
    let _register_pipe = crate::bridge::EventPipe::new({
        move |result: Result<(), String>| match result {
            Ok(()) => auth_status.set("注册成功，已绑定数据空间".to_owned()),
            Err(e) => auth_status.set(format!("注册失败：{e}")),
        }
    });
    let _login_pipe = crate::bridge::EventPipe::new({
        move |result: Result<(), String>| match result {
            Ok(()) => auth_status.set("登录成功，已绑定数据空间".to_owned()),
            Err(e) => auth_status.set(format!("登录失败：{e}")),
        }
    });
    let sync_pipe = crate::bridge::EventPipe::new({
        move |result: Result<lifeos::sync::SyncOutcome, String>| {
            sync_busy.set(false);
            match result {
                Ok(outcome) => sync_status.set(format!(
                    "推送 {} 行，应用 {} 行，游标 {}",
                    outcome.pushed, outcome.applied, outcome.cursor
                )),
                Err(e) => sync_status.set(format!("同步失败：{e}")),
            }
        }
    });
    let _export_pipe = crate::bridge::EventPipe::new({
        move |result: Result<String, String>| match result {
            Ok(p) => backup_status.set(format!("已导出：{p}")),
            Err(e) => backup_status.set(format!("导出失败：{e}")),
        }
    });
    let import_pipe = crate::bridge::EventPipe::new({
        move |result: Result<lifeos::backup::RestoreReport, String>| match result {
            Ok(report) => backup_status.set(format!(
                "已恢复 {} 张表 {} 行（时钟推进到 {}）",
                report.tables,
                report.rows,
                report.max_hlc.as_deref().unwrap_or("-")
            )),
            Err(e) => backup_status.set(format!("恢复失败：{e}")),
        }
    });

    // ---- Children built up front (locals keep the sections readable). ----

    let auth_row = view()
        .flex_row()
        .gap_3()
        .child(
            ui::primary_button(
                "注册",
                {
                    let services = services.clone();
                    move || {
                        let services = services.clone();
                        let url = base_url.get().trim().to_owned();
                        let email_text = email.get().trim().to_owned();
                        let password_text = password.get().to_owned();
                        spawn(async move {
                            match services.register(&url, &email_text, &password_text).await {
                                Ok(()) => auth_status.set("注册成功，已绑定数据空间".to_owned()),
                                Err(e) => auth_status.set(format!("注册失败：{e}")),
                            }
                        });
                    }
                },
                "auth-register",
                None,
            )
            .flex_1(),
        )
        .child(
            ui::secondary_button(
                "登录",
                {
                    let services = services.clone();
                    move || {
                        let services = services.clone();
                        let url = base_url.get().trim().to_owned();
                        let email_text = email.get().trim().to_owned();
                        let password_text = password.get().to_owned();
                        spawn(async move {
                            match services.login(&url, &email_text, &password_text).await {
                                Ok(()) => auth_status.set("登录成功，已绑定数据空间".to_owned()),
                                Err(e) => auth_status.set(format!("登录失败：{e}")),
                            }
                        });
                    }
                },
                "auth-login",
                None,
            )
            .flex_1(),
        );

    let sync_row = view().flex_row().gap_3().child(
        ui::secondary_button(
            "立即同步",
            {
                let services = services.clone();
                move || {
                    if sync_busy.get() {
                        return;
                    }
                    sync_busy.set(true);
                    let _sync_status = sync_status;
                    let _sync_busy = sync_busy;
                    let job_services = services.clone();
                    crate::bridge::spawn_job(
                        &services,
                        sync_pipe.sender(),
                        move |tx: tokio::sync::mpsc::UnboundedSender<
                            Result<lifeos::sync::SyncOutcome, String>,
                        >| async move {
                            let result = job_services.sync_now().await.map_err(|e| e.to_string());
                            let _ = tx.send(result);
                        },
                    );
                }
            },
            "sync-now",
            Some(sync_busy),
        )
        .flex_1(),
    );

    let export_row = view().flex_row().gap_3().child(
        ui::secondary_button(
            "导出备份",
            {
                let services = services.clone();
                move || {
                    let services = services.clone();
                    let passphrase = backup_passphrase.get();
                    spawn(async move {
                        if passphrase.is_empty() {
                            backup_status.set("请先输入备份口令".to_owned());
                            return;
                        }
                        let dir = services.app_dir.clone().unwrap_or_else(std::env::temp_dir);
                        let path = dir.join("backups").join(format!(
                            "naviwealth-{}.bak",
                            chrono::Utc::now().format("%Y%m%d-%H%M%S")
                        ));
                        match services.backup_export(path, passphrase).await {
                            Ok(p) => backup_status.set(format!("已导出：{p}")),
                            Err(e) => backup_status.set(format!("导出失败：{e}")),
                        }
                    });
                }
            },
            "backup-export",
            None,
        )
        .flex_1(),
    );

    let import_row = ui::secondary_button(
        "从备份恢复",
        {
            let services = services.clone();
            move || {
                let path = PathBuf::from(import_path.get().trim());
                let passphrase = backup_passphrase.get();
                let _backup_status = backup_status;
                let job_services = services.clone();
                crate::bridge::spawn_job(
                    &services,
                    import_pipe.sender(),
                    move |tx: tokio::sync::mpsc::UnboundedSender<
                        Result<lifeos::backup::RestoreReport, String>,
                    >| async move {
                        let result = job_services.backup_import(path, passphrase).await;
                        let _ = tx.send(result);
                    },
                );
            }
        },
        "backup-import",
        None,
    );

    let ai_save_button = ui::primary_button(
        "保存 AI 配置",
        {
            let services = services.clone();
            move || {
                let services = services.clone();
                let profile = LlmProfile {
                    provider: ai_provider.get(),
                    base_url: ai_base_url.get().trim().to_owned(),
                    model: ai_model.get().trim().to_owned(),
                    api_key: ai_key.get().trim().to_owned(),
                };
                spawn(async move {
                    services.save_llm_profile(profile.clone()).await;
                    ai_status.set(if profile.is_complete() {
                        "已保存（密钥只存在本机数据库）".to_owned()
                    } else {
                        "已保存，但配置不完整".to_owned()
                    });
                });
            }
        },
        "ai-save",
        None,
    );

    let encryption = if services.encrypted {
        "数据库已加密（SQLCipher，密钥在系统钥匙串/密钥库）"
    } else {
        "开发模式：数据库未加密"
    };
    let device = services.device_id.clone();

    // Opt-in domains: one toggle row each (finance is always on and not
    // listed here).
    let domain_rows = view().gap_2().children(
        domains::OPTIONAL_DOMAINS
            .map(|spec| domain_toggle_row(spec, domains_state, services.clone())),
    );

    view()
        .flex_1()
        .child(
            view()
                .px_4()
                .py_3()
                .child(text("设置").text_xl().font_weight(FontWeight::BOLD)),
        )
        .child(
            scroll().flex_1().px_4().pb_6().child(
                view()
                    .gap_4()
                    .child(section!(
                        "同步与账户",
                        reactive_text(auth_status),
                        ui::text_field(
                            "后端地址",
                            "http://127.0.0.1:8787",
                            base_url,
                            "setting-base-url"
                        ),
                        ui::text_field("邮箱", "you@example.com", email, "auth-email"),
                        ui::secret_field("密码", "至少 8 位", password, "auth-password"),
                        auth_row,
                    ))
                    .child(section!(
                        "领域",
                        text("Finance（财务）恒开；其余领域按需启用，启用后出现对应标签页。")
                            .text_sm()
                            .text_color(move || theme().muted_foreground),
                        domain_rows,
                    ))
                    .child(section!(
                        "智能",
                        provider_picker(ai_provider),
                        ui::text_field("Base URL", "留空使用官方地址", ai_base_url, "ai-base-url"),
                        ui::text_field("模型", "例如 claude-sonnet-4-5", ai_model, "ai-model"),
                        ui::secret_field("API Key", "仅保存在本机", ai_key, "ai-key"),
                        reactive_text(ai_status),
                        ai_save_button,
                    ))
                    .child(section!(
                        "同步与备份",
                        sync_row,
                        reactive_text(sync_status),
                        ui::secret_field(
                            "备份口令",
                            "加密整库备份",
                            backup_passphrase,
                            "backup-passphrase"
                        ),
                        export_row,
                        ui::text_field(
                            "备份文件路径",
                            "…/naviwealth-….bak",
                            import_path,
                            "backup-import-path"
                        ),
                        import_row,
                        reactive_text(backup_status),
                    ))
                    .child(section!(
                        "关于",
                        text("NaviWealth 客户端 0.1.0（nsh Rust 重写 · 阶段 1+2）"),
                        text(encryption.to_owned()),
                        text(format!("设备 {device}")),
                    )),
            ),
        )
}

fn provider_picker(selected: Signal<String>) -> impl IntoElement {
    let options: [&'static str; 2] = ["anthropic", "openai"];
    view().flex_row().gap_2().children(
        options
            .iter()
            .map(|&option| {
                ui::chip(
                    option.to_owned(),
                    move || selected.get() == option,
                    move || selected.set(option.to_owned()),
                )
            })
            .collect::<Vec<_>>(),
    )
}

/// One opt-in domain: label + reactive enable/disable button. The switch
/// updates the shared signal immediately (tabs follow at once) and
/// persists to the settings KV, mirroring onto `Services` so sync and the
/// AI tools pick it up.
fn domain_toggle_row(
    spec: &'static domains::DomainSpec,
    domains: DomainsState,
    services: Arc<Services>,
) -> impl IntoElement {
    let is_on = move || domains.is_enabled(spec.key);
    let label = move || {
        if is_on() {
            "已启用".to_owned()
        } else {
            "已停用".to_owned()
        }
    };
    view()
        .flex_row()
        .items_center()
        .gap_3()
        .child(
            view()
                .flex_1()
                .child(text(spec.label).text_base().font_weight(FontWeight::MEDIUM)),
        )
        .child(ui::state_button(
            label,
            move || {
                let next = !is_on();
                domains.0.update(|list| {
                    if next {
                        if !list.contains(&spec.key) {
                            list.push(spec.key);
                        }
                    } else {
                        list.retain(|key| *key != spec.key);
                    }
                });
                let services = services.clone();
                spawn(async move {
                    domains::set_enabled(&services, spec, next).await;
                });
            },
            spec.toggle_test_id,
            true,
        ))
}
