// icons.jsx — minimal SF-Symbol-style line icons for the HUD.
// Stroke = currentColor so a tile can tint its icon. 16×16 grid.

// Build a flat-topped cog outline path (reads as a gear far better than
// radial spokes at small sizes).
function gearPath(cx, cy, rOut, rIn, teeth) {
  const step = (Math.PI * 2) / teeth;
  const half = step / 2;
  const tw = half * 0.52; // half angular width of a tooth top
  let d = '';
  for (let i = 0; i < teeth; i++) {
    const a = i * step - Math.PI / 2;
    const pts = [
      [a - tw, rOut], [a + tw, rOut],            // tooth top
      [a + half - tw * 0.6, rIn], [a + step - tw - tw * 0.6, rIn], // valley
    ];
    pts.forEach(([ang, r], j) => {
      const x = (cx + Math.cos(ang) * r).toFixed(2);
      const y = (cy + Math.sin(ang) * r).toFixed(2);
      d += (d ? 'L' : 'M') + x + ' ' + y;
    });
  }
  return d + 'Z';
}
const GEAR_D = gearPath(8, 8, 6.6, 4.7, 7);

function Icon({ name, size = 16, stroke = 1.6, style }) {
  const p = { fill: 'none', stroke: 'currentColor', strokeWidth: stroke, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const paths = {
    cpu: (
      <g {...p}>
        <rect x="4.5" y="4.5" width="7" height="7" rx="1.2" />
        <rect x="6.7" y="6.7" width="2.6" height="2.6" rx="0.5" />
        <path d="M6.2 4.5V2.6M9.8 4.5V2.6M6.2 11.5v1.9M9.8 11.5v1.9M4.5 6.2H2.6M4.5 9.8H2.6M11.5 6.2h1.9M11.5 9.8h1.9" />
      </g>
    ),
    memory: (
      <g {...p}>
        <rect x="2.4" y="5" width="11.2" height="6" rx="1" />
        <path d="M5 11v1.6M8 11v1.6M11 11v1.6M5.4 7.2v1.6M8 7.2v1.6M10.6 7.2v1.6" />
      </g>
    ),
    disk: (
      <g {...p}>
        <rect x="2.6" y="2.6" width="10.8" height="10.8" rx="2.4" />
        <circle cx="8" cy="8" r="2.2" />
        <circle cx="8" cy="8" r="0.4" fill="currentColor" stroke="none" />
      </g>
    ),
    network: (
      <g {...p}>
        <path d="M5 9.5L5 3M5 3L2.8 5.4M5 3l2.2 2.4" />
        <path d="M11 6.5L11 13M11 13l2.2-2.4M11 13l-2.2-2.4" />
      </g>
    ),
    battery: (
      <g {...p}>
        <rect x="1.8" y="5" width="11" height="6" rx="1.6" />
        <path d="M14.4 7v2" />
        <rect x="3.1" y="6.3" width="6.4" height="3.4" rx="0.6" fill="currentColor" stroke="none" />
      </g>
    ),
    load: (
      <g {...p}>
        <path d="M2.6 11a5.4 5.4 0 0 1 10.8 0" />
        <path d="M8 11l2.6-3.1" />
        <circle cx="8" cy="11" r="0.9" fill="currentColor" stroke="none" />
      </g>
    ),
    uptime: (
      <g {...p}>
        <circle cx="8" cy="8.4" r="5.2" />
        <path d="M8 5.4v3l2 1.4" />
      </g>
    ),
    process: (
      <g {...p}>
        <rect x="2.4" y="3" width="11.2" height="10" rx="1.8" />
        <path d="M2.4 6h11.2" />
        <circle cx="4.5" cy="4.5" r="0.4" fill="currentColor" stroke="none" />
        <circle cx="6.1" cy="4.5" r="0.4" fill="currentColor" stroke="none" />
      </g>
    ),
    gear: (
      <path d={GEAR_D + ' M10.1 8 A2.1 2.1 0 1 0 5.9 8 A2.1 2.1 0 1 0 10.1 8 Z'}
        fill="currentColor" fillRule="evenodd" stroke="currentColor" strokeWidth="0.5" strokeLinejoin="round" />
    ),
    chevron: (<g {...p}><path d="M5.5 3.5L10 8l-4.5 4.5" /></g>),
    bolt: (<g {...p}><path d="M8.5 2L4 9h3.2l-.7 5L12 6.5H8.5L8.5 2z" fill="currentColor" stroke="none" /></g>),
    arrowUp: (<g {...p}><path d="M8 12.5V3.5M8 3.5L4.8 6.7M8 3.5l3.2 3.2" /></g>),
    arrowDown: (<g {...p}><path d="M8 3.5v9M8 12.5l3.2-3.2M8 12.5L4.8 9.3" /></g>),
  };
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" style={{ display: 'block', flex: '0 0 auto', ...style }} aria-hidden="true">
      {paths[name] || null}
    </svg>
  );
}

Object.assign(window, { Icon });
