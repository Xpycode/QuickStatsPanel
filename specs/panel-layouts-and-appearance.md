# Panel Layouts and Dynamic Appearance Specification

**Status:** Draft — product scope confirmed; wedge visual direction accepted; native interaction validation and settings review pending
**Created:** 2026-11-12
**Last updated:** 2026-11-12
**Release:** Future release; not part of the prepared 1.2.1 artifact

## Problem Statement

QuickStatsPanel currently gives the owner one horizontal strip for glancing at local system
statistics. Different workspaces would benefit from a compact grid, a vertical rail, or a
pointer-centred ring. The owner also wants useful monitoring-style visual feedback and modest
customization, without turning the app into a dashboard builder or a large preference system.

The existing strip remains useful and stays the default. Existing themes, custom accent and
background, opacity, corner radius, density, per-stat values and graphs already provide much
of the customization needed. This work extends that foundation.

### Confirmed in discovery

- All three concept directions are welcome: compact grid, vertical rail, and ring.
- The ring image is exploratory and needs further design work, not reproduction as-is.
- Dynamic colour belongs to each stat; the overall panel background stays calm.
- The starting ring holds up to eight favourites.
- Owner correction: both starting and additional rings use MousePlus-style wedges, not boxes
  arranged around a ring. This shape choice is confirmed; exact dimensions remain for review.
- Both expansion behaviours are required: hovering a stat reveals its details; hovering a
  separate More control reveals additional stats. Eight is not the total accessible-stat limit.
- Customization stays bounded: reuse existing theme controls, add layout choice and colour
  presentation (Off / Value colour / Subtle tile tint), retain built-in thresholds, and omit
  alerts and a per-stat rule editor.

## Proposed Solution

### One-liner

Offer four presentations of the same live statistics, with stable geometry, detail on demand,
and optional subtle per-stat colour feedback.

### Key capabilities

1. **Layout choice:** Strip, Grid, Rail, and Ring. Grid and Rail show the enabled stats in the
   existing order; Strip preserves its established behaviour. Layout is a persistent preference.
2. **Expandable ring:** Up to eight selected favourites in stable positions, a separate More
   affordance for other enabled stats, and hover/click access to the same detail content used
   elsewhere. Only one additional-stat ring and one detail surface may be open at a time.
3. **Bounded appearance:** Existing themes and custom controls plus one shared colour-mode
   selector, evaluated independently for each stat. No individual rule or colour-mode matrix.
4. **Consistent details:** Existing values, paired values, detail-row choices, graphs, retained
   transfer history and reset actions retain their meanings across layouts.
5. **Predictable interaction:** Preserve non-activating HUD behaviour, hotkey, pinning, dragging,
   placement and dismissal. Hover expansion must not strand the pointer or move its target.

### Concrete user journey

1. Input: the user's existing enabled stats, ordering, themes, settings and local samples.
2. In Settings → Panel, choose Ring; in Settings → Stats, select up to eight enabled favourites.
3. In Settings → Appearance, choose Subtle tile tint.
4. Summon the HUD. Favourite stats appear around the pointer with readable labels and values.
5. Hover CPU to inspect its configured details/history. Move into the details without collapse.
6. Hover More to reveal remaining enabled stats, then hover or click one for its details.
7. Dismiss and reopen: preferences persist; sampling and retained history remain intact.

Observable success: readings and detail content agree with the existing layouts, every enabled
stat is reachable, dynamic colour affects only the relevant stat, and no interaction requires
chasing a moving target.

### Layout and interaction defaults proposed for review

- **Grid:** Compact rectangular cells with a preferred three-column arrangement; reduce columns
  when necessary for the display. Do not stretch cells solely to force an exact square.
- **Rail:** One vertical column, preserving existing order. It uses the existing anchor system;
  edge placement is available, not forced.
- **Ring:** One starting ring, horizontal text, a useful central hub, and a clearly distinct More
  control that does not consume one of the eight favourite slots. Avoid duplicating an entire
  selected tile in the centre as in the first concept image. Rich history and interactive
  details use a readable detail surface rather than being squeezed into wedge-shaped charts.
