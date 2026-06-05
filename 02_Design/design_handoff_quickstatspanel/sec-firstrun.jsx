// sec-firstrun.jsx — Prompt 6: one-time first-run hint card.

function FirstRunCard({ width = 320 }) {
  const [dismissed, setDismissed] = React.useState(false);
  const dismiss = () => { setDismissed(true); setTimeout(() => setDismissed(false), 1300); };
  return (
    <div style={{ position: 'relative', width, fontFamily: QS.font,
      background: 'rgba(36,36,40,0.93)', backdropFilter: 'blur(30px) saturate(1.6)', WebkitBackdropFilter: 'blur(30px) saturate(1.6)',
      border: '1px solid rgba(255,255,255,0.14)', borderRadius: 12,
      boxShadow: '0 18px 48px rgba(0,0,0,0.5), 0 2px 8px rgba(0,0,0,0.4)', padding: 16,
      opacity: dismissed ? 0 : 1, transform: dismissed ? 'translateY(-6px) scale(0.98)' : 'none',
      transition: 'opacity .35s, transform .35s' }}>
      {/* header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 11, marginBottom: 13 }}>
        <IconLiteral size={34} />
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 13.5, fontWeight: 600, color: QS.text.value }}>QuickStats is running</div>
          <div style={{ fontSize: 11.5, color: QS.text.label, marginTop: 1 }}>No Dock or menu-bar icon — it lives on a key.</div>
        </div>
      </div>
      {/* core gesture */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, flexWrap: 'wrap', marginBottom: 7 }}>
        <span style={{ fontSize: 13, color: QS.text.value }}>Press</span>
        <span style={{ display: 'flex', gap: 4 }}>
          <Keycap>⌃</Keycap><Keycap>⌥</Keycap><Keycap>⌘</Keycap><Keycap>Q</Keycap>
        </span>
        <span style={{ fontSize: 13, color: QS.text.value }}>anytime to summon your stats.</span>
      </div>
      <div style={{ fontSize: 12, color: QS.text.label, lineHeight: 1.4 }}>
        Press it again, <Keycap wide>esc</Keycap>, or click away to dismiss.
      </div>
      {/* divider + footer */}
      <div style={{ height: 1, background: 'rgba(255,255,255,0.09)', margin: '13px -16px 12px' }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 6, flex: 1, fontSize: 11.5, color: QS.text.dim, lineHeight: 1.35 }}>
          <span style={{ color: QS.text.label, display: 'flex' }}><Icon name="gear" size={13} /></span>
          Change the shortcut or anchor in Settings.
        </span>
        <button onClick={dismiss} style={{ flex: '0 0 auto', height: 30, padding: '0 16px', borderRadius: 7, cursor: 'pointer',
          border: 'none', background: QS.accent, color: '#fff', fontSize: 12.5, fontWeight: 600, font: 'inherit',
          fontFamily: QS.font, boxShadow: '0 1px 3px rgba(0,0,0,0.3)' }}>Got it</button>
      </div>
    </div>
  );
}

function SecFirstRun() {
  return (
    <DCSection id="firstrun" title="06 · First-run hint" subtitle="Teaches the single core gesture on first launch. Click “Got it” to dismiss (auto-resets here).">
      {/* standalone */}
      <DCArtboard id="fr-standalone" label="Standalone card" width={400} height={320}>
        <div style={{ width: '100%', height: '100%', background: POP_BG, display: 'flex', alignItems: 'center',
          justifyContent: 'center', padding: 28, boxSizing: 'border-box' }}>
          <FirstRunCard />
        </div>
      </DCArtboard>

      {/* positioned below the live strip over desktop */}
      <DCArtboard id="fr-positioned" label="In context — below the strip" width={780} height={470}
        style={{ background: QS.wallpaper }}>
        <div style={{ position: 'relative', width: '100%', height: '100%', overflow: 'hidden',
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 16 }}>
          <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(70% 60% at 50% 120%, rgba(0,0,0,0.35), transparent)' }} />
          <div style={{ position: 'relative', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16 }}>
            <FirstRunStripSnapshot />
            <FirstRunCard width={336} />
          </div>
        </div>
      </DCArtboard>
    </DCSection>
  );
}

// static strip snapshot for the in-context shot
function FirstRunStripSnapshot() {
  const stats = { cpu: { pct: 23 }, mem: { usedGB: 16.9, totalGB: 32 }, disk: { usedPct: 64 },
    net: { up: 2.4, down: 18.6 }, batt: { pct: 82 }, load: { one: 1.42, cores: 8 }, uptime: { str: '3d 4h' }, proc: { name: 'Xcode' } };
  return <HUDStrip stats={stats} levels={{ cpu: 0, mem: 0, disk: 0, load: 1, batt: 0 }}
    order={['cpu', 'mem', 'disk', 'net', 'batt', 'load', 'uptime', 'proc']} variant="labelAbove" showGear />;
}

Object.assign(window, { SecFirstRun, FirstRunCard });
