//! A successful save sends small copies of the reviewed cards into their
//! actual dock targets. Only the decoration waits for the native sheet exit.
use super::details;
use crate::{
    domain::capture::{Draft, Record},
    nav::Tab,
    pages::dock::tab_index,
    ui::{Icon, Type, Typo, color, icon, motion, radius},
};
use nsh_core::{
    Haptic,
    element::{ElementRef, Timing},
    prelude::*,
};

#[derive(Clone, Copy)]
pub(in crate::pages) struct Flights {
    pub tabs: [ElementRef; 4],
    frame: ElementRef,
    owner: Owner,
    editor_open: Signal<bool>,
    sequence: Stored<u64>,
    ghosts: Signal<Vec<Ghost>>,
}

#[derive(Clone, PartialEq)]
struct Ghost {
    glyph: Icon,
    figure: String,
    start: (f32, f32),
    end: (f32, f32),
}

#[derive(Clone, Copy)]
struct Origins(Stored<Vec<ElementRef>>);
#[derive(Clone, Copy)]
struct FirstCard(Stored<bool>);

pub(in crate::pages) fn provide() -> Flights {
    let host = Flights {
        tabs: std::array::from_fn(|_| element_ref()),
        frame: element_ref(),
        owner: Owner::current(),
        editor_open: signal(false),
        sequence: stored(0),
        ghosts: signal(Vec::new()),
    };
    provide_context(host);
    host
}

impl Flights {
    /// Retiring a batch also fences late measurement replies after Undo or
    /// opening another editor. It never changes the receipt or selected tab.
    fn clear(self) {
        self.sequence.replace(self.sequence.get().wrapping_add(1));
        self.ghosts.set(Vec::new());
    }
}

#[derive(Clone, Copy)]
pub(super) struct CaptureFlight {
    host: Flights,
    origins: Origins,
}

pub(super) fn opened(initial: &Draft) -> Option<CaptureFlight> {
    provide_context(FirstCard(stored(!initial.records.is_empty())));
    let origins = Origins(stored(Vec::new()));
    provide_context(origins);
    use_context::<Flights>().map(|host| {
        host.clear();
        host.editor_open.set(true);
        cleanup(move || {
            host.editor_open.try_set(false);
        });
        CaptureFlight { host, origins }
    })
}

pub(super) fn first_card() {
    if let Some(first) = use_context::<FirstCard>()
        && use_context::<super::Sheets>().is_some_and(|sheets| sheets.capture.get_untracked())
        && !first.0.replace(true)
    {
        haptic(Haptic::Selection);
    }
}

pub(super) fn origin(index: usize) -> ElementRef {
    let target = element_ref();
    if let Some(positions) = use_context::<Origins>() {
        positions.0.with(|refs| {
            if refs.len() <= index {
                refs.resize(index + 1, target);
            }
            refs[index] = target;
        });
    }
    target
}

pub(super) fn destination(record: &Record) -> Tab {
    match record {
        Record::Money { draft, .. } if draft.kind == navi_finance::recognition::Kind::Transfer => {
            Tab::Assets
        }
        Record::Money { .. } => Tab::Records,
        Record::Meal { day, .. } | Record::Weight { day, .. } => {
            if *day == crate::data::clock::today() {
                Tab::Today
            } else {
                Tab::Records
            }
        }
        Record::Trade { .. } | Record::Price { .. } | Record::Balance { .. } => Tab::Assets,
        Record::Note { .. } => Tab::Review,
    }
}

