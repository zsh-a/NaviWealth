---
name: NaviWealth LifeOS
colors:
  surface: '#f7f9fb'
  surface-dim: '#d8dadc'
  surface-bright: '#f7f9fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f4f6'
  surface-container: '#eceef0'
  surface-container-high: '#e6e8ea'
  surface-container-highest: '#e0e3e5'
  on-surface: '#191c1e'
  on-surface-variant: '#45474c'
  inverse-surface: '#2d3133'
  inverse-on-surface: '#eff1f3'
  outline: '#75777d'
  outline-variant: '#c5c6cd'
  surface-tint: '#545f73'
  primary: '#091426'
  on-primary: '#ffffff'
  primary-container: '#1e293b'
  on-primary-container: '#8590a6'
  inverse-primary: '#bcc7de'
  secondary: '#006c49'
  on-secondary: '#ffffff'
  secondary-container: '#6cf8bb'
  on-secondary-container: '#00714d'
  tertiary: '#001624'
  on-tertiary: '#ffffff'
  tertiary-container: '#002c42'
  on-tertiary-container: '#0099d9'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d8e3fb'
  primary-fixed-dim: '#bcc7de'
  on-primary-fixed: '#111c2d'
  on-primary-fixed-variant: '#3c475a'
  secondary-fixed: '#6ffbbe'
  secondary-fixed-dim: '#4edea3'
  on-secondary-fixed: '#002113'
  on-secondary-fixed-variant: '#005236'
  tertiary-fixed: '#c9e6ff'
  tertiary-fixed-dim: '#89ceff'
  on-tertiary-fixed: '#001e2f'
  on-tertiary-fixed-variant: '#004c6e'
  background: '#f7f9fb'
  on-background: '#191c1e'
  surface-variant: '#e0e3e5'
typography:
  display-lg:
    fontFamily: Outfit
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 44px
    letterSpacing: -0.5px
  display-md:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 37px
    letterSpacing: -0.25px
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 30px
    letterSpacing: 0px
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 26px
    letterSpacing: 0px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: 0px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 21px
    letterSpacing: 0px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 18px
    letterSpacing: 0.1px
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.5px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  xxl: 48px
  gutter: 16px
  margin-mobile: 16px
  margin-desktop: 32px
---

## Brand & Style

The design system embodies the concept of a **"North Star"**—a guiding light for navigating the complexities of personal wealth, health, and knowledge. The brand personality is **Institutional yet Personal**: it projects the unshakeable reliability of a high-end financial institution while maintaining the intimate, warm touch of a personal life assistant.

The visual style is **Glassmorphism Lite**, a refined evolution of minimalism. It prioritizes clarity and whitespace but introduces layers of depth through frosted surfaces and subtle refractive highlights. The emotional response should be one of **calm control and clarity**; the UI feels like a cockpit for one's life, where data is organized and atmospheric depth makes the experience feel premium and modern.

**Key Aesthetic Principles:**
- **Clarity over Complexity:** Use large headings and generous whitespace to prevent information overload.
- **Physicality:** Interaction is grounded in tactile feedback, utilizing micro-scale animations (1.5% scale-down) to mimic physical buttons.
- **Luminosity:** Elements should feel like they catch light, using subtle gradients and blurs rather than heavy shadows or flat borders.

## Colors

The palette is built on a foundation of **Deep Slate Blue** to establish trust and authority. Secondary and tertiary colors are domain-specific, providing instant visual categorization for the LifeOS "modules."

- **Primary (Deep Slate Blue):** Used for structural elements and high-level navigation.
- **Finance (Emerald Green):** Symbolic of growth and wealth.
- **Knowledge (Sky Blue):** Represents logic and clear thought.
- **Health (Rose):** Represents vitality and biological signals.
- **Interactive Accent (Cyan):** A bright, high-visibility turquoise specifically for interactive states and primary actions.

**Color Modes:**
- **Light Mode:** Uses a cool off-white (#F8FAFC) canvas to reduce glare and feel "airy."
- **Dark Mode:** Employs a rich charcoal navy (#0F172A) rather than pure black to maintain brand depth and sophisticated layering.
- **Market Sensitivity:** In financial views, the system supports swappable semantic meanings for Red/Green based on regional preferences (CN vs. INTL).

## Typography

The typography system uses **Outfit** for high-impact display moments to lean into its geometric, modern personality, while **Inter** handles all functional and body copy for maximum legibility.

**Tabular Figures:**
Crucially, for all financial data, metrics, and timestamps, the `tabular-nums` (tnum) CSS property or equivalent font feature must be enabled. This ensures that columns of numbers align vertically and do not "jitter" when values update in real-time.

**Scaling:**
Headlines scale down for mobile devices to maintain a clean vertical rhythm. Body text remains at 14px-16px to ensure accessibility on hand-held devices.

## Layout & Spacing

The system follows a strict **4px baseline grid**. All spacing, margins, and component heights are multiples of this unit.

**Layout Model:**
- **Mobile:** Single-column fluid layout with 16px side margins. Primary actions are clustered in the "thumb zone" (lower 40% of the screen).
- **Desktop:** A fixed-max-width container (1200px) centered on the screen. It uses a 12-column grid with 24px gutters.
- **Hierarchy:** Use spacing rather than lines to group content. A larger gap (32px+) between sections is preferred over a divider line to maintain the "clean and airy" feel.

## Elevation & Depth

This design system eschews traditional shadows in favor of **Luminous Depth**. 

- **Tonal Layers:** Surfaces are defined by slight shifts in background alpha. Cards use a 2% alpha surface tint of the primary text color to distinguish themselves from the off-white canvas.
- **Glassmorphism:** Navigation docks and overlays use `backdrop-filter: blur(20px)`. To ensure performance on 120Hz mobile screens, these elements are 97% opaque, reducing the GPU load of the blur.
- **Refraction:** Floating elements feature a 1px top-edge border (linear gradient) that is 55% white in light mode, simulating a light-catching edge.
- **Shadows:** When used, shadows are "Ambient Glows"—highly diffused, low-opacity (4-6%), and tinted with Deep Slate Blue (#1E293B) to avoid a "dirty" gray appearance.

## Shapes

The shape language is **Generous and Modern**. Large corner radii are used to make the UI feel approachable and "soft" despite its institutional nature.

- **Base Radius:** 8px (Small components like chips).
- **Component Radius:** 16px (Buttons and small cards).
- **Container Radius:** 20px (Primary dashboard cards).
- **Navigation Radius:** 40px (Floating bottom docks/pills).

Avoid sharp 0px corners entirely; even dividers should have slightly rounded caps.

## Components

**Buttons:**
Primary buttons are 52px tall with a 12px radius. They utilize the Cyan interactive accent. Every press must trigger a 1.5% scale-down and a light haptic vibration. "Busy" states show a circular loader while keeping the label visible to prevent layout shift.

**Cards (Soft Cards):**
Omit heavy borders. Instead, use a subtle 6% alpha border and a faint 2% alpha surface fill. For interactive cards, the background should lift in brightness by 5% on hover/touch.

**Floating Glass Dock:**
The main navigation is a floating pill at the bottom of the screen. It features the frosted glass effect with a top-edge refraction line. Active icons are highlighted with a Cyan glow.

**Input Fields:**
Fields should feel "open." Use a subtle bottom border (2px) that transforms into a Cyan highlight when focused. Avoid enclosing boxes unless the input is inside a dense form; prefer "floating labels" to maintain context.

**Delta Chips:**
Financial change indicators use pill shapes with 8px radii. They use the success/support colors with 10% alpha backgrounds for a "tinted" effect that doesn't overwhelm the text.