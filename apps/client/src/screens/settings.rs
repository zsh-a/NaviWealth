//! 设置: backend/account, AI profile, sync, encrypted backup, about.
//! Dense sections; every action reports its result inline.

use std::path::PathBuf;
use std::sync::Arc;

use nsh_base::{SheetEvent, theme};
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
            let _ = owner;
            auth_status.set(
                if user.is_some() {
                    "已登录 · 可以同步此设备的数据"
                } else {
                    "本地使用中 · 记账无需登录"
                }
                .to_owned(),
            );
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
    let data_version = use_context::<crate::state::DataVersion>().expect("data version");
    let backup_busy: Signal<bool> = signal(false);
    let backups: Signal<Vec<PathBuf>> = signal(Vec::new());
    let restore_path: Signal<Option<PathBuf>> = signal(None);
    let restore_staged: Signal<bool> = signal(false);
    let restore_open: Signal<bool> = signal(false);
    let auth_busy: Signal<bool> = signal(false);
    let backup_status: Signal<String> = signal(String::new());
    let backup_error: Signal<String> = signal(String::new());
    let sync_status: Signal<String> = signal(String::new());
    let sync_busy: Signal<bool> = signal(false);

    // Component-owned pumps survive individual event handlers. Network and
    // encryption jobs never update engine signals from a background thread.
    let auth_pipe = crate::bridge::EventPipe::new({
        move |result: Result<(), String>| {
            auth_busy.set(false);
            match result {
                Ok(()) => {
                    auth_status.set("已登录 · 可以同步此设备的数据".to_owned());
                    data_version.0.update(|v| *v += 1);
                }
                Err(error) => auth_status.set(format!("登录未完成：{error}")),
            }
        }
    });
    let sync_pipe = crate::bridge::EventPipe::new({
        move |result: Result<lifeos::sync::SyncOutcome, String>| {
            sync_busy.set(false);
            match result {
                Ok(outcome) => {
                    sync_status.set(format!(
                        "同步完成 · 上传 {} 条，接收 {} 条",
                        outcome.pushed, outcome.applied
                    ));
                    data_version.0.update(|v| *v += 1);
                }
                Err(error) => sync_status.set(format!("同步未完成：{error}")),
            }
        }
    });

    let (backup_commands, mut backup_rx) = tokio::sync::mpsc::unbounded_channel::<BackupCommand>();
    {
        let services = services.clone();
        spawn(async move {
            if let Ok(paths) = services.local_backups().await {
                backups.set(paths);
            }
            while let Some(command) = backup_rx.recv().await {
                backup_error.set(String::new());
                let passphrase = backup_passphrase.get();
                if passphrase.trim().is_empty() {
                    backup_status.set(String::new());
                    backup_error.set("请输入备份口令".to_owned());
                    continue;
                }
                backup_busy.set(true);
                match command {
                    BackupCommand::Export => {
                        backup_status.set("正在生成加密备份…".to_owned());
                        let dir = services.app_dir.clone().unwrap_or_else(std::env::temp_dir);
                        let path = dir.join("backups").join(format!(
                            "NaviWealth-{}.bak",
                            chrono::Utc::now().format("%Y%m%d-%H%M%S-%3f")
                        ));
                        match services.backup_export(path.clone(), passphrase).await {
                            Ok(_) => {
                                if let Ok(paths) = services.local_backups().await {
                                    backups.set(paths);
                                }
                                match crate::native_files::export_backup(&services, path).await {
                                    Ok(true) => {
                                        backup_status.set("加密备份已保存到你选择的位置".to_owned())
                                    }
                                    Ok(false) => backup_status
                                        .set("已取消导出；此设备保留了一份加密副本".to_owned()),
                                    Err(error) => backup_status
                                        .set(format!("已生成本机副本；导出未完成：{error}")),
                                }
                            }
                            Err(error) => backup_status.set(format!("备份未完成：{error}")),
                        }
                    }
                    BackupCommand::ChooseImport => {
                        match crate::native_files::import_backup().await {
                            Ok(Some(path)) => {
                                restore_path.set(Some(path));
                                restore_staged.set(true);
                                restore_open.set(true);
                                backup_status.set(String::new());
                                backup_error.set(String::new());
                            }
                            Ok(None) => backup_status.set("已取消选择备份".to_owned()),
                            Err(error) => backup_status.set(format!("无法选择备份：{error}")),
                        }
                    }
                    BackupCommand::Restore => {
                        if let Some(path) = restore_path.get() {
                            backup_status.set("正在验证并恢复备份…".to_owned());
                            match services.backup_import(path.clone(), passphrase).await {
                                Ok(_report) => {
                                    if restore_staged.get() {
                                        crate::native_files::cleanup_import(&path);
                                    }
                                    restore_path.set(None);
                                    restore_staged.set(false);
                                    restore_open.set(false);
                                    domains_state.0.set(services.enabled_domain_keys());
                                    data_version.0.update(|v| *v += 1);
                                    let (user, _) = services.auth_status().await;
                                    auth_status.set(
                                        if user.is_some() {
                                            "已登录 · 可以同步此设备的数据"
                                        } else {
                                            "本地使用中 · 记账无需登录"
                                        }
                                        .to_owned(),
                                    );
                                    backup_status.set("恢复完成 · 账户与记录已刷新".to_owned());
                                }
                                Err(error) => {
                                    log::debug!("encrypted backup restore failed: {error}");
                                    backup_status.set(String::new());
                                    backup_error.set("恢复未完成，现有数据已保留。请检查口令；若仍失败，请重新选择有效的备份文件。".to_owned());
                                }
                            }
                        }
                    }
                }
                backup_busy.set(false);
            }
        });
    }

    let auth_row = view()
        .flex_row()
        .gap_3()
        .child(
            ui::primary_button(
                "登录",
                {
                    let services = services.clone();
                    let tx = auth_pipe.sender();
                    move || {
                        if auth_busy.get() {
                            return;
                        }
                        auth_busy.set(true);
                        auth_status.set("正在登录…".to_owned());
                        let job = services.clone();
                        let url = base_url.get();
                        let mail = email.get();
                        let pass = password.get();
                        crate::bridge::spawn_job(&services, tx.clone(), move |tx| async move {
                            let _ = tx.send(job.login(&url, &mail, &pass).await);
                        });
                    }
                },
                "auth-login",
                Some(auth_busy),
            )
            .flex_1(),
        )
        .child(
            ui::secondary_button(
                "注册",
                {
                    let services = services.clone();
                    let tx = auth_pipe.sender();
                    move || {
                        if auth_busy.get() {
                            return;
                        }
                        if password.get().len() < 8 {
                            auth_status.set("密码至少需要 8 个字符".to_owned());
                            return;
                        }
                        auth_busy.set(true);
                        auth_status.set("正在注册…".to_owned());
                        let job = services.clone();
                        let url = base_url.get();
                        let mail = email.get();
                        let pass = password.get();
                        crate::bridge::spawn_job(&services, tx.clone(), move |tx| async move {
                            let _ = tx.send(job.register(&url, &mail, &pass).await);
                        });
                    }
                },
                "auth-register",
                Some(auth_busy),
            )
            .flex_1(),
        );

    let sync_row = ui::secondary_button(
        "立即同步",
        {
            let services = services.clone();
            let tx = sync_pipe.sender();
            move || {
                if sync_busy.get() {
                    return;
                }
                sync_busy.set(true);
                sync_status.set("正在同步…".to_owned());
                let job = services.clone();
                crate::bridge::spawn_job(&services, tx.clone(), move |tx| async move {
                    let _ = tx.send(job.sync_now().await.map_err(|e| e.to_string()));
                });
            }
        },
        "sync-now",
        Some(sync_busy),
    );
    let export_row = ui::primary_button(
        "导出加密备份",
        {
            let tx = backup_commands.clone();
            move || {
                let _ = tx.send(BackupCommand::Export);
            }
        },
        "backup-export",
        Some(backup_busy),
    );
    let import_row = ui::secondary_button(
        "选择文件恢复",
        {
            let tx = backup_commands.clone();
            move || {
                let _ = tx.send(BackupCommand::ChooseImport);
            }
        },
        "backup-import",
        Some(backup_busy),
    );
    let local_backups = when(
        move || !backups.get().is_empty(),
        move || {
            view()
                .gap_2()
                .child(
                    text("此设备的备份副本")
                        .text_sm()
                        .font_weight(FontWeight::MEDIUM),
                )
                .child(
                    text("卸载应用或设备损坏会丢失这些副本，请将重要备份导出到其他位置。")
                        .text_sm()
                        .text_color(move || theme().muted_foreground),
                )
                .child(each(
                    move || backups.get(),
                    |path: &PathBuf| path.clone(),
                    move |path: ReadSignal<PathBuf>, _| {
                        let value = path.get();
                        let label = value
                            .file_name()
                            .and_then(|name| name.to_str())
                            .unwrap_or("加密备份")
                            .to_owned();
                        ui::secondary_button_dyn(
                            label.clone(),
                            move || {
                                restore_path.set(Some(value.clone()));
                                restore_staged.set(false);
                                restore_open.set(true);
                                backup_status.set(String::new());
                                backup_error.set(String::new());
                            },
                            format!("backup-local-{label}"),
                            Some(backup_busy),
                        )
                    },
                ))
        },
    );
    let restore_confirmation = ui::app_sheet()
        .open(move || Some(restore_open.get()))
        .on_open_change(move |event: &SheetEvent| {
            if let SheetEvent::OpenChange(next, _) = event
                && !*next && !backup_busy.get() {
                    if restore_staged.get() && let Some(path) = restore_path.get() { crate::native_files::cleanup_import(&path); }
                    restore_path.set(None); restore_staged.set(false); restore_open.set(false);
            }
        })
        .child(ui::interactive_scroll().child(view().p_5().pb_safe_area_plus(px(20.0)).gap_4().bg(move || theme().background)
            .child(text("恢复这份备份？").text_xl().font_weight(FontWeight::SEMIBOLD))
            .child(text("恢复会替换此设备的现有记录。请先导出当前数据；口令错误或文件损坏时，现有数据会保留。")
                .text_base().text_color(move || theme().muted_foreground))
            .child(ui::secret_field("备份口令", "输入创建备份时的口令", backup_passphrase, "restore-passphrase"))
            .child(reactive_text(backup_status))
            .child(ui::error_line(backup_error))
            .child(ui::primary_button("确认恢复", {
                let tx = backup_commands.clone(); move || { let _ = tx.send(BackupCommand::Restore); }
            }, "backup-restore-confirm", Some(backup_busy)))
            .child(ui::secondary_button("取消", move || {
                if restore_staged.get() && let Some(path) = restore_path.get() { crate::native_files::cleanup_import(&path); }
                restore_path.set(None); restore_staged.set(false); restore_open.set(false);
            }, "backup-restore-cancel", Some(backup_busy)))));

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
        "本机数据库已加密，密钥文件保存在应用私有目录"
    } else {
        "开发模式：数据库未加密"
    };

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
            ui::interactive_scroll().flex_1().px_4().pb_6().child(
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
                        import_row,
                        local_backups,
                        reactive_text(backup_status),
                        ui::error_line(backup_error),
                    ))
                    .child(section!(
                        "关于",
                        text("NaviWealth · 日常财务"),
                        text(encryption.to_owned()),
                    )),
            ),
        )
        .child(restore_confirmation)
}

#[derive(Clone, Copy)]
enum BackupCommand {
    Export,
    ChooseImport,
    Restore,
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
