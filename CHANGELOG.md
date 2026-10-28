# Changelog

## [Unreleased]

## [1.2.0] — 2026-10-28

- Network and Disk history for 1 minute, 1 hour, and 24 hours, retained across app restarts.
- Selected-period transfer totals and independently resettable cumulative Network/Disk totals.
- Explicit missing-time and partial-source indicators, saved-state feedback, and bounded checkpoint recovery.
- Native category toolbar and compact per-stat editors in Settings.

- Temperature headline choices: thermal status, CPU/GPU temperature, or status plus CPU/GPU; Celsius/Fahrenheit across temperature readouts.
- Disk headline choices for capacity or live read/write activity.
- Selectable detail rows across every stat, including available fan and temperature sensor rows.

- Power headline choices: whole system (default), chip total, CPU, GPU, labeled CPU + GPU, or charger input.
- Load headline choices: 1-, 5-, or 15-minute averages, or 1-minute load beside core count.
- Configurable Power and Load detail rows, with metric explanations in Settings → Stats.
- Reset to Defaults now also clears tile value and graph choices.

## [1.1.0] — 2026-10-03

### Added

- Configurable headline values and text, graph, or combined presentation per tile.
- Mirrored one-minute activity graphs for CPU, GPU, memory, network, and disk.
- CPU/GPU temperature sensors, whole-machine power detail, and richer detail-card rows.
- Automated logic tests for history scaling, ring-buffer ordering, and network-interface filtering.

### Improved

- Network totals now count active physical links, avoiding loopback inflation and VPN duplication.
- Graph peaks decay once per sample without jumping when an old spike leaves the window.
- Panel dragging uses AppKit's native window loop for immediate cursor tracking.
- Settings hotkey glyphs are larger and spaced for readability.

## [1.0.0] — 2026-07-12

- First public, signed and notarized release.
- Hotkey-summoned HUD with CPU, memory, disk, network, battery, GPU, fans, power, temperatures,
  load average, uptime, and top-process detail.
- Configurable stats, themes, placement, refresh interval, hotkeys, and launch-at-login.
