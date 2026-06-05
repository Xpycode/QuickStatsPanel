// app.jsx — composes the QuickStatsPanel design canvas.
function App() {
  const [active, setActive] = React.useState(null); // hero tile highlight

  return (
    <DesignCanvas>
      <SecHero
        active={active}
        onTile={(k) => setActive((a) => (a === k ? null : k))}
        onGear={() => setActive((a) => (a === 'gear' ? null : 'gear'))} />
      {window.SecPopovers && <SecPopovers />}
      {window.SecColor && <SecColor />}
      {window.SecSettings && <SecSettings />}
      {window.SecIcon && <SecIcon />}
      {window.SecFirstRun && <SecFirstRun />}
    </DesignCanvas>
  );
}
ReactDOM.createRoot(document.getElementById('root')).render(<App />);
