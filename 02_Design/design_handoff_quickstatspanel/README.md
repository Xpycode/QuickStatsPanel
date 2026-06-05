# Handoff: QuickStatsPanel — floating macOS system-stats HUD

## Overview
QuickStatsPanel is a macOS menu-bar-less / Dock-less utility. The user presses a global
hotkey (**⌃⌥⌘Q**, rebindable) to summon a thin, horizontally-wide HUD strip that floats over
the desktop showing live system stats (CPU, Memory, Disk, Network, Battery, Load average,
Uptime, Top Process). Each stat is a compact tile; clicking a tile opens a detail popover.
A trailing gear tile opens a compact Settings window. On first launch a one-time hint card
teaches the summon gesture.

This bundle is the **design specification** across six areas:
1. The core HUD strip + 3 tile-layout variations
2. A single tile's resting + detail-popover states (Disk, Battery, Load, CPU)
3. The semantic color language for stat health (calm → caution → warn → critical)
4. The Settings window (+ hotkey-recorder resting/recording states)
5. The app icon (3 directions)
6. The first-run hint card

## About the Design Files
The files in this bundle are **design references created in HTML/React (Babel-in-browser)** —
prototypes that show the intended look and behavior. They are **not** production code to copy
directly. The task is to **recreate these designs in the target environment**.

This is a native macOS utility, so the natural target is **SwiftUI or AppKit** (an `NSPanel`
with `.nonactivatingPanel` style + `NSVisualEffectView` for the vibrancy material, a global
`CGEventTap` / `MASShortcut`-style hotkey, and `NSPopover` for the detail cards). If the team
is instead building cross-platform (e.g. Electron/Tauri + React), the HTML here is much closer
to drop-in, but should still be re-expressed in the app's component system and tokens.
Use the codebase's established patterns; the HTML is the source of truth for **appearance,
measurements, copy, and interaction**, not for framework choice.

## Fidelity
**High-fidelity.** Final colors (oklch + rgba), typography, spacing, radii, shadows, and
interactions are all specified below and in the prototype. Recreate pixel-faithfully, then
substitute live system data for the simulated values.

> Note on scale: the prototype renders the strip at ~1.5× physical size for on-screen
> legibility in the design canvas. The **physical** spec is 36pt tall (22–44pt range) with a
> 12pt corner radius. The px values below are the prototype's rendered values — preserve the
> *proportions* and use pt at implementation time. Where a true pt value is fixed by product
> spec it is called out explicitly.

---

## Product constants (authoritative spec)
| Thing | Value |
|---|---|
| Hotkey | ⌃⌥⌘Q (rebindable) |
| Strip height | 22–44pt slider, **36pt default** |
| Corner radius | **12pt** (crisp — not heavy "Tahoe" rounding) |
| Strip width | content-driven (~210pt at CPU+Mem, grows per enabled tile) |
| Sampling interval | 0.25–5s slider (1s default) |
| Panel anchors | Near cursor (default) / Screen center / Top center / Bottom center |
| Stats | CPU %, Memory GB, Disk (Used/Free/Total + R/W), Network ↑↓, Battery %, Load avg (1/5/15 + cores), Uptime ("3d 4h"), Top Process |
| Battery tile | hidden on desktop Macs; color band **inverted** (low = hot) |
| Dismiss | press hotkey again, Esc, or click away |

---

## Design Tokens

### Type
- **UI font:** SF Pro Text / system — `-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", system-ui, sans-serif`
- **Numeric/value font:** SF Mono — `ui-monospace, "SF Mono", "SFMono-Regular", Menlo, monospace`, always `font-variant-numeric: tabular-nums` so values never shift width as they tick.