- Favourites form a saved subset of enabled stats and follow existing stat order. Initial
  selection uses up to the first eight enabled stats; subsequent explicit choices are preserved.
  Disabling a favourite makes it inactive without deleting its saved membership.
- Temporarily unavailable ring favourites retain their positions with an unavailable indication.
  They do not become measured zero. Other slots do not rotate to fill a transient gap.
- More contains enabled non-favourites; it is absent when none exist. No recursive outer rings,
  independent ring-order editor, or app-specific layout profiles.
- Ring hover uses a short fixed dwell and a forgiving close delay; click offers an immediate
  equivalent and can hold the detail open. Start with 350 ms dwell and 450 ms close delay, to validate in the interaction prototype,
  not expose as settings. Held details ignore hover replacement and close by owner click, Close, or Escape.
- Pointer travel through a child ring/detail preserves that branch. Moving deliberately to
  another parent replaces it; crossing the centre does not accidentally select a stat.
- Escape closes the detail first, then More if open, then the HUD on the next press. Hotkey and click-away
  retain whole-HUD dismissal semantics, respecting the existing Keep on Screen behaviour.
- Hover expansion is required for Ring. Strip/Grid/Rail keep reliable click-to-open details;
  adding hover to those layouts is not required for this first version.
- Geometry-changing settings take effect on the next summon, consistent with the strip's
  current stability contract. Colour/theme changes can apply live without moving controls.

### Refined ring contract — November 12 review

The owner accepted the revised wedge visual direction (“yes, better”); see D-034. Detailed
interaction choices below are proposed defaults, not claims of working app behaviour. Review images and reproducible source live in
`02_Design/ring-review/`. Blue dotted paths are explanatory annotations, never visible HUD chrome.

**Geometry and centre**

- Use circular annular wedges, like MousePlus, for favourites and additional stats. The wedge
  itself is the visible surface and hit target; do not place rectangular stat boxes inside it.
  Keep labels and configured readings horizontal within each wedge. Status tint fills the wedge;
  a separate outline indicates selection. Rich detail retains the existing rectangular surface.
  The centre never repeats the selected reading.
- Centre: a dedicated drag area, a separate More control with remaining-stat count, and Settings.
  More and Settings must have disjoint targets of at least 28 points high. Keep on Screen remains
  in the existing context menu/hotkey with a reserved centre indicator; it is separate from
  holding a detail. The centre's unused space selects nothing.
- Distribute the active favourites clockwise from twelve o'clock in existing stat order when
  summoned. One favourite uses a 60-degree wedge at twelve o'clock; the remaining annulus is inactive.
  Two or more divide the ring into equal sectors. Freeze all slot positions for that summon;
  explicit membership/order changes may redistribute them next time. Sample availability cannot.
- Initial fixtures use a circular favourite ring with 100-point inner and 260-point outer
  radii; horizontal text centres sit at radius 185. Labels/headlines/secondary text remain
  13/16/12 points. The footprint is 520 × 520 points. The four-entry outer-ring fixture uses
  radii 274–410 with text at radius 342, leaving enough radial width for process names.
  These are review baselines, not new size preferences. Measure text/graph bounds against the
  actual annular sector, including its sloping sides and inner hole, before summon. Enlarge or
  use the stated fallback rather than clip values, rotate labels or shrink text.
- Rendering and hit testing share centre, radii and angular boundaries. The centre, separator
  gaps and inactive annulus do not select stats. Pointer-travel protection takes precedence
  over crossed wedge hover while moving toward an open child; explicit clicks still win.
- The additional ring holds all enabled non-favourites, in existing order. Its positions are
  calculated once per summon. Current twelve-stat inventory means four entries with eight
  favourites, but fewer favourites may require up to twelve More entries: never assume four.
  Use the More list when the measured outer ring cannot fit. No pagination or third ring.
