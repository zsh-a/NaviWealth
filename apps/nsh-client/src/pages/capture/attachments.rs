use super::*;

static NEXT_IMAGE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

pub(super) fn pick(
    draft: Signal<Draft>,
    id: Stored<String>,
    picking: Signal<bool>,
    error: Signal<Option<String>>,
) {
    picking.set(true);
    let remaining = draft.with_untracked(|d| MAX_ATTACHMENTS.saturating_sub(d.image_names().len()));
    if remaining == 0 {
        picking.set(false);
        return;
    }
    // Keep source detail: capture normalization strips metadata and bounds
    // memory/bytes without the picker's preliminary lossy resize.
    let picked = pick_images(PickRequest::new(true, remaining as u32));
    spawn(async move {
        for file in picked.await.into_iter().take(remaining) {
            let bytes = file.data.to_vec();
            let prepared = blocking(move || photos::prepare_capture(&bytes))
                .await
                .ok()
                .flatten();
            if let Some((upload, _)) = prepared {
                let serial = NEXT_IMAGE.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                let extension = if upload.starts_with(b"\x89PNG") {
                    "png"
                } else {
                    "jpg"
                };
                let name = id.with(|id| format!("{id}-{}-{serial}.{extension}", clock::now_ms()));
                if let Err(failure) = photos::keep(&name, &upload) {
                    log::error!("capture: image could not be kept: {failure}");
                    error.set(Some(s().error_transaction_storage.into()));
                    continue;
                }
                draft.update(|d| {
                    if d.photo.is_none() && d.transcript.is_empty() {
                        d.photo = Some(name.clone());
                    }
                    d.attachments.push(name);
                });
            } else {
                error.set(Some(s().failure_photo.0.into()));
            }
        }
        picking.set(false);
    });
}