### Type scale (rendered px in prototype)
| Role | Size | Weight | Notes |
|---|---|---|---|
| Tile value | 16–17px | 600 | mono, tabular-nums, letter-spacing -0.01em |
| Tile micro-label | 9.5px | 600 | uppercase, letter-spacing 0.07em |
| Tile unit suffix (%/GB) | inherits | 500 | opacity 0.5 |
| Popover headline value | 16px | 600 | mono |
| Popover title | 12.5px | 600 | |
| Popover KV label | 12px | — | color = label token |
| Popover KV value | 12.5px | 500–600 | mono |
| Settings group label | 11px | 600 | uppercase, 0.04em |
| Settings row text | 13px | — | |
| Section caption (mono) | 12px | — | mono |

### Panel material (the strip + popovers + first-run card)
- Background: `rgba(34,34,37,0.62)` with `backdrop-filter: blur(28px) saturate(1.7)` (popovers use `rgba(36,36,40,0.92)`, blur 30px).
- Border: `1px solid rgba(255,255,255,0.16)`
- Radius: **12px** (strip & popovers & first-run card)
- Shadow: `0 1px 0 rgba(255,255,255,0.05) inset, 0 12px 34px rgba(0,0,0,0.46), 0 2px 6px rgba(0,0,0,0.34)`
- Hairline divider between tiles: `1px` wide, `rgba(255,255,255,0.085)`, inset 9px top/bottom.

### Text colors
- Value (calm/neutral): `rgba(255,255,255,0.94)`
- Micro-label: `rgba(255,255,255,0.42)`
- Icon: `rgba(255,255,255,0.62)`
- Dim/secondary: `rgba(255,255,255,0.30)`

### Control accent (switches, sliders, selection, primary button)
- `oklch(0.64 0.155 248)` (calm blue)

### Semantic health ramp (tuned for dark translucent bg)
| Level | Bar / icon color | Value-text color |
|---|---|---|
| 0 Calm | `oklch(0.80 0.035 225)` | `rgba(255,255,255,0.94)` |
| 1 Caution | `oklch(0.835 0.130 92)` | `oklch(0.88 0.115 95)` |
| 2 Warn | `oklch(0.740 0.165 52)` | `oklch(0.80 0.155 55)` |
| 3 Critical | `oklch(0.660 0.205 26)` | `oklch(0.75 0.185 28)` |

**Where color lives (deliberately restrained — one signal at a time):**
- The thin 2px meter bar at the bottom of each tile is the **primary, always-on** carrier.
- Value **text** stays neutral until level ≥ 2 (warn).
- The **icon** tints and a faint tile-background wash appears **only** at level 3 (critical):
  bg wash = `color-mix(in oklab, <critical> 12%, transparent)`; a smaller 7% wash at warn.

**Hysteresis bands (enter to escalate ▲ / exit to de-escalate ▽ — the gap absorbs jitter):**
| Stat | Direction | Caution enter/exit | Warn enter/exit | Critical enter/exit |
|---|---|---|---|---|
| CPU % | high=hot | 55 / 48 | 80 / 73 | 92 / 87 |
| Memory % of total | high=hot | 60 / 53 | 80 / 73 | 92 / 87 |
| Disk full % | high=hot | 75 / 70 | 88 / 84 | 95 / 92 |
| Load ÷ active cores | high=hot | 0.70 / 0.60 | 1.00 / 0.90 | 1.50 / 1.35 |
| Battery % | **low=hot (inverted)** | 40 / 45 | 20 / 25 | 10 / 13 |

A value must cross the **enter** threshold to escalate a level, but must fall back past the
**exit** threshold (one notch lower) to de-escalate. This prevents strobing on a boundary.

### Wallpaper stand-ins (desktop backdrop for vibrancy demos only — not part of the app)
- Cool: `radial-gradient(125% 120% at 18% 8%, #4a5fb0, #34367e 32%, #211a44 62%, #100c20)`
- Settings/popover backdrop: `radial-gradient(120% 110% at 50% 0%, #26262b, #161619)`