- No favourites: retain the hub and More for enabled stats; explain that no favourites are
  selected. No enabled stats: keep Settings and an empty-state message. Hide More only when its
  enabled non-favourite count is zero. Unavailable enabled stats remain reachable in More too.
- Saved membership, including disabled favourites, counts toward the eight-selection limit.
  Settings says “8 selected, 6 enabled” when relevant; the user can uncheck a disabled favourite.
  Enabling another stat never silently promotes it or replaces a saved favourite.

**Interaction state and precedence**

| Input / situation | Proposed result |
|---|---|
| Summon | Collapsed; no remembered detail/More expansion. Suppress hover until actual pointer movement so clamping cannot open a stat under a stationary pointer. |
| Dwell on stat for 350 ms | Preview its detail, unless a held detail exists. Moving to another stat restarts dwell. |
| Click stat / accessibility Press | Open immediately and hold; a preview of that same stat becomes held. Clicking the held owner again closes it; clicking another stat replaces it with a held detail. |
| Interact with preview content | Mouse-down in the detail promotes it to held before processing graph/range/reset controls. Hover never invokes a reset. |
| Dwell on More / click More | Dwell previews the additional ring/list; click holds that branch. Clicking an already held More closes it and its child detail. First click on hover-open More holds it. |
| Hover while a detail is held | No detail replacement or More opening. Clicking More explicitly closes a favourite detail and opens/holds More. |
| Select an additional stat | Keep More visible while its preview/detail is active. A held child also holds the More branch. |
| Select a favourite from More | On completed dwell (if unheld) or explicit click, close More and open that favourite's detail atomically. |
| Close button / Escape | Close detail first, leaving More if it owns that detail; next Escape closes More; next hides HUD, even when Keep on Screen is on. |
| Hotkey | Hide the entire HUD and cancel all expansion timers, including while pinned. |
| Click outside, unpinned | Hide the entire HUD. Clicks in any child surface are inside. |
| Click outside, Keep on Screen | Leave the HUD and explicitly held surfaces open; hover previews close after their normal leave delay. |
| Drag centre | Cancel pending hover and close expansions before moving. Save position with current anchor semantics; resume hover only after mouse-up and movement. |
| Open Settings / hide / display removed | Cancel timers and close descendants. Settings follows the existing activating-window path. Display removal dismisses; next summon recomputes geometry. |

- Leave delay: 450 ms outside the union of owner, child and safe travel region. Re-entry cancels
  the close. While travelling toward the child, preserve the branch and suppress crossed sibling
  hover for at most 700 ms; a deliberate click always wins. If the pointer stops on a sibling,
  normal 350 ms dwell resumes. Crossing the centre alone does not open/replace anything.
- Build travel regions from actual rendered frames (including the gap), not assumed angles.
  Allow 12 points of route tolerance. Travel regions preserve state but are not clickable surfaces
  and must not intercept clicks intended for another app. Avoid a giant invisible input window.
- Closing with owner click, Close or Escape suppresses reopening under the stationary pointer
  until it exits and re-enters that target. Timers carry a summon/branch generation; stale callbacks
  cannot reopen anything after dismissal, drag, settings, or a newer selection.
- Keep on Screen retains current per-summon semantics and resets when the HUD hides. Holding a
  detail does not turn it on. No new global arrow-key/Tab capture; accessibility Press is the
  click equivalent and each stat announces name, value, availability and expanded state.

**Screen edges and finite fallback**

- Choose a host display, stable base position, expansion side and presentation mode at summon.
  Reserve space for the measured largest configured detail and More route before placing the
  base. Prefer an outer ring only when the complete base + outer ring + detail fits the visible
  frame. Do not wait until hover to discover that the selected stat must move.
- At edges, shift the initial placement inward and prefer a fixed side area: a More list above
  the single detail card. The list remains accessible while its detail is open. Large lists and
  tall details scroll independently. No selected owner is obscured by its own card.
- Prototype minimum: 1024 × 640 **visible points**, not physical pixels. The fallback image fits
  the baseline base plus a 380-point side area. If larger configured values cannot fit that
  arrangement, use a compact labelled list for the entire presentation on that summon, retaining
  favourites first and Settings. Preserve the saved Ring preference; do not clip or scale text.
