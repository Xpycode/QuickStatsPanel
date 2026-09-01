# Changelog

## [1.1.0] — 2026-09-01

### Added

- Configurable headline values and text, graph, or combined presentation per tile.
- Mirrored one-minute activity graphs for CPU, GPU, memory, network, and disk.
- Per-core CPU/GPU temperatures, whole-machine power detail, and richer detail-card rows.
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