### Radii & spacing
- Strip / popover / first-run card radius: 12px
- Settings window radius: 10px; grouped-card radius: 9px; control radius: 7–8px; keycap radius: 6px
- Tile horizontal padding: 15px (label-above / icon-left), 14px (stacked)
- Popover padding: 13px 15px; Settings body padding: 16px, group gap: 16px

---

## Screens / Views

### 1. HUD strip (core)
- **Purpose:** glanceable, dense, instrument-like readout summoned by hotkey.
- **Layout:** a single `display:inline-flex` row, content-hugging width, fixed height (36pt
  default). Tiles in order: CPU, Memory, Disk, Network, Battery, Load, Uptime, Top Process,
  then a trailing **gear** tile. Hairline divider before every tile except the first.
- **Tile (default "label-above-value" variant):** vertical stack — top row = icon (14px) +
  micro-label; below = mono value (17px) + optional sub-value. 2px health meter bar pinned to
  the bottom (inset 15px L/R, 7px from bottom), filled left-to-right to the stat's fraction,
  colored by health level.
- **Tile variants (pick one for the product; prototype shows all three):**
  - **A · Label-above-value** (default): tightest height, reads top-down.
  - **B · Icon-left / value-right**: icon (17px) anchors the left edge, label + value stack to
    its right. Most legible, widest tiles.
  - **C · Fully stacked**: icon → label → value centered; most "instrument" feel, needs a
    taller strip (~64px rendered).
- **Per-tile content:**
  - CPU: value `23`, unit `%`; meter = pct/100.
  - Memory: value `16.9`, unit `GB`; meter = used/total.
  - Disk: value `64`, unit `%` (used); meter = pct/100.
  - Network: value `↓18.6`, sub `↑2.4` (MB/s); no health level.
  - Battery: value `82`, unit `%`; inverted meter; **hidden on desktop Macs**.
  - Load: value `1.42` (1-min); meter = load/cores normalized to /2.0.
  - Uptime: value `3d 4h`; no level.
  - Top Process: value `Xcode` (top user process by memory); no level.
- **Gear tile:** 16px gear glyph, icon-color default, brightens to value-color on hover.
- **Behavior:** values tick on the sampling interval (default 1s, smooth). Clicking a tile
  highlights it (`rgba(255,255,255,0.08)` bg) and opens its detail popover.

### 2. Tile detail popover
- **Trigger:** click a resting tile. Anchors to the tile with a small 14px caret (rotated
  square, same border/material as the card) pointing at it.
- **Card:** popover material (above), width 224–236px, padding 13×15.
- **Structure:** header row = icon + title (left) + big mono headline value (right, health-
  tinted). Hairline. Then content:
  - **Disk** (236px): a "Used" meter row (label + % + 4px bar), then KV list Used `297 GB` /
    Free `163 GB` / Total `460 GB` (Total bold), hairline, then Read `4.2 MB/s` / Write `1.1 MB/s`.
  - **Battery** (224px): Charge meter, then State `On battery` / Time remaining `3:34` (bold) /
    Condition `Normal` / Cycles `218`. (Tile hidden entirely on desktop Macs.)
  - **Load** (224px): 1 min `1.42` (tinted, bold) / 5 min `1.18` / 15 min `0.96`, hairline,
    Active cores `8`, then a "Load / core" meter (load/cores).
  - **CPU** (224px): Total meter, User `14%` / System `9%` / Idle `77%`, hairline, Top process
    `Xcode · 42%`.
- **KV row:** label left (12px, label color), value right (12.5px mono, tabular-nums). 3.5px
  vertical padding.
- **Meter row:** uppercase 11px label + % readout (health-tinted) over a 4px rounded track
  (`rgba(255,255,255,0.10)`) with a fill in the level color.

### 3. Color language (reference, not a runtime screen)
Three reference artboards: (a) the 4-step ramp as swatches with oklch values + role copy and
the "where it lives" rules; (b) the ramp applied across the CPU/Mem/Disk/Load/Batt row at three
stress scenarios (Idle / Under load / Critical); (c) the hysteresis band chart with ▲ enter /
▽ exit markers per stat. Implement the rules from the Design Tokens section above.