- Validate 1024 × 640 and 1440 × 900 visible points, all four edges/corners, 1×/2× and mixed-scale
  displays. Geometry and hit testing share point coordinates. Full outer-ring availability is
  conditional on measurement, not promised for every display or favourite count.

**Desk-review findings and implementation implications**

- Existing `StatsStore.visibleStats` filters availability. Ring needs a separate ordered enabled
  identity projection with unavailable placeholders; directly reusing the filtered array would
  violate stable slots and make More counts jump.
- Existing detail positioning is below/above the strip and may clamp over its owner. A ring
  geometry resolver must place children using the reserved expansion area, not reuse that rule.
- Existing Escape hides everything. Introduce the hierarchy only for Ring; preserve other layouts.
- Separate preview/held state from `isPinned`. Reuse one detail data source/history selection;
  switching layout must not create sampling or retention lifecycles.
- Static review checks content fit and state completeness only. Timing, non-activating first-click
  delivery, accessibility, pointer corridors and long interactive detail forms need a native
  prototype and live acceptance. The mockup graph and detail rows are illustrative, not full cards.

### Colour behaviour

The shared mode lives in Appearance and governs all layouts; each stat resolves its own colour.

| Mode | Behaviour |
|---|---|
| Off | Neutral/theme accent values and surfaces; retain readable non-colour state information |
| Value colour | Existing status-colour treatment on the stat value/icon; panel stays calm |
| Subtle tile tint | Apply a restrained status tint to that stat's cell/segment; readable foreground and calm panel backing |

- Existing installations start in Value colour, retaining their current theme. Mono continues
  to suppress semantic hue in every mode. Do not silently recolour an existing installation.
- Reuse existing status-band hysteresis. Rendering a layout or opening another surface must not
  count as a new sample or reset the previous band.
- Colours describe the metric's actual basis. CPU utilization, battery charge, disk capacity,
  thermal state and relative activity are not interchangeable measures of system health.
  Network/power activity colours must not claim a fault or hardware danger. No overall health score.
- Paired readings do not silently change the status source: CPU temperature beside usage does
  not make the CPU colour temperature-driven. Detail/help text identifies the basis where needed.
- Unavailable or invalid readings use a neutral unavailable state, not a reassuring green zero.
- Preserve distinct graph-series identities; upload is not assigned warning red merely because
  download is green. Selection/hover feedback remains distinguishable from status.
- Retain readable text and non-colour cues in Mono, light/dark appearances, custom colours,
  Reduce Transparency and Increase Contrast. Avoid flashing, pulsing and continuous animation.

## Acceptance Criteria

### Layouts and content

- **AC-01:** Given existing preferences, when upgrading, then Strip, enabled stats, order, theme,
  displayed values and retained history remain unchanged unless the user changes them.
- **AC-02:** Given each of the four layouts, when summoned with the same samples/settings, then
  visible readings and detail data agree; no layout creates another sampler or history store.
- **AC-03:** Given Grid or Rail and all supported stats enabled, when shown on the supported
  minimum display workspace, then every stat is reachable without clipped values or unreachable
  controls. A bounded scrolling fallback is allowed when content cannot fit.
- **AC-04:** Given paired values, long localized numbers, graph-only and combined display choices,
  when readings change, then text does not overlap and tile/segment positions do not shift.
- **AC-05:** Given no enabled stats, when any layout opens, then Settings remains accessible and
  the panel presents an understandable empty state.

### Ring expansion

- **AC-06:** Given up to eight favourites plus other enabled stats, when Ring opens, then favourites
  occupy stable positions and More provides access to every remaining enabled stat.
- **AC-07:** Given eight selected favourites, when attempting a ninth, then Settings explains the
  limit without silently replacing a favourite or disabling the stat in other layouts.
- **AC-08:** Given a favourite, when the pointer dwells over it or it is clicked, then its configured
  details appear; moving into those details keeps them available for interaction.
