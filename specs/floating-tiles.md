# Floating Tiles Specification

**Status:** Prototype planned — direction confirmed by D-041; defaults remain provisional for native review
**Created / updated:** 2026-11-22
**Scope:** Bounded native prototype, after spec review and a separate implementation plan

## Problem Statement

The owner wants a quick, readable view of system statistics with richer detail on demand.
The ring's display style remains unresolved. D-040 parks its review while D-041 explores
independent floating tiles. The existing Strip remains the shipped default.

The smallest useful result is an overview → detail → switch → return journey that feels
stable and readable with representative data. This is a layout experiment, not a dashboard
builder. Ring acceptance stays open; this spec neither replaces its contract nor closes E1.

## Proposed Solution

Show separate stat surfaces with transparent gaps; selecting one replaces the overview with
a content-sized detail surface and a stationary, separate stat switcher.

### Confirmed direction

- Independent tile backgrounds, without an enclosing panel background.
- One expanded stat at a time. ~~Other overview tiles disappear.~~ **Revised 2026-11-27 (E1 case B,
  D-043):** the overview stays on screen and the card opens beside it — see below.
- Detail uses only the space its content needs; returning restores the overview.
- The switcher stays at the overview footprint's top-right edge, independent of detail width.
- Usage colour accompanies readable values, labels and meters (D-041).

### Revision after E1 case B (2026-11-27, D-043)

Supersedes the Detail, Switcher-position and Placement rows below where they conflict.

- **Overview stays.** Clicking a tile keeps every tile where it is, outlines the selected tile
  and opens its card beside the overview. Clicking the open tile again, All statistics or
  Escape closes the card; a second Escape dismisses.
- **Side:** the overview edge nearest the clicked tile's centre (left/right win near-ties within
  3%, so corner tiles open sideways). If the display has no room there: the opposite side, then
  the other axis, nearest first; if no side fits, the side with most room, clamped on screen.
- **Alignment:** side cards line up with the tile's top; top/bottom cards with its left edge;
  clamped into the display. Too-tall cards scroll; text never shrinks.
- **Switcher kept for now** (owner: "not yet" on removal): a reserved column right of the
  overview, shown only while a card is open; right-side cards open past it. The group bar stays
  above the overview's right edge.
- **Geometry** is still frozen at summon: the core (bar, overview, switcher column) is placed
  first, then each stat's card frame is fixed beside it. Nothing moves on selection.

### Proposed prototype defaults — evaluate in the bounded prototype

| Area | Proposed rule |
|---|---|
| Overview | Start from the mockup's 480-point-wide, four-column arrangement: 100-point row height and 12-point gaps. First enabled stat spans 2×2 cells; next two span 2×1; remaining stats occupy 1×1. Pack in saved order, without sorting by live values. These dimensions are starting values, not accepted native sizing. |
| Identity and availability | Use saved stat order and enabled identities. Freeze geometry per summon; unavailable readings keep their slot and say unavailable rather than zero. No enabled stats shows a compact empty state with Settings and Quit reachable. |
| Content | Preserve configured primary/secondary readings and existing detail rows/history. Reserve value widths so changing digits do not move tiles. No user tile-size editor in this experiment. |
| Detail | Anchor its top-left at the overview origin. Measure on selection, reserve changing-value widths, and keep the measured frame stable during sample updates. Remeasure on an explicit stat switch. Scroll content only when it exceeds the available frame. |
| Switcher | Separate 106-point-wide surface, two columns in saved order, including the selected stat. Keep its origin and item hit targets fixed throughout a summon. Selecting the current stat is inert; All statistics returns. |
| Placement | At summon, choose/clamp the combined overview and detail/switcher envelope to one display's visible frame. If necessary, enlarge the overview footprint once at summon to fit the widest measured detail plus switcher and gap. Keep the switcher at that footprint's right edge; freeze its resulting position; constrain/scroll detail rather than shifting the switcher on selection. |
| Limited space | Reduce overview columns at summon while preserving order and readable type. If necessary, scroll content with navigation always reachable. Determine native minimum sizes in the plan's geometry check; do not shrink text to fit. Display removal reclamps the group as one unit. |
| Return and dismiss | Click opens detail; no hover expansion. All statistics or Escape returns to overview and restores the selected tile's keyboard focus. Escape in overview dismisses. Global hotkey dismisses from either state; click-away respects existing Keep on Screen rules. Reopening starts in overview. |
| Keyboard | Tab/Shift-Tab traverses controls; arrow keys move by actual visual neighbours, not the HTML mockup's fixed index increments. Return/Space activates. Establish native focus delivery without stealing another app's focus on summon. |
| Gaps and dragging | Moving across gaps never closes detail. Proposed click on a gap counts as click-away under the existing pinning rule. Drag only from an explicit group handle, moving all surfaces together; no independent tile dragging. |
| Appearance | Reuse theme type, backgrounds and small corner radii. Colour values/icons/meters, leaving surfaces calm. Provide a separate selection/focus cue that remains visible in Mono. Respect Reduce Motion. |

### Usage semantics

For this experiment, CPU/GPU utilization, Memory used/total and Disk used/total use green
below 50%, amber from 50% to below 80%, and red from 80%. Battery applies those bands to
100 minus charge percent. Missing fractions, temperature, watts, fan RPM, load, uptime and
transfer rates stay neutral; do not borrow arbitrary activity ceilings to imply health.
Keep units and the basis of each meter explicit, especially when the configured primary
reading differs from the percentage. Reuse existing hysteresis only where the basis matches.