### 4. Settings window
- **Purpose:** opened from the gear tile (no Dock icon, no menu-bar item). Compact, dark,
  one column, grouped sections, scannable.
- **Window:** ~420px wide, bg `#262629`, radius 10px, shadow
  `0 24px 70px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.08)`.
- **Title bar:** 40px tall, traffic lights (12px: `#ff5f57` / `#febc2e` / `#28c840`) on the
  left, centered title "QuickStats Settings" (13px, 600). Bottom hairline.
- **Body (padding 16, gap 16):**
  - **Stats group** — grouped card; each row (38px min-height, hairline separators) = drag grip
    (6-dot, cursor grab) + stat icon + name + a switch. Battery row shows "auto-hidden · desktop"
    note. Rows are **drag-to-reorder** (pointer drag on the grip; reorders by row-height steps)
    and each has a **toggle** to enable/disable the tile. Switch = 38×22 pill, knob 18px,
    `accent` when on / `rgba(255,255,255,0.16)` off, 0.18s transition.
  - **Sampling interval** — slider row, 0.25–5s, step 0.25, mono readout `1.00s`.
  - **Panel anchor** — 2×2 grid of selectable cells, each a little "screen" glyph (44×30 rounded
    rect) illustrating the position: Near cursor (dot + cursor arrow), Screen center (center
    dot), Top center (top bar), Bottom center (bottom bar). Selected = accent border + filled marks.
  - **Strip height** — slider row, 22–44, step 1, readout `36pt`.
  - **Global hotkey** — see field states below.
  - **Footer:** two equal buttons — "Reset…" and "Quit QuickStats" (danger = critical text color).
- **Hotkey recorder field (two states):**
  - **Resting:** bordered field; left = keycaps `⌃ ⌥ ⌘ Q`; right = "Click to change" (label color).
  - **Recording:** accent border + 3px accent focus ring + accent-tinted bg; left = pulsing red
    dot (`qsPulse` 1.1s) + "Press your shortcut now…". Next modifier+key chord is captured; Esc cancels.
  - **Keycap:** min 24px wide, 24px tall, radius 6, bg `rgba(255,255,255,0.10)`,
    border `rgba(255,255,255,0.14)`, subtle top-inset highlight + bottom shadow.

### 5. App icon (3 directions on the macOS squircle)
Shell: rounded square, continuous-corner ratio ≈ 0.2237 × size; bg
`linear-gradient(158deg,#2b3340,#1a1e27 52%,#0e1014)`, top sheen, inset bevel, hairline ring.
Accent data color `oklch(0.78 0.13 175)` (cyan-green), spark `oklch(0.80 0.14 92)` (amber).
- **A · Literal:** a miniature of the strip — a small hairline-bordered panel with 3–4 cells,
  each a colored square + a white value bar.
- **B · Abstract:** 5 rounded bar-graph bars (one glowing accent) rising over a single white
  "panel" baseline.
- **C · Symbolic:** a slim white bar snapping in with two faded trailing "ghost" bars (motion /
  summon) + an amber spark. Each direction shown at full + 56/40/28px to prove legibility.

### 6. First-run hint card
- **Purpose:** one-time teaching of the core gesture (no Dock/menu-bar discoverability).
- **Card:** popover material, 12px radius, ~320–336px wide, padding 16.
- **Structure:** header = small app-icon glyph (34px) + "QuickStats is running" / "No Dock or
  menu-bar icon — it lives on a key." Then the gesture line: "Press [⌃][⌥][⌘][Q] anytime to
  summon your stats." Sub: "Press it again, [esc], or click away to dismiss." Hairline, then
  footer = gear icon + "Change the shortcut or anchor in Settings." (left) and a primary accent
  **"Got it"** button (right, 30px, radius 7). Shown standalone and positioned just below the strip.