- **AC-09:** Given More, when hovered or clicked, then an additional ring appears; a stat there
  exposes the same detail content without creating a third ring or collapsing the access route.
- **AC-10:** Given rapid movement between parents, when the active branch changes, then at most
  one More expansion and one detail remain active and stale hover timers cannot reopen a previous branch.
- **AC-11:** Given a temporarily unavailable favourite, when data disappears and returns, then its
  position is preserved and unavailable data is distinct from measured zero.
- **AC-12:** Given an expanded Ring near a screen edge or on mixed-scale displays, when details
  open, then the active target stays fixed and all controls remain usable inside the visible
  workspace. A readable list/card fallback is allowed when an outer ring cannot fit; stats
  must never be silently dropped or text shrunk below the accepted readable size.
- **AC-13:** Given hover is not used, when a user activates the equivalent controls by click or
  accessibility action, then More and stat details remain reachable. Escape and whole-HUD
  dismissal follow the defined hierarchy without stealing focus from the frontmost app.

- **AC-20:** Given a held detail, when hovering other stats or More, then it stays unchanged;
  clicking another stat replaces it, and interacting with a preview first holds it.
- **AC-21:** Given More with a child detail, when pressing Escape repeatedly, then detail, More,
  and HUD close in that order; closed targets cannot reopen from stale timers or stationary hover.
- **AC-22:** Given 0, 1, 6 or 8 favourites and up to twelve enabled stats, when opening More,
  then every enabled non-favourite remains reachable, including unavailable entries, with no overlaps.
- **AC-23:** Given a screen-edge summon or long configured readings, when choosing geometry,
  then the full branch fits or the declared list fallback is chosen before input; no later hover
  relocates the owner. Drag/dismiss/display removal cancels pending expansion callbacks.

### Appearance and persistence

- **AC-14:** Given one stat crossing a built-in band boundary, when dynamic colouring is enabled,
  then only its value/segment changes colour; the panel background and unrelated stats do not.
- **AC-15:** Given samples oscillating inside the existing hysteresis dead zone, when any layout
  redraws or a detail opens, then colour does not alternate due to rendering frequency.
- **AC-16:** Given Off or Mono, when load changes, then the UI stays neutral while numeric and
  non-colour information remains available; graph-series meaning is preserved.
- **AC-17:** Given saved layout, favourites, colour mode and custom theme, when restarting, then
  preferences round-trip; unknown/corrupt new values fall back safely without erasing other data.
- **AC-18:** Given appearance/layout reset, when confirmed through an explicitly scoped reset,
  then presentation defaults return without clearing retained history, cumulative totals or
  updater preferences. Existing global Reset to Defaults retains its separately documented scope.
- **AC-19:** Given each shipped preset plus representative custom light/dark colours and system
  accessibility settings, when using any layout, then values, selection and status remain legible;
  Reduce Motion removes nonessential expansion motion without delaying input.

## Technical Considerations

### Existing implementation and integration

- `StatsStripView` renders `StatsStore.visibleStats` using `StatDescriptor`, `StatTileView` and
  shared theme values. Add presentations around this data rather than duplicating sampling logic.
- `AppSettings` persists theme/value choices; `Theme`, `ThemePreset` and `StatusBand` already
  implement custom appearance and status-band hysteresis. New settings require backward-compatible
  decoding; older custom theme payloads must still load.
- `PanelWindowController` measures/clamps the HUD, and `DetailPanelController` owns detail display.
  Explicit expansion geometry must be separated from sample-driven content updates.
- Existing bands include relative activity proxies. Inspect their provenance and label their
  meaning before emphasizing backgrounds; this spec does not introduce new health measurements.
- Reference ideas: MousePlus's stable rings, central dead zone, branch continuity and shared
  geometry for rendering/hit testing; LaunchAway's bounded expansion; StatsWindow's separation
  of headline readings and deeper detail. Do not import MousePlus trigger/Accessibility machinery.

### Proposed settings placement and wiring

