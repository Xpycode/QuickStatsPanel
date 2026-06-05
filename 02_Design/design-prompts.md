# Claude Designer — Starting-Point Prompts

Design briefs for **QuickStatsPanel**, paste-ready for Claude Designer (or any
UI-generation tool). Each prompt is self-contained.

> **What the app is:** a macOS 15+ agent utility (no Dock icon, no menu-bar item)
> that summons a **thin, wide, glanceable HUD strip** of live Mac stats with a
> global hotkey. Press ⌃⌥⌘Q → strip appears near the cursor; click a tile →
> detail popover; press again / Esc / click away → dismiss. Glanceable and
> shallow ("iStat at a glance"), not a deep dashboard.

## Locked design values (don't fight these)

| Thing | Exact value |
|---|---|
| Hotkey | **⌃⌥⌘Q** (rebindable) |
| Strip height | 22–44pt slider, **~36pt default** |
| Corner radius | **12pt** (small/crisp — NOT heavy "Tahoe" rounding) |
| Width | content-driven (~210pt at CPU+Mem, grows as stats are added) |
| Sampling interval | **0.25–5s** slider |
| Anchors | near cursor (default) / screen center / top center / bottom center |
| Numerics | fixed-width tiles + **monospaced digits** (no jitter as values tick) |
| Background | dark, translucent vibrancy, subtle 1px border, soft drop shadow (floats) |
| Stats (order) | CPU %, Memory GB, Disk (Used/Free/Total + R/W), Network ↑↓, Battery %, Load avg (1/5/15 + cores), Uptime ("3d 4h"), Top process (top *user* proc by memory), then gear tile |
| Battery tile | **hidden on desktop Macs**; color band **inverted** (low = hot) |

---

## Prompt 1 — The core HUD strip (hero shot)

Design a macOS floating HUD panel: one thin, horizontally-wide rounded-rectangle
strip, **36pt tall with a 12pt corner radius** (small and crisp — NOT the heavy
macOS "Tahoe" rounding), floating over the desktop. Width hugs its content
(~210pt with two tiles, growing as more are added). It shows a left-to-right row
of compact tiles separated by hairline dividers, in this order: **CPU %, Memory
(e.g. "16.9 GB"), Disk, Network ↑/↓, Battery %, Load avg, Uptime ("3d 4h"), Top
Process**, then a trailing **gear tile**. Each tile = a small SF Symbol +
micro-label + a bold **monospaced-digit** value (fixed-width so nothing shifts as
numbers tick). Dark translucent vibrancy background, subtle 1px border, soft drop
shadow so it reads as floating. Precision-instrument feel — calm and dense, not a
colorful widget. Show it at natural content-hugging width, and give me 2–3
variations of the per-tile internal layout (label-above-value vs
icon-left/value-right vs stacked).

---

## Prompt 2 — A single tile + its detail popover

I have a 36pt-tall dark macOS HUD strip of system-stat tiles with fixed-width
monospaced values. Design ONE tile in two states: (a) resting in the strip, and
(b) the detail popover shown on click — a small dark rounded card with a pointer
to the tile. Show three concrete examples: **Disk** (resting: used %; popover:
Used / Free / Total + live Read / Write throughput), **Battery** (resting: % with
a state-aware battery SF Symbol; popover: % + charging state + time remaining —
and note this tile is *hidden entirely on desktop Macs*), and **Load average**
(resting: 1-minute load; popover: 1 / 5 / 15-minute loads + active core count).
Keep all popovers visually consistent with a glanceable instrument-like dark HUD.

---

## Prompt 3 — At-a-glance color language

Design a color system for the live tiles in a dark macOS HUD strip. Each stat
tints to signal health at a glance — calm/neutral when fine, warming to alert
under stress — without turning the panel into a rainbow or strobing when a value
hovers on a threshold. Cover these specific stats and their stress directions:
**CPU %** (high = hot), **Memory** (high = hot), **Disk fullness** (high = hot),
**Load average** (normalize as load ÷ active cores; >1.0 per core = hot), and
**Battery %** (INVERTED — *low* = hot). Propose: (1) a 3–4 step semantic ramp
(calm → caution → warn → critical) tuned for a dark translucent background, (2)
where the color lives (value text / a thin bar / the icon / a subtle tile
background), and (3) hysteresis-friendly bands so a value on a boundary doesn't
flicker. Show the ramp applied across the full tile row at varying stress levels.

---

## Prompt 4 — In-panel Settings window

Design a compact, dark, native macOS Settings window for a HUD utility that has
**no Dock icon and no menu-bar item** (it opens from a gear tile inside the
panel). One column, grouped sections, tight and scannable. It needs: a
**drag-to-reorder + toggle list** of the 9 stats (CPU, Memory, Disk, Network,
Battery, Load avg, Uptime, Top Process); a **sampling-interval slider, 0.25–5s**;
a **panel-anchor picker** (Near cursor / Screen center / Top center / Bottom
center); a **strip-height slider, 22–44pt**; a **global-hotkey recorder field**
showing the current combo **⌃⌥⌘Q**; and **Reset** + **Quit** buttons. Show the
hotkey-recorder field in both its resting state (showing ⌃⌥⌘Q) and its "press
your shortcut now…" recording state.

---

## Prompt 5 — App icon

Design a macOS app icon for **"QuickStatsPanel"** — a utility that summons a thin,
wide HUD strip of live Mac stats with the hotkey ⌃⌥⌘Q. Evoke: glanceable live
metrics + a wide thin panel + speed/summoning. Avoid speedometer/gauge clichés
and anything that looks like a heavyweight system monitor. Lean into the identity:
a slim horizontal bar with a 12pt-style small radius, a hint of sparkline/bar-graph
data, dark modern precision-instrument palette. On the standard macOS rounded-square
template, give me three directions — one literal (a tiny stat strip), one abstract
(a data motif), one symbolic.

---

## Prompt 6 — First-run hint UI

Design a one-time first-run hint for a macOS "agent" utility with **no Dock icon
and no menu-bar item** — so a new user has no obvious way to discover how to use
it. On first launch the app briefly shows its HUD strip once, but it also needs a
small, friendly, dismissible hint that teaches the single core gesture: **"Press
⌃⌥⌘Q anytime to summon your stats. Press it again, Esc, or click away to
dismiss."** Design this as a compact dark rounded card (matching the 12pt-radius
HUD aesthetic) that appears near the panel, with the hotkey rendered as styled
keycaps, a one-line explainer, and a "Got it" dismiss. Include a secondary line
pointing to the **gear → Settings** for changing the shortcut or anchor. Show it
both as a standalone card and positioned just below the live stat strip.