### User journey and bounded check

Input: isolated representative fixture readings and the existing stat/detail model. Summon
the overview, open CPU, switch to Network and its history, return, then dismiss. Success:
the owner can read values and navigate without chasing moving controls, and details retain
their existing meaning. Repeat with eleven stats, unavailable data, long labels, a small
display, screen edges and always-visible scroll bars.

Limit: one Debug-only native prototype using existing data/detail infrastructure; no new
samplers, production preference migration or release work. Native feasibility and usefulness
are untested. If fixed navigation and readable content cannot coexist on the target displays,
stop and revise geometry before expanding scope. A failed glance/readability review warrants
simplifying or parking this approach rather than building broader customization.

## Acceptance Criteria

All criteria are pending; proposed defaults above require review.

- [ ] **FT-1:** Given enabled stats, when summoned, then separate tiles appear in saved order with transparent gaps; live updates do not reorder or resize them.
- [ ] **FT-2:** Given an overview, when a tile is selected, then only its content-sized detail and the separate switcher remain, with navigation and Settings/Quit reachable.
- [ ] **FT-3:** Given expanded detail, when switching among short and long cards, then the switcher and its targets stay fixed and detail never overlaps it.
- [ ] **FT-4:** Given detail, when returning, then the same overview geometry and selected tile focus return; Escape/hotkey/click-away follow the reviewed dismissal rules.
- [ ] **FT-5:** Given edge placement or constrained display space, when opening any stat, then navigation stays on-screen and oversized detail scrolls without clipped controls or reduced type size.
- [ ] **FT-6:** Given unavailable readings or no enabled stats, when summoned/updated, then no false zero appears and Settings/Quit remain reachable.
- [ ] **FT-7:** Given 49.9%, 50%, 79.9%, 80% and 100% utilization, reversed battery and unknown scales, when rendered, then bands follow the stated basis and labels remain understandable without colour.
- [ ] **FT-8:** Given keyboard or VoiceOver navigation, when selecting/switching/returning, then named controls, selected state and focus remain usable without activating the app merely on summon.
- [ ] **FT-9:** Given the native prototype, when crossing gaps, dragging the group, changing readings or dismissing, then no accidental detail closure, moving switcher, stranded panel or persistent sampling-lifetime change occurs.
- [ ] **FT-10:** Given a normal Release launch and existing preferences/history, when the experiment is added, then Strip behaviour and stored data remain unchanged and prototype entry points are excluded.

## Technical Considerations

- `StatDescriptor.swift` supplies availability-filtered `visibleStats`, plus enabled-identity
  and resolved-descriptor paths used by Ring. Use identities for stable slots; avoid duplicating
  samplers or changing Strip's availability policy.
- `AppSettings.statOrder`/`enabledStats` provide ordering/visibility. Prototype fixtures must
  use isolated preferences and temporary history storage, avoiding the known Ring fixture leaks.
- `StatDetailView` already measures content and supports unavailable states/scrolling, but some
  options and fill-basis notes are Ring-specific. Reuse content through explicit presentation
  options; do not pass a dummy Ring close callback to obtain floating-tile layout.
- `PanelWindowController` provides placement/clamping; `DetailPanelController` provides measured
  details. Plan pure geometry/state logic separately from native window routing and hit testing.
- Separate appearance does not mandate one NSPanel per tile. Decide window count only after
  checking transparent-gap events, non-activating keyboard focus and coordinated dismissal.
- Preserve Carbon hotkeys, `LSUIElement`, no Dock/menu-bar item, existing sampling lifetimes,
  retained history and reset confirmation. No network service or extra permission is needed.
- New controls use AppKit wrappers per shared UI conventions. This HUD has no app-shell/sidebar
  requirement. Existing SwiftUI drawing/content can be reused without a broad control rewrite.
- Native visual/interaction checks belong in the hidden Atlas helper after implementation;
  geometry/state tests alone cannot establish focus, click-through or screen-edge behaviour.

## Out of Scope

Production layout selection/persistence, Grid/Rail rollout, ring corrections or acceptance,
new sensors, per-part sampling, freeform dashboard editing, per-stat colour rules, updater work,
publication, and changes to the owner's running review app or saved stat choices.

## Open Questions

| Provisional decision to validate during the prototype | Recommendation |
|---|---|
| Tile sizing and order | Adopt the first-three size hierarchy in saved order for the experiment; no stat-specific hardcoding. |
| Content envelope and narrow screens | Reserve the largest detail/switcher envelope once; allow content scrolling and column reduction rather than moving navigation. |
| Keyboard and transparent-gap semantics | Adopt the staged Escape, explicit return and click-away rules above; verify native delivery in the first implementation task. |
| Native architecture | Select the smallest coordinated panel arrangement after the geometry/focus check; do not assume eleven windows. |

Next: execute the [bounded prototype plan](../docs/IMPLEMENTATION_PLAN-floating-tiles.md) when
requested. Defaults are provisional experimental choices, not owner acceptance. The ring plan
remains parked in place with E1 open; the floating-tile plan is now selected.

## Related

- [D-040 / D-041](../docs/decisions.md#2026-11-22---d-041-floating-tiles-with-an-independent-stationary-switcher)
- [Reviewed floating mockup](../output/tile-exploration/floating-tiles.html)
- [Earlier layouts specification](panel-layouts-and-appearance.md) — historical broader scope; its Grid/Ring requirements are not requirements for this experiment.
- [Discovery and handoff](../docs/sessions/2026-11-22.md#resume--spec-next-session)