- **Panel → Layout:** Native popup for four layouts before existing placement/size controls.
  Strip height remains strip-specific; do not reinterpret its saved value as a ring diameter.
- **Stats → selected stat options:** Favourite in Ring checkbox beside existing options, outside
  the draggable list row. Show count/limit without adding a separate favourites editor.
- **Appearance:** One colour-mode popup alongside the existing theme selector; reuse existing
  custom appearance controls and a small preview. No additional settings window.
- Controls write persistent `AppSettings` properties; presentation consumes them through the
  existing observation path. New/modified interactive controls use AppKit wrappers per shared
  conventions; do not copy the existing SwiftUI colour-picker/slider exceptions into new work.
  HUD custom hit regions need equivalent accessibility actions.
- The app remains an `LSUIElement` non-activating HUD with Carbon hotkeys. No Dock icon,
  menu-bar item, document shell, network service or new permission is introduced.

### Design gate and finite validation

- First refine only the ring interaction/geometry with representative fixtures: 1, 6 and 8
  favourites, additional stats, long paired readings, unavailable values, and edge placement.
- Show collapsed ring, stat detail expansion and More expansion, including pointer travel.
  PNGs remain available because the owner's device cannot display the inline visualization.
- The first concept image is not visual acceptance. Obtain review of the refined ring and
  proposed settings placement before broad implementation; no implementation is authorized here.
- Stop/replan the affected ring approach if it cannot fit legible content or preserve the pointer
  route. Simplify geometry or use the stated list/card fallback rather than adding recursive rings.
- Automated verification should cover meaningful geometry/hit-testing, expansion cancellation,
  settings migration and colour semantics. Actual signed-artifact acceptance covers pointer
  travel, focus, pin/drag/dismiss, display edges, appearance and persisted settings. Reuse valid
  existing sampler/history evidence; do not repeat unrelated release tests solely for this spec.

## Out of Scope

- New metrics/samplers, memory-pressure or disk-accuracy work, alert notifications and rules.
- User-adjustable thresholds, per-stat status palettes, arbitrary layouts, scripting, profiles,
  theme marketplace, custom gauge designer, or animated/pulsing backgrounds.
- Multiple nested outer rings, hover timing sliders, and MousePlus-style action execution.
- A new historical data model, cloud sync, export, remote monitoring or new permissions.
- Changing the prepared 1.2.1 release or treating its open acceptance/backup gates as complete.

## Open Questions and Review Decisions

| Item | Status | Answer / proposed resolution |
|---|---|---|
| Colour scope | Confirmed | Each stat independently; calm panel backing |
| Starting ring | Confirmed | Up to eight favourites; other stats remain accessible |
| Hover expansion | Confirmed | Both details and a More route to additional stats |
| Customization limit | Confirmed | Existing theme knobs plus layout and three colour modes; built-in thresholds, no alerts/rule editor |
| Final ring geometry and centre/More placement | Wedge direction accepted; exact geometry remains provisional | MousePlus-style wedges confirmed by owner; circular geometry, quiet hub and expanded states revised in four PNGs |
| Hover dwell/close timing and pointer corridor | Defaults resolved; native validation pending | 350 ms dwell, 450 ms leave, bounded 700 ms transit grace; held detail wins over hover |
| Settings placement, shared colour selector and proposed interaction defaults | Draft for review | As described above; no implementation approval implied |
| Minimum workspace and text-size validation matrix | Proposed for validation | 1024 × 640 and 1440 × 900 visible points, 1×/2×; 13/16/12-point baseline; measured fallback |
| D-006 / D-008 evolution | Decision required at approval | Strip stays default; alternate geometry and deliberate expansion extend the strip-only contract, never sample-driven resizing |

## Related

- [Themes specification](themes.md)
- [Decisions D-001, D-006, D-007, D-008 and D-015](../docs/decisions.md)
- [Project state](../docs/PROJECT_STATE.md)
- [1.2.1 release preparation — separate work](../docs/evidence/release-1.2.1.md)
- Local concept PNG (illustrative, not approved final design):
  `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/output/layout-exploration/panel-layouts.png`
