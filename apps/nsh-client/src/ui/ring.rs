//! The day's energy as one ring: its arc is how far the energy goes toward
//! the goal (the whole ring without one), divided by where the energy came
//! from (protein, carbs, fat, the rest). Each segment's ends are animated
//! values, so a change sweeps natively from the old ring to the new one.

use std::f32::consts::{FRAC_PI_2, TAU};

use nsh_core::{canvas::LineCap, element::AnimatedValue, prelude::*};

use super::theme::{color, motion};

/// What the ring shows.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct RingData {
    /// Protein, carbs, fat and other energy as shares of the energy eaten
    /// (summing to 1), or all 0 for nothing eaten.
    pub shares: [f32; 4],
    /// How much of the ring the energy fills, from 0 to 1.
    pub fill: f32,
}

/// The segments' colors, in drawing order.
pub const SEGMENT_COLORS: [AdaptiveColor; 4] =
    [color::PROTEIN, color::CARBS, color::FAT, color::OTHER];

/// The gap between neighboring segments, in radians.
const GAP: f32 = 0.055;

/// Where each segment starts and ends (radians, clockwise from 12 o'clock).
pub fn segment_angles(data: RingData) -> [(f32, f32); 4] {
    let top = -FRAC_PI_2;
    let sweep = TAU * data.fill.clamp(0.0, 1.0);
    let visible = data.shares.iter().filter(|share| **share > 0.0).count();
    let mut cursor = 0.0;
    let mut angles = [(top, top); 4];
    for (angle, share) in angles.iter_mut().zip(data.shares) {
        let span = sweep * share.clamp(0.0, 1.0);
        let gap = if visible > 1 {
            GAP.min(span * 0.5)
        } else {
            0.0
        };
        *angle = (top + cursor, top + cursor + span - gap);
        cursor += span;
    }
    angles
}

/// A ring `size` points wide with a `stroke`-thick line, following `data`.
pub fn energy_ring(
    size: f32,
    stroke: f32,
    data: impl Fn() -> RingData + 'static,
) -> impl IntoElement {
    let top = -FRAC_PI_2;
    let ends: [(AnimatedValue, AnimatedValue); 4] =
        std::array::from_fn(|_| (animated_value(top), animated_value(top)));
    effect(move || {
        let angles = segment_angles(data());
        let still = untracked(reduce_motion);
        for ((start, end), (to_start, to_end)) in ends.iter().zip(angles) {
            if still {
                start.set(to_start);
                end.set(to_end);
            } else {
                start.timing(to_start, motion::SLOWER, Easing::EaseOut);
                end.timing(to_end, motion::SLOWER, Easing::EaseOut);
            }
        }
    });
    let center = size / 2.0;
    let radius = (size - stroke) / 2.0;
    canvas(move || {
        let mut painter = Painter::new()
            .line_width(stroke)
            .line_cap(LineCap::Butt)
            .stroke_color(nsh_core::prelude::color(color::TRACK))
            .begin_path()
            .arc(center, center, radius, 0.0, TAU)
            .stroke();
        for ((start, end), tint) in ends.iter().zip(SEGMENT_COLORS) {
            painter = painter
                .stroke_color(nsh_core::prelude::color(tint))
                .begin_path()
                .arc(center, center, radius, start, end)
                .stroke();
        }
        painter
    })
    .size(px(size))
    .accessibility_elements_hidden(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn segments_follow_each_other_with_gaps() {
        let angles = segment_angles(RingData {
            shares: [0.25, 0.5, 0.25, 0.0],
            fill: 1.0,
        });
        let top = -FRAC_PI_2;
        assert_eq!(angles[0].0, top);
        assert!((angles[0].1 - (top + TAU * 0.25 - GAP)).abs() < 1e-5);
        assert!((angles[1].0 - (top + TAU * 0.25)).abs() < 1e-5);
        assert!((angles[2].1 - (top + TAU - GAP)).abs() < 1e-5);
        // An empty segment has no length.
        assert_eq!(angles[3].0, angles[3].1);
    }

    #[test]
    fn a_single_segment_closes_the_ring_and_fill_shortens_it() {
        let whole = segment_angles(RingData {
            shares: [0.0, 1.0, 0.0, 0.0],
            fill: 1.0,
        });
        assert!((whole[1].1 - whole[1].0 - TAU).abs() < 1e-5);
        let half = segment_angles(RingData {
            shares: [0.5, 0.5, 0.0, 0.0],
            fill: 0.5,
        });
        assert!((half[1].1 - (-FRAC_PI_2 + TAU * 0.5 - GAP)).abs() < 1e-5);
        assert!(
            segment_angles(RingData::default())
                .iter()
                .all(|(start, end)| start == end)
        );
    }
}
