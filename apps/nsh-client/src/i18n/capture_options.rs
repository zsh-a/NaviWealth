use super::s;
use crate::domain::recognition::Lang;

pub(crate) struct Copy {
    pub options: &'static str,
    pub live: &'static str,
    pub live_note: &'static str,
    pub context: &'static str,
    pub context_note: &'static str,
    pub fast: &'static str,
    pub fast_default: &'static str,
    pub preview_title: &'static str,
    pub consulting: &'static str,
    pub preview_failed: &'static str,
    pub open_destination: &'static str,
}
pub(crate) fn copy() -> Copy {
    match s().lang {
        Lang::Zh => Copy {
            options: "快速录入",
            live: "边写边懂",
            live_note: "暂停输入后，将未发送的文字交给预览模型。照片仅在点发送时传出。预览目标",
            context: "参考最近记录和收藏",
            context_note: "点发送时，允许当前模型参考近期餐食、收支、体重、所持证券和收藏餐食。仅供起草。",
            fast: "预览模型（选填）",
            fast_default: "使用当前模型",
            preview_title: "输入预览",
            consulting: "正在理解文字…",
            preview_failed: "暂时无法预览，仍可发送录入。",
            open_destination: "发送后可前往相应页面查看。",
        },
        Lang::En => Copy {
            options: "Quick capture",
            live: "Preview as I type",
            live_note: "After a pause, send unsent text to this model. Photos are sent only when you tap Send. Preview target",
            context: "Use recent records and favorites",
            context_note: "On Send, let this model use recent meals, transactions, weight, held securities and favorite meals to draft records.",
            fast: "Preview model (optional)",
            fast_default: "Use current model",
            preview_title: "Typing preview",
            consulting: "Reading your text…",
            preview_failed: "Preview unavailable. You can still send this entry.",
            open_destination: "Send to open the relevant page.",
        },
    }
}
