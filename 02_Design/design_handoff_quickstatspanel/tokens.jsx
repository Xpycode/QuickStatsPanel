// tokens.jsx — QuickStatsPanel design tokens (macOS dark HUD)
// Exposed on window.QS. Loaded first, before all other babel files.

const QS = {
  // Type
  font: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", system-ui, sans-serif',
  mono: 'ui-monospace, "SF Mono", "SFMono-Regular", Menlo, "Roboto Mono", monospace',

  // Panel / material (dark translucent vibrancy)
  panel: {
    radius: 12,            // 12pt — crisp, not Tahoe
    height: 54,            // ~36pt rendered ≈1.5× for legibility
    bg: 'rgba(34,34,37,0.62)',
    bgSolid: 'rgba(34,34,37,0.96)',
    border: 'rgba(255,255,255,0.16)',
    innerTop: 'rgba(255,255,255,0.10)',  // top inner highlight
    shadow: '0 1px 0 rgba(255,255,255,0.05) inset, 0 12px 34px rgba(0,0,0,0.46), 0 2px 6px rgba(0,0,0,0.34)',
    divider: 'rgba(255,255,255,0.085)',
  },

  // Text
  text: {
    value: 'rgba(255,255,255,0.94)',      // calm/neutral value
    label: 'rgba(255,255,255,0.42)',      // micro-label
    icon: 'rgba(255,255,255,0.62)',
    dim: 'rgba(255,255,255,0.30)',
  },

  // Semantic stress ramp — tuned for dark translucent bg.
  // calm is a near-neutral cool slate so "fine" never screams;
  // it warms amber → orange → red as the stat is stressed.
  ramp: {
    calm:     'oklch(0.80 0.035 225)',   // cool slate-neutral
    caution:  'oklch(0.835 0.130 92)',   // amber
    warn:     'oklch(0.740 0.165 52)',   // orange
    critical: 'oklch(0.660 0.205 26)',   // red
  },
  // value-text colors per level (calm reads as plain near-white)
  rampText: {
    calm:     'rgba(255,255,255,0.94)',
    caution:  'oklch(0.88 0.115 95)',
    warn:     'oklch(0.80 0.155 55)',
    critical: 'oklch(0.75 0.185 28)',
  },
  rampNames: ['calm', 'caution', 'warn', 'critical'],

  // Control accent (switches, sliders, selection) — calm blue
  accent: 'oklch(0.64 0.155 248)',

  // Desktop wallpaper stand-ins (so vibrancy has something to sample)
  wallpaper: 'radial-gradient(125% 120% at 18% 8%, #4a5fb0 0%, #34367e 32%, #211a44 62%, #100c20 100%)',
  wallpaperWarm: 'radial-gradient(130% 130% at 80% 12%, #c9764e 0%, #7c4a6b 34%, #2c2746 66%, #131022 100%)',
};

// level (0..3) -> bar/icon color
QS.levelColor = (lvl) => QS.ramp[QS.rampNames[Math.max(0, Math.min(3, lvl))]];
QS.levelText  = (lvl) => QS.rampText[QS.rampNames[Math.max(0, Math.min(3, lvl))]];

Object.assign(window, { QS });
