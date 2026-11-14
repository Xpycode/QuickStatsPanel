# Panel Layouts and Dynamic Appearance Specification

**Status:** Draft — product scope confirmed; ring interaction accepted in native review; gauge
look, small hub, More wedge and sub-rings (D-035, D-036) specified and awaiting the gauge prototype
**Created:** 2026-11-12
**Last updated:** 2026-11-13
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
- November 13 native review (D-035): the interaction is accepted; the look follows the gauge
  mockup. Wedges are radial gauges with equal-area fill by default and linear as an option. Disk
  shows capacity with a thin I/O rim. Ring size uses presets in which text never shrinks. The hub
  is small (Settings gear and drag). Nothing expands from the centre.
- Stat wedges open sub-rings of their parts: CPU → cores, Disk → volumes, Network → interfaces,
  Temperature → sensors. Non-favourites are reached through a More wedge in the ring.
- November 13 follow-up (D-036): a sub-ring and its detail card open together as one branch. The
  More wedge is a narrow extra wedge at six o'clock, outside the eight favourite slots.
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
2. **Expandable gauge ring:** Up to eight selected favourites in stable positions, each wedge a
   radial gauge of its stat. A narrow More wedge reaches other enabled stats; four stats open a
   sub-ring of their parts. Hover/click reaches the same detail content used elsewhere. Only one
   outer arc and one detail surface may be open at a time. Ring size is a preset.
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
4. Summon the HUD. Favourite stats appear around the pointer as gauge wedges with readable
   labels and values; how full each wedge is shows how close that stat is to its ceiling.
5. Hover CPU: its cores appear as an arc outside the wedge and its configured details/history
   open beside the ring. Move into either without collapse.
6. Hover the More wedge to reveal remaining enabled stats, then hover or click one for its details.
7. Dismiss and reopen: preferences persist; sampling and retained history remain intact.

Observable success: readings and detail content agree with the existing layouts, every enabled
stat is reachable, dynamic colour affects only the relevant stat, and no interaction requires
chasing a moving target.

### Layout and interaction defaults proposed for review

- **Grid:** Compact rectangular cells with a preferred three-column arrangement; reduce columns
  when necessary for the display. Do not stretch cells solely to force an exact square.
- **Rail:** One vertical column, preserving existing order. It uses the existing anchor system;
  edge placement is available, not forced.
- **Ring:** One starting ring of gauge wedges, horizontal text, a small hub, and a clearly
  distinct More wedge that does not consume one of the eight favourite slots. The centre never
  duplicates a reading. Rich history and interactive details use a readable detail surface rather
  than being squeezed into wedge-shaped charts.
- Favourites form a saved subset of enabled stats and follow existing stat order. Initial
  selection uses up to the first eight enabled stats; subsequent explicit choices are preserved.
  Disabling a favourite makes it inactive without deleting its saved membership.
- Temporarily unavailable ring favourites retain their positions with an unavailable indication.
  They do not become measured zero. Other slots do not rotate to fill a transient gap.
- More contains enabled non-favourites; it is absent when none exist. One outer band only: no
  ring beyond it, no independent ring-order editor, and no app-specific layout profiles.
- Ring hover uses a short fixed dwell and a forgiving close delay; click offers an immediate
  equivalent and can hold the detail open. The 350 ms dwell and 450 ms close delay passed native
  review and are not exposed as settings. Held details ignore hover replacement and close by owner
  click, Close, or Escape.
- Pointer travel through a child ring/detail preserves that branch. Moving deliberately to
  another parent replaces it; crossing the centre does not accidentally select a stat.
- Escape closes the detail (and its sub-ring) first, then More if open, then the HUD on the next
  press. Hotkey and click-away retain whole-HUD dismissal semantics, respecting the existing Keep
  on Screen behaviour.
- Hover expansion is required for Ring. Strip/Grid/Rail keep reliable click-to-open details;
  adding hover to those layouts is not required for this first version.
- Geometry-changing settings take effect on the next summon, consistent with the strip's
  current stability contract. Colour/theme changes can apply live without moving controls.

### Ring contract — revised November 13 (D-035, D-036)

The native prototype review (E1) accepted the interaction — hover and hold, Escape order, drag, pin
and edge placement — and redirected the look and structure to the gauge mockup
(`output/ring-gauges/ring-gauges.html`). This section replaces the November 12 contract's geometry,
centre and More rules. Points marked **(confirmed)** are owner choices; everything else is a
proposed baseline for the gauge prototype review, not a claim of working behaviour. The November 12
review images in `02_Design/ring-review/` show the superseded large hub and are historical.

**Structure**

