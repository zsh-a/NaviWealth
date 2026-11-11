//! 笔记: the KnowledgeOS screen — a dense note list with a lightweight
//! capture sheet (title + content + optional source).

use std::sync::Arc;

use naviwealth_knowledge::models::Note;
use nsh_base::{SheetEvent, sheet, theme};
use nsh_core::prelude::*;

use crate::state::Services;
use crate::ui;

fn fetch_rows(services: &Arc<Services>, rows: Signal<Vec<Note>>, load_error: Signal<String>) {
    let services = services.clone();
    spawn(async move {
        match services.notes(50).await {
            Ok(list) => {
                rows.set(list);
                load_error.set(String::new());
            }
            Err(e) => load_error.set(e),
        }
    });
}

#[allow(non_snake_case)]
pub fn KnowledgeScreen() -> impl IntoElement {
    let services: Arc<Services> = use_context::<Arc<Services>>().expect("services context");

    let rows: Signal<Vec<Note>> = signal(Vec::new());
    let load_error: Signal<String> = signal(String::new());
    let data_version = use_context::<crate::state::DataVersion>().expect("data version");

    fetch_rows(&services, rows, load_error);
    // Reload whenever any write bumps the shared data version.
    {
        let services = services.clone();
        effect(move || {
            let _generation = data_version.0.get();
            fetch_rows(&services, rows, load_error);
        });
    }

    let sheet_open: Signal<bool> = signal(false);

    view()
        .flex_1()
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_3()
                .px_4()
                .py_3()
                .child(
                    text("笔记")
                        .text_xl()
                        .font_weight(FontWeight::BOLD)
                        .flex_1(),
                )
                .child(ui::primary_button(
                    "＋ 笔记",
                    move || sheet_open.set(true),
                    "open-note-form",
                    None,
                )),
        )
        .child(
            ui::interactive_scroll()
                .flex_1()
                .px_4()
                .pb_4()
                .child(ui::error_line(load_error))
                .child(each(
                    move || rows.get(),
                    |note: &Note| note.id.clone(),
                    move |note: ReadSignal<Note>, _index: ReadSignal<usize>| note_row(note),
                )),
        )
        .child(note_form_sheet(services, sheet_open, data_version.0))
}

fn note_row(note: ReadSignal<Note>) -> impl IntoElement {
    let title = move || note.get().title.clone();
    let meta = move || {
        let n = note.get();
        let source = n
            .source
            .as_deref()
            .filter(|s| !s.is_empty())
            .map(|s| s.to_owned())
            .unwrap_or_else(|| "无来源".to_owned());
        format!("{} · {}", ui::ymd(n.created_at), source)
    };
    let content = move || {
        let n = note.get();
        let first_line = n.content.lines().next().unwrap_or("").trim().to_owned();
        if first_line.is_empty() {
            "（空）".to_owned()
        } else {
            first_line
        }
    };
    view()
        .gap_1()
        .p_4()
        .rounded(move || px(crate::ui::card_radius()))
        .bg(move || theme().card)
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(
                    text(title)
                        .text_base()
                        .font_weight(FontWeight::MEDIUM)
                        .flex_1(),
                )
                .child(
                    text(meta)
                        .text_xs()
                        .text_color(move || theme().muted_foreground),
                ),
        )
        .child(
            text(content)
                .text_sm()
                .text_color(move || theme().muted_foreground),
        )
}

fn note_form_sheet(
    services: Arc<Services>,
    open: Signal<bool>,
    reload: Signal<u64>,
) -> impl IntoElement {
    let title: Signal<String> = signal(String::new());
    let content: Signal<String> = signal(String::new());
    let source: Signal<String> = signal(String::new());
    let save_error: Signal<String> = signal(String::new());
    let saving: Signal<bool> = signal(false);

    sheet()
        .open(move || Some(open.get()))
        .on_open_change(move |event: &SheetEvent| {
            if let SheetEvent::OpenChange(next, _) = event {
                open.set(*next);
            }
        })
        .child(
            view()
                .gap_3()
                .p_5()
                .rounded_t(px(16.0))
                .bg(move || theme().background)
                .child(text("新建笔记").text_lg().font_weight(FontWeight::SEMIBOLD))
                .child(ui::text_field("标题", "记点什么", title, "note-title"))
                .child(ui::text_field(
                    "内容",
                    "正文（第一行会显示在列表）",
                    content,
                    "note-content",
                ))
                .child(ui::text_field(
                    "来源（可选）",
                    "链接 / 书名 / 对话",
                    source,
                    "note-source",
                ))
                .child(ui::error_line(save_error))
                .child(ui::primary_button(
                    "保存",
                    move || {
                        if title.get().trim().is_empty() {
                            save_error.set("请输入标题".to_owned());
                            return;
                        }
                        saving.set(true);
                        let services = services.clone();
                        let title_text = title.get().trim().to_owned();
                        let content_text = content.get().trim().to_owned();
                        let source_text = source.get().trim().to_owned();
                        let source_value = (!source_text.is_empty()).then_some(source_text);
                        let save_error = save_error;
                        let saving = saving;
                        let open = open;
                        let reload = reload;
                        let title = title;
                        let content = content;
                        let source = source;
                        spawn(async move {
                            match services
                                .create_note(title_text, content_text, source_value)
                                .await
                            {
                                Ok(_) => {
                                    saving.set(false);
                                    open.set(false);
                                    title.set(String::new());
                                    content.set(String::new());
                                    source.set(String::new());
                                    save_error.set(String::new());
                                    reload.update(|v| *v += 1);
                                }
                                Err(e) => {
                                    saving.set(false);
                                    save_error.set(e);
                                }
                            }
                        });
                    },
                    "note-save",
                    Some(saving),
                )),
        )
}
