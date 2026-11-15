//! The software keyboard as the app experiences it. Every build remembers the
//! height it last reached: task sheets plan for that much, so they keep their
//! size and only move while it shows. A diagnostic build (`NW_DIAG=1` in the
//! build environment) also reports what showing it cost: how often the
//! environment changed, and how many frames came late while it moved.

use std::{
    cell::Cell,
    time::{Duration, Instant},
};

use nsh_core::prelude::*;

/// Diagnostics are compiled in only when the build asks for them.
pub const DIAGNOSTICS: bool = option_env!("NW_DIAG").is_some();

/// How long after the keyboard starts showing frames are sampled.
const SAMPLE: Duration = Duration::from_millis(700);

thread_local! {
    static LAST: Cell<f32> = const { Cell::new(0.0) };
    static SHOWN: Cell<f32> = const { Cell::new(0.0) };
}

/// The height the keyboard last reached, 0 before it has shown.
pub fn last_height() -> f32 {
    LAST.with(Cell::get)
}

/// What the keyboard cost since launch (diagnostic builds).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Report {
    /// Times it went from hidden to shown.
    pub shows: u32,
    /// Times its reported height changed, in total.
    pub keyboard_changes: u32,
    /// Times the window's size changed (not expected with the keyboard).
    pub window_changes: u32,
    /// Times the safe area changed.
    pub inset_changes: u32,
    /// Frames sampled during the last show.
    pub frames: u32,
    /// Of those, the frames that came late (over 1.5 refresh intervals).
    pub late: u32,
    /// The longest frame interval during the last show, in milliseconds.
    pub worst_ms: f32,
    /// The shortest interval seen, the display's refresh, in milliseconds.
    pub refresh_ms: f32,
}

fn report() -> Signal<Report> {
    global::<Report>()
}

/// The diagnostic report (reactive).
pub fn current() -> Report {
    report().get()
}

/// Starts following the keyboard; the app root calls it once.
pub fn track() {
    effect(move || {
        let height = keyboard_height().0;
        untracked(|| changed(height));
    });
    if DIAGNOSTICS {
        // The first run of each reads the launch value; it is not a change.
        let first = Cell::new(true);
        effect(move || {
            let _ = window();
            if !first.replace(false) {
                untracked(|| report().update(|r| r.window_changes += 1));
            }
        });
        let first = Cell::new(true);
        effect(move || {
            let _ = safe_area();
            if !first.replace(false) {
                untracked(|| report().update(|r| r.inset_changes += 1));
            }
        });
    }
}

fn changed(height: f32) {
    let before = SHOWN.with(|s| s.replace(height));
    if height > 0.0 {
        LAST.with(|l| l.set(height));
    }
    if !DIAGNOSTICS || before == height {
        return;
    }
    let showing = before == 0.0 && height > 0.0;
    report().update(|r| {
        r.keyboard_changes += 1;
        if showing {
            r.shows += 1;
        }
    });
    if showing {
        spawn(sample_frames());
    }
}

/// Frame intervals while the keyboard moves: late ones mean the engine
/// thread was busy when a frame was due.
async fn sample_frames() {
    let start: Instant = next_frame().await;
    let mut last = start;
    let mut intervals = Vec::new();
    while last.duration_since(start) < SAMPLE {
        let now: Instant = next_frame().await;
        intervals.push(now.duration_since(last).as_secs_f32() * 1000.0);
        last = now;
    }
    let refresh = intervals
        .iter()
        .copied()
        .filter(|ms| *ms >= 4.0)
        .fold(f32::MAX, f32::min);
    let refresh = if refresh == f32::MAX { 16.7 } else { refresh };
    let late = intervals.iter().filter(|ms| **ms > refresh * 1.5).count();
    let worst = intervals.iter().copied().fold(0.0, f32::max);
    report().update(|r| {
        r.frames = intervals.len() as u32;
        r.late = late as u32;
        r.worst_ms = worst;
        r.refresh_ms = refresh;
    });
}