pub(super) fn saved(flight: CaptureFlight, draft: &Draft, reduced: bool) {
    let CaptureFlight { host, origins } = flight;
    host.clear();
    if reduced {
        return;
    }
    let sequence = host.sequence.get();
    let frame = host.frame.measure();
    let rows = origins.0.with(|refs| {
        draft
            .records
            .iter()
            .zip(refs.iter())
            .map(|(r, source)| {
                let (glyph, _, figure) = details::headline(r);
                let target = host.tabs[tab_index(destination(r))].measure();
                let source = source.measure();
                async move { (glyph, figure, source.await, target.await) }
            })
            .collect::<Vec<_>>()
    });
    host.owner.run(move || {
        spawn(async move {
            let (frame, rows) = futures::join!(frame, futures::future::join_all(rows));
            let Some(frame) = frame else {
                return;
            };
            if host.sequence.get() != sequence {
                return;
            }
            let width = frame.frame.size.width.0;
            let height = frame.frame.size.height.0;
            if width < 100.0 || height < 140.0 {
                return;
            }
            let ghosts = rows
                .into_iter()
                .filter_map(|(glyph, figure, source, target)| {
                    let target = target?;
                    let x = target.page.x.0 + target.frame.size.width.0 / 2.0 - frame.page.x.0;
                    let y = target.page.y.0 + target.frame.size.height.0 / 2.0 - frame.page.y.0;
                    let (sx, sy) = source.map_or((width / 2.0, height * 0.5), |s| {
                        (
                            s.page.x.0 + s.frame.size.width.0 / 2.0 - frame.page.x.0,
                            s.page.y.0 + s.frame.size.height.0.min(96.0) / 2.0 - frame.page.y.0,
                        )
                    });
                    // Scrolled-off records emerge from the nearest visible edge of the review.
                    Some(Ghost {
                        glyph,
                        figure,
                        start: (
                            sx.clamp(44.0, width - 44.0),
                            sy.clamp(64.0, (y - 80.0).max(64.0)),
                        ),
                        end: (x, y),
                    })
                })
                .collect();
            host.ghosts.set(ghosts);
        })
    });
}

pub(super) fn cancel(flight: Option<CaptureFlight>) {
    if let Some(flight) = flight {
        flight.host.clear();
    }
}

pub(in crate::pages) fn layer(host: Flights) -> impl IntoElement {
    view()
        .absolute()
        .inset_0()
        .element_ref(&host.frame)
        .pointer_events(PointerEvents::None)
        .accessibility_elements_hidden(true)
        .child(dynamic(move || {
            let ghosts = host.ghosts.get();
            if !ghosts.is_empty() && reduce_motion() {
                host.clear();
                return view().into_element();
            }
            if ghosts.is_empty() || host.editor_open.get() {
                return view().into_element();
            }
            let sequence = host.sequence.get();
            let last = ghosts.len() - 1;
            view()
                .absolute()
                .inset_0()
                .test_id("capture-save-flight")
                .children(ghosts.into_iter().enumerate().map(|(i, g)| {
                    let progress = animated_value(0.0);
                    let finished = progress.timing_with(
                        1.0,
                        Timing {
                            duration_ms: motion::SLOW,
                            delay_ms: (i.min(4) as f32) * 24.0,
                            easing: Easing::EaseInOut,
                            ..motion::ENTER
                        },
                    );
                    if i == last {
                        spawn(async move {
                            finished.await;
                            if host.sequence.get() == sequence {
                                host.ghosts.set(Vec::new());
                            }
                        });
                    }
                    let (sx, sy) = g.start;
                    let (tx, ty) = g.end;
                    view()
                        .absolute()
                        .left(px(sx - 60.0))
                        .top(px(sy - 19.0))
                        .w(px(120.0))
                        .h(px(38.0))
                        .bind_translate_x(&progress.interpolate(&[0.0, 1.0], &[0.0, tx - sx]))
                        .bind_translate_y(
                            &progress.interpolate(
                                &[0.0, 0.28, 1.0],
                                &[0.0, (ty - sy) * 0.1 - 8.0, ty - sy],
                            ),
                        )
                        .bind_scale(&progress.interpolate(&[0.0, 0.35, 1.0], &[1.0, 0.88, 0.12]))
                        .bind_opacity(
                            &progress.interpolate(&[0.0, 0.12, 0.80, 1.0], &[0.0, 1.0, 1.0, 0.0]),
                        )
                        .items_center()
                        .justify_center()
                        .flex_row()
                        .gap_1()
                        .px_2()
                        .rounded(px(radius::WELL))
                        .bg(color::SURFACE)
                        .border(px(1.0))
                        .border_color(color::LINE_STRONG)
                        .child(icon(g.glyph, 15.0, color::ACCENT_INK))
                        .child(
                            text(g.figure)
                                .typo(Type::Subhead)
                                .text_color(color::INK)
                                .tabular_nums()
                                .flex_shrink(1.0)
                                .number_of_lines(1),
                        )
                }))
                .into_element()
        }))
}
