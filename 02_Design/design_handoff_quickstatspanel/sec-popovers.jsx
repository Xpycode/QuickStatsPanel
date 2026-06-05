// sec-popovers.jsx — Prompt 2: one tile, two states (resting + detail popover).

const POP_BG = 'radial-gradient(120% 110% at 50% 0%, #26262b 0%, #161619 100%)';

function PopoverCase({ resting, variant, popover, note }) {
  return (
    <div style={{ width: '100%', height: '100%', background: POP_BG, display: 'flex', flexDirection: 'column',
      alignItems: 'center', padding: '34px 26px 26px', boxSizing: 'border-box', gap: 0 }}>
      {/* (a) resting state */}
      <div style={{ position: 'relative' }}>
        <span style={{ position: 'absolute', top: -20, left: '50%', transform: 'translateX(-50%)',
          fontFamily: QS.mono, fontSize: 10, letterSpacing: '0.08em', color: QS.text.dim, whiteSpace: 'nowrap' }}>RESTING</span>
        <RestingTile tileProps={{ ...resting, active: true }} variant={variant} />
      </div>
      {/* connector */}
      <div style={{ width: 1, height: 22, background: 'linear-gradient(rgba(255,255,255,0.22), rgba(255,255,255,0.05))' }} />
      {/* (b) popover */}
      <div style={{ position: 'relative' }}>
        <span style={{ position: 'absolute', top: -19, right: '100%', marginRight: 12,
          fontFamily: QS.mono, fontSize: 10, letterSpacing: '0.08em', color: QS.text.dim, whiteSpace: 'nowrap' }}>ON CLICK</span>
        {popover}
      </div>
      {note && <div style={{ marginTop: 'auto', paddingTop: 18, fontFamily: QS.font, fontSize: 12, lineHeight: 1.45,
        color: 'rgba(255,255,255,0.5)', textAlign: 'center', maxWidth: 270, textWrap: 'pretty' }}>{note}</div>}
    </div>
  );
}

function SecPopovers() {
  const cases = [
    { id: 'pop-disk', label: 'Disk', height: 430,
      resting: { icon: 'disk', label: 'DISK', value: '64', unit: '%', level: 0, meter: 0.64, width: 64 },
      popover: <DiskPopover />,
      note: 'Resting shows used %. Popover breaks out Used / Free / Total and live Read / Write throughput.' },
    { id: 'pop-batt', label: 'Battery', height: 430,
      resting: { icon: 'battery', label: 'BATT', value: '82', unit: '%', level: 0, meter: 0.82, width: 64 },
      popover: <BattPopover />,
      note: 'State-aware battery glyph; popover adds charge state + time remaining. Tile is hidden entirely on desktop Macs.' },
    { id: 'pop-load', label: 'Load average', height: 430,
      resting: { icon: 'load', label: 'LOAD', value: '1.42', level: 1, meter: 1.42 / 8, width: 64 },
      popover: <LoadPopover />,
      note: 'Resting shows 1-minute load. Popover lists 1 / 5 / 15-min loads + active core count, normalized per core.' },
    { id: 'pop-cpu', label: 'CPU', height: 430,
      resting: { icon: 'cpu', label: 'CPU', value: '23', unit: '%', level: 0, meter: 0.23, width: 64 },
      popover: <CpuPopover />,
      note: 'The pattern generalizes: header value, a fill meter, then a tidy key-value breakdown.' },
  ];
  return (
    <DCSection id="popovers" title="02 · Tile + detail popover" subtitle="Resting tile (fixed-width value, no layout shift) → dark card with a pointer, on click.">
      {cases.map((c) => (
        <DCArtboard key={c.id} id={c.id} label={c.label} width={320} height={c.height}>
          <PopoverCase resting={c.resting} variant="labelAbove" popover={c.popover} note={c.note} />
        </DCArtboard>
      ))}
    </DCSection>
  );
}

Object.assign(window, { SecPopovers });