- **Dismiss:** fades + lifts (`opacity`/`translateY scale`, 0.35s). In the app, dismiss is permanent.

---

## Interactions & Behavior
- **Summon/dismiss:** global hotkey toggles the strip; Esc and click-away also dismiss. Strip
  appears at the chosen anchor (near cursor by default).
- **Sampling:** poll system stats every `interval` seconds; animate value + meter transitions
  (`width 0.5s ease`, color `0.4s`). Keep value cells fixed-width (tabular-nums) so nothing reflows.
- **Tile click → popover** anchored with caret; only one open at a time; click-away/Esc closes.
- **Health level** computed per stat each sample via the hysteresis bands; drives meter color,
  (≥warn) value color, (=critical) icon tint + tile wash.
- **Settings:** switches toggle tile visibility; grip drag reorders tiles (reflects in strip
  order); sliders update interval + strip height live; anchor picker is single-select; hotkey
  field enters recording on click.
- **Transitions:** switch knob `cubic-bezier(.3,.7,.3,1)` 0.18s; hover bg fades 0.12–0.14s;
  recording ring/border 0.15s; recording dot pulse `qsPulse` (scale 1→0.78, opacity 1→0.4) 1.1s.

## State Management
- `stats` — latest sampled values (cpu.pct, mem.usedGB/totalGB, disk.usedPct/read/write/used/free/total,
  net.up/down, batt.pct/charging/mins, load.one/five/fifteen/cores, uptime.str/secs, proc.name/memGB/cpu).
- `levels` — per-stat health level (0–3), updated with hysteresis using the **previous** level.
- Settings: `order` (tile order array), `enabled` (per-tile bool), `interval`, `stripHeight`,
  `anchor`, `recording` (hotkey field), and the bound hotkey combo.
- Open popover id (or none). First-run: `dismissed` (persisted; show only on first launch).
- Battery: detect desktop Mac (no battery) → omit tile + its setting row.

## Assets
- **Icons** are simple line glyphs drawn inline (CPU, Memory, Disk, Network ↑/↓, Battery, Load
  gauge, Uptime clock, Top-process window, Gear). In a native build, prefer the equivalent
  **SF Symbols** (e.g. `cpu`, `memorychip`, `internaldrive`, `arrow.up.arrow.down`, `battery.100`,
  `gauge.with.dots.needle`, `clock`, `macwindow`, `gearshape`). No external image assets.
- **Wallpapers** in the prototype are CSS gradients standing in for the desktop — not app assets.

## Files (in this bundle)
- `QuickStatsPanel.html` — entry; loads React 18 + Babel and all modules below.
- `tokens.jsx` — all design tokens (`window.QS`): fonts, panel material, text colors, ramp,
  accent, level helpers.
- `icons.jsx` — line icon set + procedurally-generated gear path.
- `hud.jsx` — `HUDStrip`, `Tile` (3 variants), `Panel`, dividers, gear tile, `useLiveStats`
  simulation, **`bandLevel` hysteresis logic**, `meterFor`, formatters. **Read this for the
  authoritative band/level math.**
- `popovers.jsx` — `Popover`, `KV`, `MeterRow`, and Disk/Battery/Load/CPU content.
- `sec-hero.jsx` / `sec-popovers.jsx` / `sec-color.jsx` / `sec-settings.jsx` / `sec-icon.jsx` /
  `sec-firstrun.jsx` — the six design sections (settings + first-run hold the interactive logic).
- `app.jsx` — composes the sections onto the canvas.
- `design-canvas.jsx` — the pan/zoom presentation wrapper (presentation only — **not** part of
  the product; ignore when implementing).

> To run the prototype: serve the folder over any static HTTP server and open
> `QuickStatsPanel.html` (it fetches the sibling `.jsx` files, so `file://` won't work).