- Three levels, outward only **(confirmed)**: the favourites ring → one child arc in an outer band
  (a stat's sub-ring of parts, or the More arc) → one detail card. Nothing expands from the centre.
- At most one child arc and one detail card are open. Opening another branch replaces the current
  one atomically. A stat reached through the More arc opens its detail card only; there is no
  third radial level.

**Geometry and size presets**

- Favourites are circular annular wedges, as in D-034. The wedge is the visible surface, the hit
  target and now the gauge. Labels and readings stay horizontal. A separate outline marks selection.
- Size is a preset, not a free slider, and text never shrinks **(confirmed)**. Labels, headlines and
  secondary text are 13/16/12 points in every preset. Baselines to validate natively, taken from the
  mockup's range (its default is 360 points):

  | Preset | Outer diameter | Inner radius | Wedge depth | Footprint with outer band |
  |---|---|---|---|---|
  | Small | 260 pt | 47 pt | 83 pt | 400 pt |
  | Medium (default) | 360 pt | 65 pt | 115 pt | 500 pt |
  | Large | 460 pt | 83 pt | 147 pt | 600 pt |

  Inner radius is 36 % of the outer radius (the mockup default). Separators are 4 points. The
  prototype's fixed 520-point ring and 820-point outer ring are retired.
- A preset fixes geometry; it never scales text. Each wedge shows the richest content that fits its
  own sector, measured before summon against the stat's widest strings (D-008): label + value +
  secondary → label + value → icon + value → icon only. The chosen rung is frozen for that summon
  and does not change as readings change. A Wedge text preference sets the upper rung. Icon only
  always fits; the full reading stays available in the detail card and to accessibility.
- With a More wedge present, favourites share the remaining arc in equal sectors, tiled clockwise
  from the More wedge's trailing edge. Favourite 1 is the first sector whose centre lies clockwise
  from twelve o'clock; order continues clockwise and skips More. Without a More wedge, favourites
  tile the full circle with the first centred on twelve o'clock. One favourite uses a 60-degree
  wedge at twelve o'clock. Slot positions are frozen per summon; explicit membership or order
  changes may redistribute them next time, sample availability cannot.
- Rendering and hit testing share centre, radii and angular boundaries, all derived from the preset
  rather than constants. The hub, separator gaps and inactive annulus select no stat.

**Hub**

- The hub is small **(confirmed)**: a Settings gear and a drag area, nothing else. Baseline disc
  radius is the inner radius minus 6 points. The gear target is at least 28 × 28 points and the rest
  of the disc drags. The word "Settings" appears beside the gear only when the disc radius is at
  least 58 points (Medium and Large), as in the mockup.
- Keep on Screen keeps its context-menu and hotkey control; a small pin glyph in the hub shows it is
  on. The hub never repeats a reading and never opens More or any ring.
- Empty states move out of the hub. No favourites: the More wedge remains and a short message sits
  in the empty annulus. No enabled stats: the hub's gear remains with an empty-state message.

**Wedge gauges**

- Each wedge is a radial gauge **(confirmed)**: the inner edge is zero, the outer edge is the stat's
  ceiling, and the fill grows outward over a faint empty track.
- Fill scale is equal-area by default with linear radius as an option **(confirmed)**. For fraction
  `f`, inner radius `r0` and outer radius `r1`: equal-area `r = sqrt(r0² + f·(r1² − r0²))`; linear
  `r = r0 + f·(r1 − r0)`. Fractions clamp to 0…1. Stacked components use cumulative fractions, so
  the outer reach is the total.
- Faint dotted reference arcs sit at 25, 50 and 75 % in the active scale. Where adjacent arcs would
  be less than 8 points apart, only the 50 % arc is drawn.
- A 60-second peak tick marks the recent maximum where the table says so. No sparkline runs along
  the arc. Nothing pulses or animates continuously.
- The gauge is a glance cue; the number remains the reading. Each stat's fill has one fixed basis:

  | Stat | Fill | Scale | Also |
  |---|---|---|---|
  | CPU | User, system, nice stacked | 0–100 % of all cores | Peak tick |
  | Memory | App, wired, compressed, other used stacked; empty is free | 0 to installed memory | — |
  | Disk | Used capacity **(confirmed)** | 0 to boot volume size | Thin outer I/O rim **(confirmed)**: brightness follows read + write on the log rate scale; it never changes the fill |
  | Network | Split wedge: download left half, upload right half | Log, 1 KB/s to 1 GB/s; marks at 100 KB/s and 10 MB/s | Peak tick per half |
  | Battery | Charge | 0–100 % | Bolt when charging, amber plug when plugged in but not charging, plug when full on power, no mark on battery |
  | GPU | Utilisation | 0–100 % | Peak tick |
  | Power | CPU, GPU, Neural Engine, DRAM, rest of system stacked | 0 to a fixed ceiling per Mac | Peak tick |
  | Temperature | Hottest valid sensor | 30–100 °C | Heat ramp fixed to radius; thermal state as text and as a wedge tint from Fair upward |
  | Fans | Fastest fan between its minimum and maximum speed | Minimum to maximum rpm | New encoding, not in the mockup |
  | Load | Selected load average ÷ active core count | 0 to 1.0 per core, clamped | New encoding, not in the mockup |
  | Uptime | No fill | — | Text on the plain track; new, not in the mockup |

- The log rate scale is fixed, so a gauge never rescales silently. The rate fraction is
  `(log10(bytes per second) − 3) ÷ 6`, clamped.
- The fill basis does not follow the configured text reading. Text shows the reading the user
  chose (for example Free instead of Used, or a CPU temperature instead of the hottest sensor); the
  detail card names the gauge basis where the two differ. Whether that reads acceptably is a
  prototype review item.
- The gauge fraction is a presentation value. It does not replace the status band's input or
  hysteresis, and drawing a gauge is never a new sample.
- Unavailable stats keep their slot and show the neutral track with no fill and an unavailable
  indication. They never show a measured zero. A Mac without a battery, fans or valid temperature
  sensors shows that stat as unavailable in the same way.
- Fills update at the sampling cadence. One short ease of at most 0.2 seconds is allowed; under
  Reduce Motion the fill steps.

**More wedge**

- Non-favourite enabled stats are reached through a More wedge in the ring **(confirmed)**. It is a
  narrow extra wedge centred on six o'clock **(confirmed)**, baseline 24 degrees, showing an icon and
  the count of remaining stats. It has no gauge fill and is not one of the eight favourite slots.
- It is absent when no enabled non-favourite exists. Unavailable enabled stats stay reachable in it.
- Dwell previews and click holds the More arc: an arc in the outer band centred on six o'clock,
  holding every enabled non-favourite in existing order as a full gauge wedge with text. Current
  inventory is eleven stats, so the arc holds anywhere from one to eleven entries: never assume three.
- The eight-favourite limit, saved membership and Settings wording are unchanged from November 12.

**Sub-rings**

- Four stats open a sub-ring of their parts **(confirmed)**: CPU → cores, Disk → volumes, Network →
  interfaces, Temperature → sensors. The sub-ring and the detail card open together as one branch
  **(confirmed)**: dwell previews both, click holds both, and Close or Escape closes both.
- A sub-ring is an arc in the outer band centred on its parent wedge's mid-angle, so the pointer
  reaches it by moving outward without crossing a sibling wedge. Each part is a small gauge segment
  on the parent's scale and colour basis.
- Parts are display-only. Hovering a segment shows a caption with its name and value; clicking in
  the arc holds the branch, like interacting with a preview. Segments open nothing further.

  | Stat | One segment per | Segment shows | Rules |
  |---|---|---|---|
  | CPU | Logical core | Core usage, 0–100 % | Grouped by core class (efficiency, performance, and super where the chip has it) with a wider gap between groups. No classes on Intel. Plan for 32; beyond that, pair hyperthreads, then group |
  | Disk | Storage container | Used fraction | Visible local volumes only; volumes sharing an APFS container appear once. Same capacity basis as the Disk wedge. No per-volume I/O exists, so segments have no rim |
  | Network | Counted interface | Download and upload halves on the log scale | Exactly the interfaces the Network total sums, with system display names such as Wi-Fi. Tunnels are not added, because their traffic is already counted on the physical interface |
  | Temperature | Sensor | Temperature on the 30–100 °C ramp | Grouped by the existing roles (CPU, GPU, SoC, SSD, Battery). Same-named sensors are merged; readings outside 0–110 °C are dropped. Never labelled as individual cores |

- Parts agree with the parent: core usage averages to the CPU total, interface rates sum to the
  Network reading, the boot container matches the Disk reading, and the hottest segment matches the
  Temperature fill.
- A stat with fewer than two parts on this Mac has no sub-ring; its detail card still opens. The
  part list and its order are frozen per summon. Parts are never sorted by value.
- Segments carry a label and value only when the measured text fits. Otherwise they are unlabelled
  slivers at least 8 points wide with the hover caption. Above 32 parts, the largest group collapses
  to one segment showing its hottest or highest member, repeated until 32 or fewer remain.

**Outer band and child arcs**

- The outer band starts 6 points outside the favourites ring. Baseline depth is 44 points for a
  sub-ring and 64 points for the More arc, which carries text.
- An arc's span is the sum of its entries' measured angular needs, at least as wide as its parent
  wedge and at most a full circle. It is centred on the parent and computed once per summon.
  Opening an arc never moves a favourite wedge or the hub.
- A More arc that cannot fit its entries in a full circle uses the More list. A sub-ring that cannot
  fit uses the sliver and grouping rules above. No pagination and no second outer band.

**Interaction state and precedence**

Timings, hold semantics and precedence passed native review and are unchanged; rows are reworded
for the More wedge and sub-rings.

| Input / situation | Result |
|---|---|
| Summon | Collapsed; no remembered detail, sub-ring or More expansion. Suppress hover until actual pointer movement so clamping cannot open a stat under a stationary pointer. |
| Dwell on a stat wedge for 350 ms | Preview its branch — the detail card, plus the sub-ring when it has one — unless a held branch exists. Moving to another stat restarts dwell. |
| Click a stat wedge / accessibility Press | Open its branch immediately and hold it; a preview of that same stat becomes held. Clicking the held owner again closes it; clicking another stat replaces it with a held branch. |
| Interact with preview content | Mouse-down in the detail card or the sub-ring arc promotes the branch to held before processing graph, range or reset controls. Hover never invokes a reset. |
| Hover a sub-ring segment | Show its caption. No dwell target, no further level. |
| Dwell on the More wedge / click it | Dwell previews the More arc or list; click holds it. Clicking an already held More wedge closes it and its child detail. The first click on a hover-open More holds it. |
| Hover while a branch is held | No replacement and no More opening. Clicking the More wedge explicitly closes a favourite's branch and opens and holds More. |
| Select a stat in the More arc | Keep the More arc visible while that stat's preview or detail is active. A held child also holds the More arc. No sub-ring opens. |
| Select a favourite from the whole-list fallback | On completed dwell (if unheld) or explicit click, open that favourite's detail atomically. |
| Close button / Escape | Close the detail and its sub-ring together, leaving the More arc if it owns that detail; the next Escape closes More; the next hides the HUD, even when Keep on Screen is on. |
| Hotkey | Hide the entire HUD and cancel all expansion timers, including while pinned. |
| Click outside, unpinned | Hide the entire HUD. Clicks in any child surface are inside. |
| Click outside, Keep on Screen | Leave the HUD and explicitly held surfaces open; hover previews close after their normal leave delay. |
| Drag the hub | Cancel pending hover and close expansions before moving. Save position with current anchor semantics; resume hover only after mouse-up and movement. |
| Open Settings / hide / display removed | Cancel timers and close descendants. Settings follows the existing activating-window path. Display removal dismisses; next summon recomputes geometry. |

- Leave delay: 450 ms outside the union of owner wedge, child arc, the gap between them, detail
  card and safe travel region. Re-entry cancels the close. While travelling toward the detail card,
  preserve the branch and suppress crossed sibling hover for at most 700 ms; a deliberate click
  always wins. If the pointer stops on a sibling, normal 350 ms dwell resumes. Crossing the hub
  alone does not open or replace anything.
- Build travel regions from actual rendered frames (including the gap), not assumed angles.
  Allow 12 points of route tolerance. Travel regions preserve state but are not clickable surfaces
  and must not intercept clicks intended for another app. Avoid a giant invisible input window.
- Closing with owner click, Close or Escape suppresses reopening under the stationary pointer
  until it exits and re-enters that target. Timers carry a summon/branch generation; stale callbacks
  cannot reopen anything after dismissal, drag, settings, or a newer selection.
- Keep on Screen retains current per-summon semantics and resets when the HUD hides. Holding a
  branch does not turn it on. No new global arrow-key/Tab capture.
- Accessibility: each wedge is a pressable element announcing name, value, availability and
  expanded state; Press is the click equivalent. The More wedge announces its count. Sub-ring
  segments are read-only children of the expanded wedge with name, value and range. Canvas drawing
  provides none of this by itself, so the elements are explicit.

**Screen edges and finite fallback**

- Choose a host display, stable base position, expansion side and presentation mode at summon.
  Reserve the preset's footprint with outer band plus the measured largest configured detail card
  before placing the base. The card sits beside that footprint, never over its owner or the open
  arc. Do not wait until hover to discover that the selected stat must move.
- If the outer band cannot fit on that summon, sub-rings are omitted (detail cards still open) and
  More uses a fixed side area: a More list above the single detail card. The list remains
  accessible while its detail is open. Large lists and tall details scroll independently.
- Prototype minimum: 1024 × 640 **visible points**, not physical pixels. If the ring plus a
  380-point side area cannot fit, use a compact labelled list for the entire presentation on that
  summon, retaining favourites first and Settings. Preserve the saved Ring and size preferences; do
  not clip or scale text.
- Detail cards keep Close visible: Close sits outside the scrolling region, and the card is measured
  with its process rows reserved whether or not samples have arrived (review item C1).
- Validate 1024 × 640 and 1440 × 900 visible points, all four edges/corners, 1×/2× and mixed-scale
  displays, in each size preset. Geometry and hit testing share point coordinates.

**Review findings and implementation implications**

- Existing `StatsStore.visibleStats` filters availability. Ring needs a separate ordered enabled
  identity projection with unavailable placeholders; directly reusing the filtered array would
  violate stable slots and make More counts jump.
- Existing detail positioning is below/above the strip and may clamp over its owner. A ring
  geometry resolver must place children using the reserved expansion area, not reuse that rule.
- Existing Escape hides everything. Introduce the hierarchy only for Ring; preserve other layouts.
- Separate preview/held state from `isPinned`. Reuse one detail data source/history selection;
  switching layout must not create sampling or retention lifecycles.
- Native review results are in `docs/evidence/ring-prototype.md`. Rows not run there (text fit,
  unavailable slots, second display, accessibility, settings placement, card controls) are repeated
  on the gauge ring, not treated as passed.

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
- Gauge fills: the mockup's default gives each stat its own hue, with lighter steps for stacked
  components, and a heat ramp for Temperature whose lightness rises with heat. Mono keeps a
  single neutral fill. The gauge prototype uses that default. How the shared colour mode maps onto
  gauge fills (for example Subtle tile tint → status-band fill) is an open review item, as is the
  known mismatch where a status band's input scale differs from the gauge scale (Network, Power).
- The fill's outer edge must stay visible against the empty track at 3:1 or better, so the level
  reads without colour. With Increase Contrast or Differentiate Without Colour, draw that edge
  as an explicit line.

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
  occupy stable positions and the More wedge provides access to every remaining enabled stat.
- **AC-07:** Given eight selected favourites, when attempting a ninth, then Settings explains the
  limit without silently replacing a favourite or disabling the stat in other layouts.
- **AC-08:** Given a favourite, when the pointer dwells over it or it is clicked, then its configured
  details appear; moving into those details keeps them available for interaction.
- **AC-09:** Given the More wedge, when hovered or clicked, then the More arc appears in the outer
  band; a stat there exposes the same detail content without opening a sub-ring, a further ring
  or collapsing the access route.
- **AC-10:** Given rapid movement between parents, when the active branch changes, then at most
  one More expansion and one detail remain active and stale hover timers cannot reopen a previous branch.
- **AC-11:** Given a temporarily unavailable favourite, when data disappears and returns, then its
  position is preserved and unavailable data is distinct from measured zero.
- **AC-12:** Given an expanded Ring near a screen edge or on mixed-scale displays, when details
  open, then the active target stays fixed and all controls remain usable inside the visible
  workspace. A readable list/card fallback is allowed when the outer band cannot fit; stats
  must never be silently dropped or text shrunk below the accepted readable size.
- **AC-13:** Given hover is not used, when a user activates the equivalent controls by click or
  accessibility action, then More and stat details remain reachable. Escape and whole-HUD
  dismissal follow the defined hierarchy without stealing focus from the frontmost app.

- **AC-20:** Given a held detail, when hovering other stats or More, then it stays unchanged;
  clicking another stat replaces it, and interacting with a preview first holds it.
- **AC-21:** Given More with a child detail, when pressing Escape repeatedly, then detail, More,
  and HUD close in that order; closed targets cannot reopen from stale timers or stationary hover.
  Given a favourite's held branch, one Escape closes its sub-ring and detail together.
- **AC-22:** Given 0, 1, 6 or 8 favourites and up to eleven enabled stats, when opening More,
  then every enabled non-favourite remains reachable, including unavailable entries, with no overlaps.
- **AC-23:** Given a screen-edge summon or long configured readings, when choosing geometry,
  then the full branch fits or the declared list fallback is chosen before input; no later hover
  relocates the owner. Drag/dismiss/display removal cancels pending expansion callbacks.

### Gauges, hub and size

- **AC-24:** Given a stat at fraction f with equal-area fill, when drawn, then filled area ÷ wedge
  area equals f; with linear fill, filled depth ÷ wedge depth equals f. Zero draws no fill, one
  fills the wedge, and out-of-range values clamp.
- **AC-25:** Given a stacked stat (CPU, Memory, Power), when drawn, then components appear in the
  stated order and the outer reach equals their total.
- **AC-26:** Given Disk, when read and write rates change, then only the rim's brightness changes;
  the fill follows used capacity and agrees with the Disk reading.
- **AC-27:** Given Network, when rates range from below 1 KB/s to above 1 GB/s, then download fills
  the left half and upload the right half on the fixed log scale; the scale never changes by itself.
- **AC-28:** Given an unavailable stat or a Mac without that hardware, when the ring opens, then the
  wedge keeps its slot and shows the empty track with an unavailable indication, never a zero fill.
- **AC-29:** Given each size preset, when the ring opens with 1, 6 or 8 favourites and worst-case
  strings, then text is 13/16/12 points, horizontal and unclipped, each wedge shows the richest
  content that fits, and nothing moves or changes rung as readings change during that summon.
- **AC-30:** Given the hub, when used, then it offers only Settings and drag; the gear target is at
  least 28 × 28 points; no pointer action on the hub opens More, a sub-ring or a detail.
- **AC-31:** Given non-favourite enabled stats, when the ring opens, then a narrow More wedge sits at
  six o'clock with their count; given none, it is absent and favourites use the full circle.

### Sub-rings

- **AC-32:** Given CPU, Disk, Network or Temperature with two or more parts, when its wedge is
  dwelt on or clicked, then its sub-ring and detail card appear together, centred outside the
  parent wedge and beside the ring; Close, Escape or owner click closes both.
- **AC-33:** Given an open branch, when another wedge or More is opened, then at most one outer arc
  and one detail card remain; no favourite wedge or the hub moves when an arc opens.
- **AC-34:** Given a sub-ring, when compared with its parent at the same sample, then cores average
  to the CPU total, interfaces sum to the Network reading, the boot container equals the Disk
  reading and the hottest sensor equals the Temperature fill, within rounding.
- **AC-35:** Given 32 cores or 29 sensors, when the sub-ring opens, then every part is a segment at
  least 8 points wide, grouped by class or role, with name and value available on hover; given more
  than 32 parts, groups collapse by the stated rule and no part is silently dropped from the total.
- **AC-36:** Given a stat with fewer than two parts, or an outer band that cannot fit on this
  summon, when its wedge is opened, then the detail card still opens and no empty arc appears.
- **AC-37:** Given APFS volumes sharing one container, when Disk's sub-ring opens, then the container
  appears once. Given an unresponsive mounted volume, then summon, other stats and dismissal are
  not delayed.
- **AC-38:** Given part lists that change while the HUD is open (a drive is ejected, an interface
  drops), when samples arrive, then segment positions stay frozen and the missing part shows as
  unavailable until the next summon.

### Detail cards and accessibility in Ring

- **AC-39:** Given real data and a card taller than its slot (CPU or Memory with process rows),
  when shown, then the content scrolls and Close stays visible and clickable without scrolling.
- **AC-40:** Given VoiceOver, when navigating the ring, then each wedge announces name, value,
  availability and expanded state, the More wedge announces its count, sub-ring segments are
  reachable as children with name and value, and Press matches click.
- **AC-41:** Given Reduce Motion, when values change, then fills step without tweening; given
  Increase Contrast or Differentiate Without Colour, the fill edge and every state remain
  distinguishable without relying on hue.

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

### Gauge ring: code and platform review (November 13)

Code facts come from a read-only review of the prototype and samplers; confirm line references at
planning. Platform facts carry their source; items checked on one Mac only (M1 Max, macOS 27.2)
say so.

**What stays.** The interaction state machine's timers, tokens and generations, travel regions,
arming and closed-parent rules, hold semantics, mouse forwarding, drag and replan, list fallbacks,
typography without shrinking, fixture launch plumbing and the accessibility element pattern.

**What changes.**

- `RingGeometry` (`Model/RingGeometry.swift`): radii are static constants (inner 100, outer 260,
  footprint 520). They become parameters from the size preset. Remove the hub's More target; add
  the More wedge slot; add one annular-sector function taking inner and outer radius per call,
  used for wedges, partial fills, the Disk rim and outer-band segments. No such function exists;
  the favourites and More outlines duplicate the same code with different constants.
- `RingReading` (`Model/RingPresentation.swift`): text and a band only. Add gauge content: ordered
  fill components with fractions, optional split halves, rim, peak and marks.
- `RingSnapshot`: favourites are currently the first eight enabled stats. It needs the saved
  favourites set and each stat's parts.
- `RingExpansion`, `RingNode`, `RingHit`, `RingPlan` (`Model/RingInteractionState.swift`,
  `Model/RingPlacement.swift`): one hub-owned More slot and a `viaMore` flag. Generalise to an
  outer arc owned by any wedge (More or a stat) plus one detail, with per-owner child surfaces.
  Estimated as a moderate refactor; the More-branch tests are rewritten against the More wedge.
- `RingPlacement`: the 820-point full outer ring becomes preset footprints with the outer band.
- Tests: of 92 ring tests, hover, dwell, hold, leave, transit, Escape, stale-token, drag and
  accessibility groups must survive. Hub-target, fixed-radius, outer-ring sizing and More-geometry
  tests are replaced.
- Review item C1, likely cause (read from code, not reproduced): card height is measured in
  `AppDelegate.toggleRing` before the top-process sampler starts, so CPU and Memory are measured
  without their process rows; the frame is frozen at that height; and the whole card, Close
  included, sits inside the scroll view. Fix: Close outside the scroll region, and measure with
  process rows reserved.

**Per-part data.**

| Parts | Today | Needed | Constraints |
|---|---|---|---|
| CPU cores | Not read; aggregate `host_statistics` only | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` tick deltas per core, freeing the buffer each read | Core class comes from each core's `cluster-type` in the device tree, never from index or `hw.perflevel` order: on the M1 Max checked, cpu0–1 are efficiency while perflevel0 is performance. Newer chips report a third class. Largest current Mac has 32 cores |
| Disk volumes | Boot volume only, via `statfs("/")` | Enumerate mounted volumes with resource keys; keep browsable local ones; group by container | APFS siblings report the container's total and free space, so summing double-counts. Keep the wedge's existing capacity basis for every segment. Network or stale mounts must never block: sample off the main thread at a slow cadence and skip non-local volumes. I/O counters are per physical device only |
| Network interfaces | Per-interface 64-bit counters are already read (`NET_RT_IFLIST2`), filtered to `en*`, up and running, then summed | Carry per-source deltas out of the accounting step; names for every counted interface | The SystemConfiguration interface list gave user-facing names without permission and omitted tunnels and system interfaces, so it works as an allow-list (one Mac). Never sum a tunnel with its physical interface. No new per-interface history store |
| Temperature sensors | Read individually (SMC table and the private HID path), then averaged into at most five roles | Keep the per-sensor readings alongside the role averages | Names are chip-specific and repeat: 64 services but 29 unique names on the M1 Max checked. Other monitors keep readings from 0 up to 110 °C. Sensors are thermal zones, not cores. Temperature sources reportedly changed in macOS 27, so an empty result must degrade to no sub-ring |

- Per-part sampling runs only while the panel is visible, like the existing top-process sampler.
  Hidden-panel cost does not rise.
- Existing values a gauge can use today: CPU user/system/total, memory components, disk capacity
  and read/write rates, network down/up, battery charge and source, GPU utilisation, power
  components and system watts, fan current/minimum/maximum, load averages, thermal state.
- Existing scales that would mislead in a gauge and are not reused for fills:
  `NetworkSample.activityPercent` (fixed 12.5 MB/s), `PowerSample.loadPercent` (session peak that
  only rises), temperature's four-step thermal mapping, `MemorySample.pressurePercent`
  (used ÷ total, not kernel pressure). They still drive status bands until that is decided.
- Rendering: 8 to about 40 sectors at the sampling cadence is light for either `Canvas` or shapes
  (judgement, not measured). `Canvas` has no per-element accessibility, so wedges and segments
  need the explicit element tree described above.

**Design evidence used.**

- Fill scale: readers under-read linear-radius sector fills badly (an encoded 50 % reads as about
  35 %) and judge by area up to about 65 % fill; a grid helps; the centre gives the largest error
  (Kiesel, Riehmann and Froehlich, EuroVis 2025). A hub reduces the difference between the two
  scales. This supports equal-area as default and the reference arcs.
- Reference marks improve accuracy and need at least 8 pixels between them (Heer and Bostock, 2010).
- Radial menus stay accurate to about eight items per level at two levels (Kurtenbach and Buxton,
  1993); Blender's guidelines limit pies to eight and keep positions fixed.
- A child arc centred on its parent is how MousePlus opens children; outward travel then needs no
  corridor through siblings.
- Auto-scaled rate graphs draw long-standing complaints that the reader cannot tell whether the
  network is busy; fixed and log scales are the usual remedies. This supports the fixed log scale.
- Apple's guidance: label a gauge's value, avoid many tiny discrete segments, never make motion or
  colour the only channel.

### Proposed settings placement and wiring

- **Panel → Layout:** Native popup for four layouts before existing placement/size controls.
  Strip height remains strip-specific; do not reinterpret its saved value as a ring diameter.
- **Panel → Ring (shown for Ring):** Size (Small / Medium / Large), Wedge text (Label and value /
  Icon and value / Icon only) and Fill scale (Equal area / Linear). Fill strength, track tint,
  reference arcs and peak ticks stay fixed at the mockup defaults (80 %, 10 %, on, on) unless
  review asks for them. Power's gauge ceiling, if it becomes a setting, belongs with the Power
  stat's options. The gauge prototype takes these as Debug launch options, not Settings controls.
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

- Done: the native interaction prototype (1, 6, 8 and all-stat fixtures, long paired readings,
  unavailable values, edge placement). Interaction accepted, structure redirected; see
  `docs/evidence/ring-prototype.md`.
- Next: a gauge prototype step, still Debug-only and excluded from Release. Its scope is gauge
  wedges on real data, the three size presets and content ladder, the small hub, the More wedge
  and arc, sub-ring arcs, the generalised branch state, and the C1 card fix.
- Sub-ring fixtures cover 10 cores in two classes, 32 cores, one and four volumes, three
  interfaces, 29 sensors and more than 32 sensors. Real per-part sampling may follow as its own
  step, each sampler change behind hostless tests; planning decides the split.
- Its native review repeats every E1 row that was not run or was superseded, in each preset, and
  adds the gauge items: fill legibility, fill basis differing from the text reading, mixed content
  rungs in one ring, hub size, More wedge reach and sub-ring travel.
- The mockup is the visual target, not acceptance. No production implementation is authorized
  here; settings placement is reviewed before any Settings control is built.
- Stop/replan the affected ring approach if it cannot fit legible content or preserve the pointer
  route. Simplify geometry or use the stated list/card fallback rather than adding recursive rings.
- Automated verification should cover meaningful geometry/hit-testing, expansion cancellation,
  settings migration and colour semantics. Actual signed-artifact acceptance covers pointer
  travel, focus, pin/drag/dismiss, display edges, appearance and persisted settings. Reuse valid
  existing sampler/history evidence; do not repeat unrelated release tests solely for this spec.

## Out of Scope

- New stat kinds, memory-pressure or disk-accuracy work, alert notifications and rules. Per-part
  breakdowns of CPU, Disk, Network and Temperature are in scope; they extend existing samplers.
- A sub-ring for stats other than those four, sub-rings for stats in the More arc, per-volume I/O,
  network volumes and tunnel interfaces in sub-rings, per-part history or per-part detail cards.
- Auto-scaling gauge ceilings, a charging pulse, sparklines along a wedge and a free size slider.
- User-adjustable thresholds, per-stat status palettes, arbitrary layouts, scripting, profiles,
  theme marketplace, custom gauge designer, or animated/pulsing backgrounds.
- A second outer band, hover timing sliders, and MousePlus-style action execution.
- A new historical data model, cloud sync, export, remote monitoring or new permissions.
- Changing the prepared 1.2.1 release or treating its open acceptance/backup gates as complete.

## Open Questions and Review Decisions

| Item | Status | Answer / proposed resolution |
|---|---|---|
| Colour scope | Confirmed | Each stat independently; calm panel backing |
| Starting ring | Confirmed | Up to eight favourites; other stats remain accessible |
| Hover expansion | Confirmed | Both details and a More route to additional stats |
| Customization limit | Confirmed | Existing theme knobs plus layout and three colour modes; built-in thresholds, no alerts/rule editor |
| Ring look and structure | Confirmed (D-035) | Radial gauge wedges, small hub with gear and drag, expansion from wedges only |
| Fill scale, Disk encoding, sizing | Confirmed (D-035) | Equal-area default with linear option; capacity plus I/O rim; presets, text never shrinks |
| Sub-ring and detail card | Confirmed (D-036) | Open together as one branch |
| More placement | Confirmed (D-036) | Narrow extra wedge at six o'clock, outside the eight favourite slots |
| Hover dwell/close timing and pointer corridor | Accepted in native review | 350 ms dwell, 450 ms leave, bounded 700 ms transit grace; held detail wins over hover |
| Child level shape | Proposed | Arc centred on the parent in one outer band, not a full ring |
| Preset dimensions and content ladder | Proposed for prototype review | 260 / 360 / 460 points; per-wedge richest content that fits, so one ring may mix rungs |
| Gauges for Fans, Load and Uptime | Proposed; not in the mockup | Fan speed within its range; load ÷ cores; Uptime without a fill |
| Fill basis differing from the configured text reading | Review on prototype | Fixed basis per stat; detail card names it |
| Gauge fill colour versus the shared colour mode | Open | Prototype uses per-stat hues; mapping of Off / Value colour / Subtle tile tint undecided |
| Status-band input for Network and Power | Open | Bands still use the old capped and session-peak scales, which disagree with the gauge |
| Power gauge ceiling | Open | Fixed per Mac; default value and whether it is a setting undecided |
| Which gauge options become settings | Proposed | Size, Wedge text, Fill scale; the rest fixed |
| Volumes shown | Proposed | Local browsable volumes by container; network volumes excluded; disk images undecided |
| Interfaces shown | Proposed | Only those the total counts (`en*`, up and running); bridges and tunnels excluded |
| Sensor labels and the 32-part cap | Proposed | Role groups; raw names in captions where no friendly name exists; largest group collapses first |
| Real per-part sampling in the gauge prototype or after it | Decided in planning (2026-11-14) | Fixtures first; real per-part sampling is a follow-up plan after the gauge review. See [plan](../IMPLEMENTATION_PLAN.md) |
| Settings placement, shared colour selector | Draft for review | As described above; not reviewed in E1; no implementation approval implied |
| Minimum workspace and text-size validation matrix | Proposed for validation | 1024 × 640 and 1440 × 900 visible points, 1×/2×, each preset; 13/16/12 points; measured fallback |
| D-006 / D-008 evolution | Decision required at approval | Strip stays default; alternate geometry and deliberate expansion extend the strip-only contract, never sample-driven resizing |

## Related

- [Themes specification](themes.md)
- [Decisions D-001, D-006, D-007, D-008, D-015, D-034, D-035 and D-036](../docs/decisions.md)
- [Ring prototype evidence and native review results](../docs/evidence/ring-prototype.md)
- Gauge mockup (visual target): `output/ring-gauges/ring-gauges.html`,
  [published copy](https://claude.ai/artifact/WNNwTzTsSQDTR63E8YUj9g)
- Research sources for the November 13 revision:
  [Kiesel et al. 2025, rose-chart fill perception](https://www.uni-weimar.de/fileadmin/user/fak/medien/professuren/Virtual_Reality/documents/publications/2025_Rose_Charts.pdf) ·
  [Heer and Bostock 2010](https://homes.cs.washington.edu/~jheer/files/2010-MTurk-CHI.pdf) ·
  [Kurtenbach and Buxton 1993](https://www.billbuxton.com/MMExpert.html) ·
  [Blender pie-menu guidelines](https://developer.blender.org/docs/features/interface/human_interface_guidelines/layouts/) ·
  [Apple HIG: Gauges](https://developer.apple.com/design/human-interface-guidelines/gauges) ·
  [Stats per-core, volume, interface and sensor readers](https://github.com/exelban/stats) ·
  [XNU `if_var.h` counters](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/if_var.h) ·
  [`getfsstat` and stale mounts](https://keith.github.io/xcode-man-pages/getfsstat.2.html) ·
  [GNOME System Monitor auto-scale complaints](https://gitlab.gnome.org/GNOME/gnome-system-monitor/-/issues/162)
- [Project state](../docs/PROJECT_STATE.md)
- [1.2.1 release preparation — separate work](../docs/evidence/release-1.2.1.md)
- Local concept PNG (illustrative, not approved final design):
  `/Users/sim/ProgrammingProjects/1-macOS/QuickStatsPanel/output/layout-exploration/panel-layouts.png`
