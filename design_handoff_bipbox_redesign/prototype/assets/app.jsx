/* Bipbox — interactive prototype.
   Fixed 3-column shell (sidebar · center · inspector). Only the CONTENT of
   the center + inspector swaps on navigation; column widths never change. */

// ---------- icons ----------
const P = {
  search:'M11 4a7 7 0 105.2 11.7L21 20M11 4a7 7 0 00-7 7', spark:'M12 3l1.6 4.6L18 9l-4.4 1.4L12 15l-1.6-4.6L6 9l4.4-1.4L12 3z',
  grid:'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z', graph:'M12 9a2.5 2.5 0 100-5 2.5 2.5 0 000 5zM5 20a2.5 2.5 0 100-5 2.5 2.5 0 000 5zM19 20a2.5 2.5 0 100-5 2.5 2.5 0 000 5zM12 9v3m0 0l-5 4m5-4l5 4',
  clock:'M12 7v5l3 2M12 21a9 9 0 100-18 9 9 0 000 18z', tray:'M4 13l2.5 4h11L20 13M4 13V5h16v8M4 13h5l1 2h4l1-2h5',
  download:'M12 4v10m0 0l-4-4m4 4l4-4M5 19h14', desktop:'M4 5h16v11H4zM9 20h6M12 16v4', doc:'M7 3h7l4 4v14H7zM14 3v4h4',
  folder:'M4 7a2 2 0 012-2h4l2 2h6a2 2 0 012 2v7a2 2 0 01-2 2H6a2 2 0 01-2-2z',
  flow:'M6 5a2 2 0 100 4 2 2 0 000-4zM18 15a2 2 0 100 4 2 2 0 000-4zM6 19a2 2 0 100-4 2 2 0 000 4zM8 7h7a3 3 0 013 3v3M6 9v6',
  gear:'M12 9a3 3 0 100 6 3 3 0 000-6zM19 12a7 7 0 00-.1-1.3l2-1.6-2-3.4-2.4 1a7 7 0 00-2.3-1.3L13.8 2h-3.6l-.4 2.4a7 7 0 00-2.3 1.3l-2.4-1-2 3.4 2 1.6A7 7 0 005 12a7 7 0 00.1 1.3l-2 1.6 2 3.4 2.4-1a7 7 0 002.3 1.3l.4 2.4h3.6l.4-2.4a7 7 0 002.3-1.3l2.4 1 2-3.4-2-1.6A7 7 0 0019 12z',
  plus:'M12 5v14M5 12h14', open:'M14 4h6v6M20 4l-9 9M18 13v6a1 1 0 01-1 1H5a1 1 0 01-1-1V7a1 1 0 011-1h6',
  reveal:'M3 6a2 2 0 012-2h4l2 2h8a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2z', link:'M9 15l6-6M10 6l1-1a4 4 0 016 6l-1 1M14 18l-1 1a4 4 0 01-6-6l1-1',
  bookmark:'M7 4h10v16l-5-3.5L7 20z', person:'M12 12a4 4 0 100-8 4 4 0 000 8zM5 20a7 7 0 0114 0', project:'M3 7l9-4 9 4-9 4-9-4zM3 7v10l9 4 9-4V7M12 11v10',
  topic:'M7 7h10M7 12h10M7 17h6M4 4h16v16H4z', refresh:'M4 9a8 8 0 0113-3l3 2M20 15a8 8 0 01-13 3l-3-2M19 4v4h-4M5 20v-4h4',
  check:'M5 12l5 5L20 6', x:'M6 6l12 12M18 6L6 18', more:'M5 12h.01M12 12h.01M19 12h.01', back:'M15 6l-6 6 6 6', fwd:'M9 6l6 6-6 6',
  sort:'M7 4v16m0 0l-3-3m3 3l3-3M17 20V4m0 0l-3 3m3-3l3 3', filter:'M4 5h16l-6 8v5l-4 2v-7z', collection:'M5 7h14M6 11h12M8 15h8M9 19h6',
  sidebar:'M4 5h16v14H4zM9 5v14', layers:'M12 4l9 5-9 5-9-5 9-5zM3 14l9 5 9-5', pause:'M9 5v14M15 5v14', play:'M7 5l12 7-12 7z',
  undo:'M9 7L4 12l5 5M4 12h11a5 5 0 010 10h-3', sun:'M12 4V2M12 22v-2M5 5L3.5 3.5M20.5 20.5L19 19M4 12H2M22 12h-2M5 19l-1.5 1.5M20.5 3.5L19 5M12 8a4 4 0 100 8 4 4 0 000-8z',
  moon:'M20 14.5A8 8 0 119.5 4 6.5 6.5 0 0020 14.5z',
};
function Icon({ n, s = 17, sw = 1.7, fill = false }) {
  const d = P[n] || '';
  return (<svg width={s} height={s} viewBox="0 0 24 24" fill={fill ? 'currentColor' : 'none'} stroke={fill ? 'none' : 'currentColor'}
    strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">{d.split('M').filter(Boolean).map((g, i) => <path key={i} d={'M' + g} />)}</svg>);
}

// ---------- data ----------
const SRC = {
  downloads:{ name:'Downloads', color:'#0a84ff', ic:'download', path:'~/Downloads', stat:'218 items · watching for new arrivals', state:'Watching', pill:['good','Watching'] },
  desktop:{ name:'Desktop', color:'#8a5cf6', ic:'desktop', path:'~/Desktop', stat:'64 items · watching', state:'Watching', pill:['good','Watching'] },
  documents:{ name:'Documents', color:'#1f9d57', ic:'doc', path:'~/Documents', stat:'Indexing… 1,204 of 1,580 items', state:'Indexing', pill:['info','Indexing'], meter:76 },
  aurora:{ name:'Aurora', color:'#d98b1f', ic:'folder', path:'~/Projects/Aurora', stat:'Paused · last scanned 2 days ago', state:'Paused', pill:['ghost','Paused'] },
};
const CTXP = {
  q3close:{ t:'Q3 Earnings', c:'#0a84ff', ic:'project', kind:'project', pred:'belongs to' },
  maya:{ t:'Maya Chen', c:'#8a5cf6', ic:'person', kind:'person', pred:'mentions' },
  finance:{ t:'Finance', c:'#1f9d57', ic:'topic', kind:'topic', pred:'about' },
  aurora:{ t:'Aurora', c:'#d98b1f', ic:'project', kind:'project', pred:'belongs to' },
  design:{ t:'Design', c:'#1f9d57', ic:'topic', kind:'topic', pred:'about' },
};
const ITEMS = [
  { id:'q3', name:'Q3 Financial Report.pdf', path:'~/Downloads/Q3 Financial Report.pdf', src:'downloads', date:'Today, 9:14 AM', kind:'PDF',
    status:['warn','Needs decision'], pending:true, why:'Matches “Q3” and “financial”; arrived in a watched source today.',
    ctx:['q3close','maya','finance'], similar:'invoice', collection:'Q3 Close',
    plan:{ move:'~/Documents/Finance/Q3/', coll:'Q3 Close', link:'Maya Chen · Finance' } },
  { id:'screenshot', name:'screenshot 2025-03-14.png', path:'~/Desktop/screenshot 2025-03-14.png', src:'desktop', date:'Today, 8:02 AM', kind:'Image', img:true,
    status:['warn','Needs decision'], pending:true, why:'Ambiguous — could belong to two projects.', ctx:['aurora','design'], similar:'roadmap', collection:'Design Inspiration',
    plan:{ move:'~/Projects/Aurora/Shots/', coll:'Design Inspiration', link:'Aurora' } },
  { id:'untitled', name:'Untitled folder', path:'~/Downloads/Untitled folder', src:'downloads', date:'Yesterday', kind:'Folder', folder:true,
    status:['bad','Needs care'], pending:true, why:'Risky move — destination already has a folder with this name.', ctx:['q3close'], similar:'mockups', collection:'Q3 Close',
    plan:{ move:'~/Documents/Inbox/', coll:'—', link:'—' } },
  { id:'contract', name:'Maya Chen — Contract.pdf', path:'~/Documents/Clients/Maya Chen/Contract.pdf', src:'documents', date:'Mar 14', kind:'PDF',
    status:['good','Filed'], why:'Mentions “Maya Chen”; related to Project Q3 Close.', ctx:['maya','q3close','finance'], similar:'q3', collection:'Q3 Close' },
  { id:'brand', name:'Brand Guidelines 2025.pdf', path:'~/Desktop/Brand Guidelines 2025.pdf', src:'desktop', date:'Mar 11', kind:'PDF',
    status:['info','Indexed'], why:'Filename token “brand”; similar to 4 design files.', ctx:['design','aurora'], similar:'mockups', collection:'Design Inspiration' },
  { id:'mockups', name:'Aurora — Mockups', path:'~/Projects/Aurora/Mockups', src:'aurora', folder:true, date:'Mar 9', kind:'Folder',
    status:['good','Filed'], why:'Folder kept whole; belongs to Project Aurora.', ctx:['aurora','design'], similar:'roadmap', collection:'Design Inspiration' },
  { id:'invoice', name:'invoice-1042.pdf', path:'~/Downloads/invoice-1042.pdf', src:'downloads', date:'Mar 8', kind:'PDF',
    status:['info','Indexed'], why:'Similar to Q3 Financial Report; same source.', ctx:['finance','q3close'], similar:'q3', collection:'Invoices' },
  { id:'offsite', name:'team-offsite.heic', path:'~/Desktop/team-offsite.heic', src:'desktop', img:true, date:'Mar 6', kind:'Image',
    status:['info','Indexed'], why:'Captured 6 days ago from Desktop.', ctx:['design'], similar:'screenshot', collection:'Design Inspiration' },
  { id:'roadmap', name:'roadmap.sketch', path:'~/Projects/Aurora/roadmap.sketch', src:'aurora', img:true, date:'Mar 3', kind:'Sketch',
    status:['good','Filed'], why:'Belongs to Project Aurora; edited recently.', ctx:['aurora','design'], similar:'mockups', collection:'Design Inspiration' },
];
const BYID = Object.fromEntries(ITEMS.map((i) => [i.id, i]));
const COLLECTIONS = {
  colQ3:{ name:'Q3 Close', ic:'bookmark', items:['q3','contract','invoice','untitled'] },
  colDesign:{ name:'Design Inspiration', ic:'bookmark', items:['brand','mockups','roadmap','offsite','screenshot'] },
  colInvoices:{ name:'Invoices · smart', ic:'collection', items:['invoice','q3'] },
};
// semantic-similarity clusters (the Overview level). Files can belong to several,
// which is what creates overlap links between clusters.
const CLUSTERS = {
  finance:{ t:'Finance', c:'#0a84ff', items:['q3','invoice','contract','untitled'] },
  q3:{ t:'Q3 Earnings', c:'#d9772f', items:['q3','invoice','contract'] },
  clients:{ t:'Clients', c:'#8a5cf6', items:['contract','q3'] },
  design:{ t:'Design', c:'#1f9d57', items:['brand','mockups','roadmap','offsite','screenshot'] },
};
const COLByName = Object.fromEntries(Object.values(COLLECTIONS).map((c) => [c.name, c.items]));
function clusterOf(id) { return Object.keys(CLUSTERS).find((k) => CLUSTERS[k].items.includes(id)); }
const RULES = [
  { id:'r1', name:'Financial documents', enabled:true, cond:'name contains “invoice” or “financial”', outcome:'Move → ~/Documents/Finance, add to Q3 Close', review:true },
  { id:'r2', name:'Design assets stay whole', enabled:true, cond:'kind is Folder and source is Aurora', outcome:'Remember in place, tag “design”', review:false },
  { id:'r3', name:'Screenshots', enabled:false, cond:'name starts with “screenshot”', outcome:'Add to collection “Design Inspiration”', review:false },
];
const ACTIVITY = [
  { id:'a1', title:'Filed Maya Chen — Contract.pdf', kind:'Move', detail:'Moved to ~/Documents/Clients/Maya Chen/ by rule “Financial documents”.', when:'Mar 14, 2:31 PM', reversible:true, cls:'good' },
  { id:'a2', title:'Remembered 64 items from Desktop', kind:'Index', detail:'Initial scan of Desktop indexed 64 top-level items for search.', when:'Mar 11, 9:00 AM', reversible:false, cls:'info' },
  { id:'a3', title:'Added roadmap.sketch to Aurora', kind:'Relationship', detail:'Linked roadmap.sketch to Project Aurora.', when:'Mar 9, 4:12 PM', reversible:true, cls:'info' },
  { id:'a4', title:'Paused watching Aurora', kind:'Source', detail:'Watching paused for ~/Projects/Aurora.', when:'Mar 7, 10:20 AM', reversible:true, cls:'info' },
];

// ---------- sections config ----------
const NAV = {
  all:{ title:'All Items', sub:(n) => `${n} remembered · 3 need a decision`, type:'lib' },
  recents:{ title:'Recents', sub:() => 'Captured in the last 14 days', type:'lib' },
  inbox:{ title:'Inbox', sub:(n) => `${n} ${n === 1 ? 'thing needs' : 'things need'} your decision`, type:'inbox' },
  downloads:{ title:'Downloads', sub:() => SRC.downloads.stat, type:'src', src:'downloads' },
  desktop:{ title:'Desktop', sub:() => SRC.desktop.stat, type:'src', src:'desktop' },
  documents:{ title:'Documents', sub:() => SRC.documents.stat, type:'src', src:'documents' },
  aurora:{ title:'Aurora', sub:() => SRC.aurora.stat, type:'src', src:'aurora' },
  colQ3:{ title:'Q3 Close', sub:() => 'Manual collection · 4 items', type:'col', col:'colQ3' },
  colDesign:{ title:'Design Inspiration', sub:() => 'Manual collection · 5 items', type:'col', col:'colDesign' },
  colInvoices:{ title:'Invoices', sub:() => 'Smart collection · auto-updates', type:'col', col:'colInvoices' },
  rules:{ title:'Rules', sub:() => '3 routes · automation is optional', type:'rules' },
  activity:{ title:'Activity', sub:() => 'Every change, explained — with undo', type:'activity' },
};

// =====================================================================
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "appearance": "light",
  "accent": "#0a84ff",
  "density": "spacious",
  "defaultView": "connections"
}/*EDITMODE-END*/;

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [sec, setSec] = React.useState('all');
  const [view, setView] = React.useState(t.defaultView); // default C
  const [sel, setSel] = React.useState('overview');
  const [query, setQuery] = React.useState('');
  const results = React.useMemo(() => searchFiles(query), [query]);
  const onQuery = (v) => { setQuery(v); if (v.trim()) { const r = searchFiles(v); setSel(r[0] ? r[0].it.id : null); } else { setSel('overview'); } };
  const [resolved, setResolved] = React.useState({});
  const [toast, setToast] = React.useState(null);
  const toastT = React.useRef(0);
  const theme = t.appearance;
  const setTheme = (v) => setTweak('appearance', v);

  React.useEffect(() => { document.documentElement.dataset.theme = t.appearance; }, [t.appearance]);
  React.useEffect(() => { document.documentElement.style.setProperty('--accent', t.accent); }, [t.accent]);
  const flash = (msg) => { setToast(msg); clearTimeout(toastT.current); toastT.current = setTimeout(() => setToast(null), 2600); };

  const conf = NAV[sec];
  const isPending = (it) => it.pending && !resolved[it.id];

  // items for the active section
  const items = React.useMemo(() => {
    if (conf.type === 'inbox') return ITEMS.filter(isPending);
    if (conf.type === 'src') return ITEMS.filter((i) => i.src === conf.src);
    if (conf.type === 'col') return COLLECTIONS[conf.col].items.map((id) => BYID[id]);
    if (conf.type === 'recents') return ITEMS.slice(0, 6);
    return ITEMS;
  }, [sec, resolved]);

  const pendingCount = ITEMS.filter(isPending).length;

  // navigate — Overview/scoped graph by default; pick a sensible inspector subject
  const go = (id) => {
    const c = NAV[id]; setSec(id);
    if (c.type === 'rules') setSel(RULES[0].id);
    else if (c.type === 'activity') setSel(ACTIVITY[0].id);
    else if (c.type === 'inbox') { const p = ITEMS.filter(isPending); setSel(p[0] ? p[0].id : null); }
    else if (c.type === 'src') setSel(view === 'gallery' ? ((ITEMS.find((i) => i.src === c.src) || {}).id || null) : 'src:' + c.src);
    else if (c.type === 'col') setSel(view === 'gallery' ? COLLECTIONS[c.col].items[0] : 'col:' + COLLECTIONS[c.col].name);
    else { // all / recents — no scope → Overview map (or first card in gallery)
      const first = (c.type === 'recents' ? ITEMS.slice(0, 6) : ITEMS)[0];
      setSel(view === 'gallery' ? (first && first.id) : 'overview');
    }
  };

  // keep gallery coherent: it needs a real item selected
  const setViewSafe = (v) => { setView(v); if (v === 'gallery' && !BYID[sel]) { const f = items[0]; setSel(f ? f.id : null); } };

  const decide = (it, kind) => {
    setResolved((r) => ({ ...r, [it.id]: kind }));
    if (kind === 'approve') flash(`Filed to ${it.plan ? it.plan.move : 'destination'} · Undo`);
    else if (kind === 'keep') flash('Kept in place — still findable');
    else flash('Rejected — left where it was');
    if (conf.type === 'inbox') {
      const rest = ITEMS.filter((x) => x.pending && !{ ...resolved, [it.id]: kind }[x.id]);
      setSel(rest[0] ? rest[0].id : null);
    }
  };

  const showViewToggle = conf.type === 'lib' || conf.type === 'src' || conf.type === 'col' || !!query.trim();
  const selItem = sel && BYID[sel] ? BYID[sel] : null;

  return (
    <div className="bb-app" data-density={t.density}>
      <div className="bb-win">
        <SideBar sec={sec} go={go} pending={pendingCount} theme={theme} setTheme={setTheme} />
        <div className="bb-main">
          <Toolbar view={view} setView={setViewSafe} showToggle={showViewToggle} theme={theme} setTheme={setTheme} query={query} setQuery={onQuery} />
          <div className="bb-body">
            <Center conf={conf} items={items} view={view} sel={sel} setSel={setSel}
              isPending={isPending} resolved={resolved} flash={flash} query={query} results={results} />
            <Inspector conf={conf} selItem={selItem} sel={sel} isPending={isPending} decide={decide}
              resolved={resolved} flash={flash} setSel={setSel} />
          </div>
        </div>
        {toast && <div className="bb-toast"><Icon n="check" s={15} /> {toast}</div>}
      </div>
      <TweaksPanel>
        <TweakSection label="Appearance" />
        <TweakRadio label="Theme" value={t.appearance} options={['light', 'dark']} onChange={(v) => setTweak('appearance', v)} />
        <TweakColor label="Accent" value={t.accent} options={['#0a84ff', '#1f9d57', '#8a5cf6', '#d9772f']} onChange={(v) => setTweak('accent', v)} />
        <TweakSection label="Layout" />
        <TweakRadio label="Density" value={t.density} options={['spacious', 'regular']} onChange={(v) => setTweak('density', v)} />
        <TweakRadio label="Default view" value={t.defaultView} options={['connections', 'gallery']} onChange={(v) => { setTweak('defaultView', v); setView(v); }} />
      </TweaksPanel>
    </div>
  );
}

// ---------- sidebar ----------
function SideBar({ sec, go, pending, theme, setTheme }) {
  const Nav = ({ id, ic, ttl, badge, dot }) => (
    <div className={'bb-nav' + (sec === id ? ' sel' : '')} onClick={() => go(id)}>
      <span className="ic"><Icon n={ic} s={16} /></span><span className="ttl">{ttl}</span>
      {badge ? <span className="bb-badge">{badge}</span> : null}
      {dot ? <span className="dot" style={{ background: dot }} /> : null}
    </div>
  );
  return (
    <div className="bb-sidebar">
      <div className="bb-sb-top">
        <div className="bb-traffic"><i className="r" /><i className="y" /><i className="g" /></div>
        <div className="bb-brand"><div className="bb-brand-mark">B</div><div className="bb-brand-name">Bipbox</div></div>
      </div>
      <div className="bb-sb-scroll">
        <div className="bb-group">
          <Nav id="all" ic="layers" ttl="All Items" />
          <Nav id="recents" ic="clock" ttl="Recents" />
          <Nav id="inbox" ic="tray" ttl="Inbox" badge={pending || null} />
        </div>
        <div className="bb-group">
          <div className="bb-group-h"><span>Watched Folders</span><span className="add"><Icon n="plus" s={13} /></span></div>
          {Object.entries(SRC).map(([k, v]) => <Nav key={k} id={k} ic={v.ic} ttl={v.name} dot={v.color} />)}
        </div>
        <div className="bb-group">
          <div className="bb-group-h"><span>Collections</span><span className="add"><Icon n="plus" s={13} /></span></div>
          <Nav id="colQ3" ic="bookmark" ttl="Q3 Close" />
          <Nav id="colDesign" ic="bookmark" ttl="Design Inspiration" />
          <Nav id="colInvoices" ic="collection" ttl="Invoices · smart" />
        </div>
        <div className="bb-group">
          <div className="bb-group-h"><span>Organize</span></div>
          <Nav id="rules" ic="flow" ttl="Rules" />
          <Nav id="activity" ic="clock" ttl="Activity" />
        </div>
      </div>
      <div className="bb-sb-foot">
        <span className="bb-ai-pip" /><span className="bb-foot-txt">Assistant ready · local</span>
        <span className="bb-foot-gear"><Icon n="gear" s={16} /></span>
      </div>
    </div>
  );
}

// ---------- toolbar ----------
function Toolbar({ view, setView, showToggle, theme, setTheme, query, setQuery }) {
  const ref = React.useRef(null);
  return (
    <div className="bb-toolbar">
      <div className="bb-tbtn"><Icon n="sidebar" s={17} /></div>
      <div className="bb-tbtn"><Icon n="back" s={17} /></div>
      <div className="bb-tbtn"><Icon n="fwd" s={17} /></div>
      <div className={'bb-search' + (query ? ' active' : '')} onClick={() => ref.current && ref.current.focus()}>
        <span className="spark"><Icon n={query ? 'search' : 'spark'} s={15} fill={!query} /></span>
        <input ref={ref} className="bb-search-input" value={query} placeholder="Ask or search your files…"
          onChange={(e) => setQuery(e.target.value)} />
        {query
          ? <span className="bb-search-x" onClick={(e) => { e.stopPropagation(); setQuery(''); }}><Icon n="x" s={13} /></span>
          : <span className="kbd">⌘K</span>}
      </div>
      <div style={{ flex: 1 }} />
      {showToggle && (
        <div className="bb-viewseg">
          <button className={view === 'gallery' ? 'on' : ''} onClick={() => setView('gallery')}><Icon n={query ? 'list' : 'grid'} s={14} /> {query ? 'Results' : 'Gallery'}</button>
          <button className={view === 'connections' ? 'on' : ''} onClick={() => setView('connections')}><Icon n="graph" s={14} /> {query ? 'Map' : 'Connections'}</button>
        </div>
      )}
      <div className="bb-tbtn" onClick={() => setTheme(theme === 'light' ? 'dark' : 'light')} title="Toggle appearance">
        <Icon n={theme === 'light' ? 'moon' : 'sun'} s={17} />
      </div>
    </div>
  );
}

// ---------- center ----------
function Center({ conf, items, view, sel, setSel, isPending, resolved, flash, query, results }) {
  const searching = !!query.trim();
  let body, title, sub, key;

  if (searching) {
    title = 'Search';
    sub = `${results.length} ${results.length === 1 ? 'match' : 'matches'} for “${query.trim()}”`;
    body = view === 'connections'
      ? <SearchGraph results={results} q={query.trim()} setSel={setSel} />
      : <SearchResults results={results} q={query.trim()} sel={sel} setSel={setSel} />;
    key = 'search-' + view + '-' + query;
  } else {
    if (conf.type === 'rules') body = <RulesCenter sel={sel} setSel={setSel} flash={flash} />;
    else if (conf.type === 'activity') body = <ActivityCenter sel={sel} setSel={setSel} />;
    else if (conf.type === 'inbox') body = <InboxList items={items} sel={sel} setSel={setSel} />;
    else if (view === 'connections') body = sel === 'overview' ? <OverviewGraph setSel={setSel} /> : <Connections centerId={sel} setSel={setSel} />;
    else body = <Gallery items={items} sel={sel} setSel={setSel} resolved={resolved} />;
    const countN = conf.type === 'inbox' ? items.length : (conf.type === 'src' || conf.type === 'col') ? items.length : 428;
    title = conf.title;
    sub = conf.sub(countN);
    key = conf.type === 'rules' || conf.type === 'activity' ? conf.title
      : conf.type === 'inbox' ? 'inbox'
      : view === 'connections' ? 'cx-' + (sel || '') : 'gal-' + conf.title;
  }
  const isLib = conf.type === 'lib' || conf.type === 'col' || conf.type === 'src';

  return (
    <div className="bb-results">
      <div className="bb-res-head">
        <div style={{ display: 'flex', alignItems: 'flex-start' }}>
          <div style={{ flex: 1 }}>
            <div className="bb-h1">{title}</div>
            <div className="bb-h1-sub">{sub}</div>
          </div>
          {!searching && conf.type === 'src' && (
            <div className="bb-acts">
              <span className={'bb-pill ' + SRC[conf.src].pill[0]}>{SRC[conf.src].pill[1]}</span>
              <div className="bb-iconbtn" title="Rescan" onClick={() => flash('Rescanning ' + SRC[conf.src].name + '…')}><Icon n="refresh" s={15} /></div>
              <div className="bb-iconbtn" title="Pause / resume" onClick={() => flash(SRC[conf.src].state === 'Paused' ? 'Resumed watching' : 'Paused watching')}><Icon n={SRC[conf.src].state === 'Paused' ? 'play' : 'pause'} s={15} /></div>
            </div>
          )}
        </div>
        {!searching && isLib && view === 'gallery' && (
          <div className="bb-filters">
            <span className="bb-chip on">All</span><span className="bb-chip">Files</span>
            <span className="bb-chip">Folders</span><span className="bb-chip">Images</span>
            <span style={{ flex: 1 }} /><span className="bb-chip"><Icon n="filter" s={13} /> Filter</span>
          </div>
        )}
      </div>
      <div className="bb-swap" key={key} style={{ flex: 1, display: 'flex', flexDirection: 'column', minHeight: 0 }}>{body}</div>
    </div>
  );
}

// ---------- search ----------
function searchFiles(query) {
  const q = (query || '').trim().toLowerCase();
  if (!q) return [];
  const out = [];
  ITEMS.forEach((it) => {
    const name = it.name.toLowerCase(), path = it.path.toLowerCase();
    let score = 0; const why = [];
    if (name.startsWith(q)) { score += 100; why.push('name'); }
    else if (name.includes(q)) { score += 70; why.push('name'); }
    if (path.includes(q) && !name.includes(q)) { score += 30; why.push('path'); }
    if (SRC[it.src].name.toLowerCase().includes(q)) { score += 22; why.push('source'); }
    (it.ctx || []).forEach((cid) => { const c = CTXP[cid]; if (c && c.t.toLowerCase().includes(q)) { score += 26; why.push(c.kind); } });
    const ck = clusterOf(it.id); if (ck && CLUSTERS[ck].t.toLowerCase().includes(q)) { score += 16; }
    if (it.kind.toLowerCase().includes(q)) { score += 12; why.push('type'); }
    if (score > 0) out.push({ it, score, why: [...new Set(why)] });
  });
  return out.sort((a, b) => b.score - a.score);
}
function hl(text, q) {
  if (!q) return text;
  const i = text.toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return text;
  return <>{text.slice(0, i)}<mark className="bb-hl">{text.slice(i, i + q.length)}</mark>{text.slice(i + q.length)}</>;
}
function SearchResults({ results, q, sel, setSel }) {
  if (!results.length) return (
    <div className="bb-insp-empty" style={{ flex: 1 }}><div className="ring"><Icon n="search" s={22} /></div>
      <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--ink-2)' }}>No matches</div>
      <div style={{ fontSize: 12.5 }}>Try a name, type, person, or folder.</div></div>
  );
  const strong = results.filter((r) => r.score >= 70), rest = results.filter((r) => r.score < 70);
  const Row = ({ r }) => {
    const it = r.it; const ck = clusterOf(it.id);
    return (
      <div className={'bb-row' + (it.id === sel ? ' sel' : '')} onClick={() => setSel(it.id)}>
        <div className={'bb-ficon' + (it.folder ? '' : ' doc')}><Icon n={it.folder ? 'folder' : (it.img ? 'desktop' : 'doc')} s={19} /></div>
        <div className="bb-rmain">
          <div className="bb-rname">{hl(it.name, q)}</div>
          <div className="bb-rpath">{it.path}</div>
          <div className="bb-rwhy"><span className="spark"><Icon n="spark" s={12} fill /></span>matched in {r.why.join(' · ')}{ck ? ' · ' + CLUSTERS[ck].t + ' group' : ''}</div>
        </div>
        <div className="bb-rmeta">
          <span className="bb-rdate">{it.date}</span>
          <span className="bb-src-chip"><span className="dot" style={{ background: SRC[it.src].color }} />{SRC[it.src].name}</span>
        </div>
      </div>
    );
  };
  return (
    <div className="bb-list">
      {strong.length > 0 && <div className="bb-list-group">Best matches</div>}
      {strong.map((r) => <Row key={r.it.id} r={r} />)}
      {rest.length > 0 && <div className="bb-list-group">Also related</div>}
      {rest.map((r) => <Row key={r.it.id} r={r} />)}
    </div>
  );
}
function SearchGraph({ results, q, setSel }) {
  const [hov, setHov] = React.useState(null);
  const files = results.slice(0, 10);
  const n = files.length || 1, rx = 36, ry = 34;
  const pos = files.map((r, i) => {
    const a = (-Math.PI / 2) + (i * 2 * Math.PI / n);
    const ck = clusterOf(r.it.id); const c = ck ? CLUSTERS[ck].c : '#8a8a92';
    return { r, c, cl: ck ? CLUSTERS[ck].t : 'ungrouped', x: 50 + rx * Math.cos(a), y: 50 + ry * Math.sin(a) };
  });
  const dim = (i) => hov != null && hov !== i;
  if (!files.length) return (
    <div className="bb-graph"><div className="bb-crumbs"><span className="crumb cur">Results for “{q}”</span></div>
      <div className="bb-insp-empty" style={{ position: 'absolute', inset: 0 }}><div className="ring"><Icon n="search" s={22} /></div><div style={{ fontSize: 13.5, color: 'var(--ink-2)', fontWeight: 600 }}>No matches</div></div></div>
  );
  return (
    <div className="bb-graph">
      <div className="bb-crumbs"><span className="crumb cur">Results for “{q}” · {results.length}</span></div>
      <svg viewBox="0 0 100 100" preserveAspectRatio="none">
        {pos.map((p, i) => <line key={i} x1="50" y1="50" x2={p.x} y2={p.y} stroke={hov === i ? 'var(--accent)' : 'var(--edge)'} strokeWidth="0.16" style={{ opacity: dim(i) ? 0.16 : 1, transition: 'opacity .15s' }} />)}
      </svg>
      {pos.map((p, i) => <span key={'e' + i} className="bb-edge-label" style={{ left: (50 + p.x) / 2 + '%', top: (50 + p.y) / 2 + '%', opacity: hov == null ? 0.9 : (hov === i ? 1 : 0.14), color: hov === i ? 'var(--accent)' : 'var(--ink-3)' }}>{p.cl}</span>)}
      <div className="bb-node center ctx" style={{ left: '50%', top: '50%' }}>
        <span className="cic" style={{ background: 'var(--info-bg)', color: 'var(--accent)' }}><Icon n="search" s={20} /></span>
        <div><div className="cnm">“{q}”</div><div className="csub">{results.length} matches</div></div>
      </div>
      {pos.map((p, i) => {
        const it = p.r.it;
        return (
          <div key={it.id} className="bb-node bb-node-anim" style={{ left: p.x + '%', top: p.y + '%', opacity: dim(i) ? 0.4 : 1, transition: 'opacity .15s' }}
            onMouseEnter={() => setHov(i)} onMouseLeave={() => setHov(null)} onClick={() => setSel(it.id)}>
            <span className="ic" style={{ background: p.c + '22', color: p.c }}><Icon n={it.folder ? 'folder' : (it.img ? 'desktop' : 'doc')} s={15} /></span>
            <div><div className="t" style={{ maxWidth: 150, overflow: 'hidden', textOverflow: 'ellipsis' }}>{it.name}</div><div className="s">{p.cl} group</div></div>
          </div>
        );
      })}
    </div>
  );
}

// ---------- gallery (B) ----------
function Gallery({ items, sel, setSel, resolved }) {
  return (
    <div className="bb-gallery">
      {items.map((it) => {
        const st = pillFor(it, resolved);
        return (
          <div key={it.id} className={'bb-card' + (it.id === sel ? ' sel' : '')} onClick={() => setSel(it.id)}>
            <div className="bb-card-thumb">
              <Icon n={it.folder ? 'folder' : (it.img ? 'desktop' : 'doc')} s={34} />
              <span className="bb-card-pill"><span className={'bb-pill ' + st[0]}>{st[1]}</span></span>
            </div>
            <div className="bb-card-b">
              <div className="bb-card-name">{it.name}</div>
              <div className="bb-card-meta">
                <span className="bb-src-chip"><span className="dot" style={{ background: SRC[it.src].color }} />{SRC[it.src].name}</span>
                <span style={{ flex: 1 }} /><span className="bb-rdate">{it.date}</span>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ---------- connections (C) ----------
// ---------- graph model ----------
function nodeMeta(id) {
  if (id && id.startsWith('ctx:')) { const c = CTXP[id.slice(4)]; return c ? { type: 'context', ic: c.ic, c: c.c, t: c.t, kind: c.kind } : null; }
  if (id && id.startsWith('src:')) { const s = SRC[id.slice(4)]; return s ? { type: 'source', ic: s.ic, c: s.color, t: s.name, kind: 'source' } : null; }
  if (id && id.startsWith('col:')) { const nm = id.slice(4); return { type: 'collection', ic: 'bookmark', c: '#d98b1f', t: nm, kind: 'collection' }; }
  if (id && id.startsWith('cluster:')) { const c = CLUSTERS[id.slice(8)]; return c ? { type: 'cluster', ic: 'layers', c: c.c, t: c.t, kind: 'similarity group' } : null; }
  const it = BYID[id]; if (!it) return null;
  return { type: 'item', ic: it.folder ? 'folder' : (it.img ? 'desktop' : 'doc'), c: '#8a8a92', t: it.name, kind: it.kind, item: it };
}
function neighbors(id) {
  const out = [];
  if (BYID[id]) {
    const it = BYID[id];
    out.push({ id: 'src:' + it.src, pred: 'came from', strength: 0.55 });
    (it.ctx || []).forEach((cid) => { if (CTXP[cid]) out.push({ id: 'ctx:' + cid, pred: CTXP[cid].pred, strength: 0.9 }); });
    if (it.similar && BYID[it.similar]) out.push({ id: it.similar, pred: 'similar to', strength: 0.45 });
    if (it.collection) out.push({ id: 'col:' + it.collection, pred: 'in collection', strength: 0.6 });
  } else if (id.startsWith('ctx:')) {
    const cid = id.slice(4);
    ITEMS.forEach((x) => { if ((x.ctx || []).includes(cid)) out.push({ id: x.id, pred: CTXP[cid].pred, strength: 0.85 }); });
  } else if (id.startsWith('src:')) {
    const k = id.slice(4);
    ITEMS.forEach((x) => { if (x.src === k) out.push({ id: x.id, pred: 'captured here', strength: 0.55 }); });
  } else if (id.startsWith('col:')) {
    const nm = id.slice(4);
    const ids = COLByName[nm] || ITEMS.filter((x) => x.collection === nm).map((x) => x.id);
    ids.forEach((iid) => { if (BYID[iid]) out.push({ id: iid, pred: 'in collection', strength: 0.6 }); });
  } else if (id.startsWith('cluster:')) {
    const c = CLUSTERS[id.slice(8)];
    (c ? c.items : []).forEach((iid) => { if (BYID[iid]) out.push({ id: iid, pred: 'similar group', strength: 0.7 }); });
  }
  const seen = {};
  return out.filter((o) => { if (seen[o.id] || !nodeMeta(o.id)) return false; seen[o.id] = 1; return true; });
}
function itemCount(id) { return neighbors(id).filter((o) => BYID[o.id]).length; }

// breadcrumb: Overview ▸ Cluster ▸ File — every crumb clickable
function Crumbs({ id, setSel }) {
  const parts = [{ id: 'overview', t: 'Overview' }];
  if (id && id !== 'overview') {
    if (id.startsWith('cluster:')) { const c = CLUSTERS[id.slice(8)]; if (c) parts.push({ id, t: c.t }); }
    else if (BYID[id]) { const ck = clusterOf(id); if (ck) parts.push({ id: 'cluster:' + ck, t: CLUSTERS[ck].t }); parts.push({ id, t: BYID[id].name }); }
    else { const m = nodeMeta(id); parts.push({ id, t: m ? m.t : id }); }
  }
  return (
    <div className="bb-crumbs">
      {parts.map((p, i) => (
        <React.Fragment key={p.id}>
          {i > 0 && <span className="sep">›</span>}
          {i < parts.length - 1
            ? <button className="crumb" onClick={() => setSel(p.id)}>{p.t}</button>
            : <span className="crumb cur">{p.t}</span>}
        </React.Fragment>
      ))}
    </div>
  );
}

// OVERVIEW level — clusters by similarity, sized by file count, linked by overlap.
function OverviewGraph({ setSel }) {
  const [hov, setHov] = React.useState(null);
  const keys = Object.keys(CLUSTERS);
  const n = keys.length, rx = 31, ry = 30;
  const pos = keys.map((k, i) => { const a = (-Math.PI / 2) + (i * 2 * Math.PI / n); const cl = CLUSTERS[k]; return { k, cl, cnt: cl.items.length, x: 50 + rx * Math.cos(a), y: 50 + ry * Math.sin(a) }; });
  const links = [];
  for (let i = 0; i < pos.length; i++) for (let j = i + 1; j < pos.length; j++) {
    const shared = pos[i].cl.items.filter((x) => pos[j].cl.items.includes(x)).length;
    if (shared > 0) links.push({ a: i, b: j, shared });
  }
  const linked = (i) => links.some((l) => (l.a === hov && l.b === i) || (l.b === hov && l.a === i));
  const dim = (i) => hov != null && hov !== i && !linked(i);
  return (
    <div className="bb-graph">
      <Crumbs id="overview" setSel={setSel} />
      <svg viewBox="0 0 100 100" preserveAspectRatio="none">
        {links.map((l, li) => { const A = pos[l.a], B = pos[l.b]; const on = hov === l.a || hov === l.b;
          return <line key={li} x1={A.x} y1={A.y} x2={B.x} y2={B.y} stroke={on ? 'var(--accent)' : 'var(--edge)'} strokeWidth={(0.14 + l.shared * 0.13).toFixed(2)} style={{ opacity: hov != null && !on ? 0.1 : 0.85, transition: 'opacity .15s' }} />; })}
      </svg>
      {links.filter((l) => hov === l.a || hov === l.b).map((l, li) => { const A = pos[l.a], B = pos[l.b];
        return <span key={'ll' + li} className="bb-edge-label" style={{ left: (A.x + B.x) / 2 + '%', top: (A.y + B.y) / 2 + '%', color: 'var(--accent)', fontWeight: 600 }}>{l.shared} shared files</span>; })}
      {pos.map((p, i) => { const sz = 50 + p.cnt * 8;
        return (
          <div key={p.k} className="bb-node bb-cluster bb-node-anim" style={{ left: p.x + '%', top: p.y + '%', opacity: dim(i) ? 0.32 : 1, transition: 'opacity .15s' }}
            onMouseEnter={() => setHov(i)} onMouseLeave={() => setHov(null)} onClick={() => setSel('cluster:' + p.k)}>
            <span className="cl-orb" style={{ width: sz, height: sz, background: p.cl.c + '20', color: p.cl.c, borderColor: p.cl.c + '66' }}><Icon n="layers" s={Math.round(sz * 0.34)} /></span>
            <div className="cl-meta"><div className="cl-t">{p.cl.t}</div><div className="cl-c">{p.cnt} files</div></div>
          </div>
        ); })}
    </div>
  );
}

// inspector for the Overview level
function OverviewInspector({ setSel }) {
  const keys = Object.keys(CLUSTERS);
  return (
    <div className="bb-inspector">
      <div className="bb-insp-head"><div className="grow" /><div className="bb-iconbtn"><Icon n="more" s={16} /></div></div>
      <div className="bb-insp-scroll bb-swap" key="ov">
        <div className="bb-sec">
          <div className="bb-sec-h">Overview</div>
          <div className="bb-insp-name" style={{ fontSize: 16 }}>Your library, by similarity</div>
          <div className="bb-insp-sub" style={{ marginTop: 5, lineHeight: 1.5 }}>{ITEMS.length} files grouped into {keys.length} clusters. Pick a cluster to zoom in, then a file — you never see every file at once.</div>
        </div>
        <div className="bb-sec"><div className="bb-why"><div className="lead"><Icon n="graph" s={13} /> A map, not a hairball</div>At scale Bipbox groups files by what they’re about. Searching or choosing a folder/collection zooms the map straight to that neighborhood.</div></div>
        <div className="bb-sec">
          <div className="bb-sec-h">Clusters</div>
          <div className="bb-related">
            {keys.map((k) => { const cl = CLUSTERS[k]; return (
              <div key={k} className="bb-rel" onClick={() => setSel('cluster:' + k)}>
                <span className="ic" style={{ background: cl.c + '22', color: cl.c }}><Icon n="layers" s={15} /></span>
                <div style={{ minWidth: 0 }}><div className="t">{cl.t}</div><div className="r">{cl.items.length} files</div></div>
              </div>
            ); })}
          </div>
        </div>
      </div>
    </div>
  );
}

function CenterNode({ meta }) {
  if (meta.type === 'item') {
    const it = meta.item;
    return (
      <div className="bb-node center" style={{ left: '50%', top: '50%' }}>
        <div className="core"><div className="th"><Icon n={it.folder ? 'folder' : (it.img ? 'desktop' : 'doc')} s={28} /></div><div className="nm">{it.name}</div></div>
      </div>
    );
  }
  return (
    <div className="bb-node center ctx" style={{ left: '50%', top: '50%' }}>
      <span className="cic" style={{ background: meta.c + '22', color: meta.c }}><Icon n={meta.ic} s={22} /></span>
      <div><div className="cnm">{meta.t}</div><div className="csub">{meta.kind}</div></div>
    </div>
  );
}

// ---------- connections (C) — interactive memory graph ----------
function Connections({ centerId, setSel }) {
  const [hov, setHov] = React.useState(null);
  const [hidden, setHidden] = React.useState({});
  const cid = nodeMeta(centerId) ? centerId : 'overview';
  const cm = nodeMeta(cid);
  if (!cm) return <div className="bb-graph" />;
  const all = neighbors(cid).map((o) => ({ ...o, m: nodeMeta(o.id) }));
  const catOf = (m) => (m.type === 'context' ? m.kind : m.type);
  const CATLBL = { source: 'Sources', collection: 'Collections', cluster: 'Groups', project: 'Projects', person: 'People', topic: 'Topics', item: 'Files' };
  const cats = [...new Set(all.map((o) => catOf(o.m)))];
  const visible = all.filter((o) => !hidden[catOf(o.m)]);
  const more = Math.max(0, visible.length - 8);
  const shown = visible.slice(0, 8);
  const n = shown.length || 1, rx = 36, ry = 35;
  const pos = shown.map((o, i) => {
    const a = (-Math.PI / 2) + (i * 2 * Math.PI / n);
    return { ...o, cnt: BYID[o.id] ? 0 : itemCount(o.id), x: 50 + rx * Math.cos(a), y: 50 + ry * Math.sin(a) };
  });
  const dim = (i) => hov != null && hov !== i;
  return (
    <div className="bb-graph">
      <Crumbs id={cid} setSel={setSel} />
      {cats.length >= 3 && (
        <div className="bb-gfilter">
          {cats.map((c) => (
            <button key={c} className={'bb-gchip' + (hidden[c] ? ' off' : '')} onClick={() => setHidden((h) => ({ ...h, [c]: !h[c] }))}>{CATLBL[c] || c}</button>
          ))}
        </div>
      )}
      <svg viewBox="0 0 100 100" preserveAspectRatio="none">
        {pos.map((p, i) => (
          <line key={p.id} x1="50" y1="50" x2={p.x} y2={p.y}
            stroke={hov === i ? 'var(--accent)' : 'var(--edge)'} strokeWidth={(0.1 + p.strength * 0.22).toFixed(2)}
            style={{ opacity: dim(i) ? 0.16 : 1, transition: 'opacity .15s' }} />
        ))}
      </svg>
      {pos.map((p, i) => (
        <span key={'e' + p.id} className="bb-edge-label"
          style={{ left: (50 + p.x) / 2 + '%', top: (50 + p.y) / 2 + '%', opacity: hov == null ? 0.92 : (hov === i ? 1 : 0.14), fontWeight: hov === i ? 600 : 400, color: hov === i ? 'var(--accent)' : 'var(--ink-3)' }}>{p.pred}</span>
      ))}
      <CenterNode meta={cm} />
      {pos.map((p, i) => (
        <div key={p.id} className="bb-node bb-node-anim" style={{ left: p.x + '%', top: p.y + '%', opacity: dim(i) ? 0.4 : 1, transition: 'opacity .15s' }}
          onMouseEnter={() => setHov(i)} onMouseLeave={() => setHov(null)} onClick={() => setSel(p.id)}>
          <span className="ic" style={{ background: p.m.c + '22', color: p.m.c }}><Icon n={p.m.ic} s={15} /></span>
          <div>
            <div className="t" style={{ maxWidth: 146, overflow: 'hidden', textOverflow: 'ellipsis' }}>{p.m.t}</div>
            <div className="s">{p.cnt > 1 ? p.m.kind + ' · ' + p.cnt + ' files' : (BYID[p.id] ? 'file' : p.m.kind)}</div>
          </div>
          {p.cnt > 1 && <span className="bb-hub"><Icon n="graph" s={11} /></span>}
        </div>
      ))}
      {more > 0 && <div className="bb-graph-more">+{more} more connected</div>}
    </div>
  );
}

// context hub inspector — shown when a context / source / collection is focused
function ContextInspector({ id, setSel, flash }) {
  const m = nodeMeta(id);
  const members = neighbors(id).filter((o) => BYID[o.id]);
  return (
    <div className="bb-inspector">
      <div className="bb-insp-head"><div className="grow" /><div className="bb-iconbtn"><Icon n="more" s={16} /></div></div>
      <div className="bb-insp-scroll bb-swap" key={id}>
        <div className="bb-insp-hero">
          <div className="bb-insp-thumb" style={{ width: 84, height: 84, borderRadius: 18, background: m.c + '18', color: m.c }}><Icon n={m.ic} s={34} /></div>
          <div><div className="bb-insp-name">{m.t}</div><div className="bb-insp-sub" style={{ textTransform: 'capitalize' }}>{m.kind} · {members.length} connected items</div></div>
        </div>
        <div className="bb-sec"><div className="bb-why"><div className="lead"><Icon n="graph" s={13} /> This is a hub</div>{members.length} of your items connect through {m.t}. Open one, or click another node in the graph to keep following the thread.</div></div>
        <div className="bb-sec">
          <div className="bb-sec-h">Connected items</div>
          <div className="bb-related">
            {members.map((o) => { const it = BYID[o.id]; return (
              <div key={o.id} className="bb-rel" onClick={() => setSel(o.id)}>
                <span className="ic"><Icon n={it.folder ? 'folder' : (it.img ? 'desktop' : 'doc')} s={15} /></span>
                <div style={{ minWidth: 0 }}><div className="t">{it.name}</div><div className="r">{o.pred} · {SRC[it.src].name}</div></div>
              </div>
            ); })}
          </div>
        </div>
        {m.type === 'source' && <div className="bb-btn-row"><button className="bb-btn" onClick={() => flash('Rescanning ' + m.t + '…')}><Icon n="refresh" s={14} /> Rescan</button><button className="bb-btn" onClick={() => flash('Paused watching')}><Icon n="pause" s={14} /> Pause</button></div>}
      </div>
    </div>
  );
}

// ---------- inbox list ----------
function InboxList({ items, sel, setSel }) {
  if (!items.length) return <div className="bb-insp-empty" style={{ flex: 1 }}><div className="ring"><Icon n="check" s={22} /></div><div style={{ fontSize: 14, fontWeight: 600, color: 'var(--ink-2)' }}>Inbox zero</div><div style={{ fontSize: 12.5 }}>Nothing needs a decision right now.</div></div>;
  return (
    <div className="bb-list">
      {items.map((it) => (
        <div key={it.id} className={'bb-row' + (it.id === sel ? ' sel' : '')} style={{ alignItems: 'flex-start' }} onClick={() => setSel(it.id)}>
          <div className={'bb-ficon' + (it.folder ? '' : ' doc')}><Icon n={it.folder ? 'folder' : (it.img ? 'desktop' : 'doc')} s={18} /></div>
          <div className="bb-rmain"><div className="bb-rname">{it.name}</div><div className="bb-rwhy" style={{ marginTop: 3 }}>{it.why}</div></div>
          <span className={'bb-pill ' + it.status[0]}>{it.status[1]}</span>
        </div>
      ))}
    </div>
  );
}

// ---------- rules ----------
function RulesCenter({ sel, setSel, flash }) {
  return (
    <div className="bb-list">
      {RULES.map((r) => (
        <div key={r.id} className={'bb-srow' + (r.id === sel ? ' sel' : '')} onClick={() => setSel(r.id)}>
          <div className={'bb-ficon doc'} style={{ width: 34, height: 34, flexBasis: 34 }}><Icon n="flow" s={17} /></div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="bb-rname">{r.name}</div>
            <div className="bb-cond">{r.cond}</div>
          </div>
          <div className={'tog' + (r.enabled ? '' : ' off')} onClick={(e) => { e.stopPropagation(); flash(r.enabled ? `Paused “${r.name}”` : `Enabled “${r.name}”`); }}><i /></div>
        </div>
      ))}
      <div className="bb-empty-add" style={{ marginTop: 6 }}><Icon n="plus" s={16} /> New rule — match files, then choose what happens</div>
    </div>
  );
}

// ---------- activity ----------
function ActivityCenter({ sel, setSel }) {
  return (
    <div className="bb-list">
      {ACTIVITY.map((e) => (
        <div key={e.id} className={'bb-srow' + (e.id === sel ? ' sel' : '')} onClick={() => setSel(e.id)} style={{ alignItems: 'flex-start' }}>
          <span className={'bb-tl-pip pip ' + e.cls} style={{ width: 14, height: 14, borderRadius: 7, border: '2px solid var(--' + (e.cls === 'good' ? 'good' : 'info') + ')', marginTop: 3, flex: '0 0 14px' }} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="bb-rname">{e.title}</div>
            <div className="bb-rwhy" style={{ marginTop: 3 }}>{e.detail}</div>
          </div>
          <span className="bb-rdate">{e.when.split(',')[0]}</span>
        </div>
      ))}
    </div>
  );
}

// ---------- inspector ----------
function pillFor(it, resolved) {
  if (it.pending && resolved[it.id]) return resolved[it.id] === 'approve' ? ['good', 'Filed'] : ['ghost', 'Kept'];
  return it.status;
}
function Inspector({ conf, selItem, sel, isPending, decide, resolved, flash, setSel }) {
  if (sel === 'overview') return <OverviewInspector setSel={setSel} />;
  // graph hub focus (context / source / collection / cluster node)
  if (sel && /^(ctx|src|col|cluster):/.test(sel)) return <ContextInspector id={sel} setSel={setSel} flash={flash} />;
  const head = (extra) => (
    <div className="bb-insp-head">
      <div className="bb-iconbtn" onClick={() => flash('Opened in default app')}><Icon n="open" s={16} /></div>
      <div className="bb-iconbtn" onClick={() => flash('Revealed in Finder')}><Icon n="reveal" s={16} /></div>
      <div className="bb-iconbtn" onClick={() => flash('Showing connections')}><Icon n="link" s={16} /></div>
      <div className="grow" />{extra}<div className="bb-iconbtn"><Icon n="more" s={16} /></div>
    </div>
  );

  // rules
  if (conf.type === 'rules') {
    const r = RULES.find((x) => x.id === sel) || RULES[0];
    return (
      <div className="bb-inspector">
        <div className="bb-insp-head"><div className="grow" /><div className="bb-iconbtn"><Icon n="more" s={16} /></div></div>
        <div className="bb-insp-scroll bb-swap" key={r.id}>
          <div className="bb-sec"><div className="bb-sec-h">Rule</div><div className="bb-insp-name" style={{ fontSize: 16 }}>{r.name}</div></div>
          <div className="bb-sec"><div className="bb-sec-h">When</div><div className="bb-cond" style={{ fontSize: 12.5, lineHeight: 1.5 }}>{r.cond}</div></div>
          <div className="bb-sec"><div className="bb-sec-h">Then</div><div style={{ fontSize: 12.5, lineHeight: 1.5 }}>{r.outcome}</div></div>
          <div className="bb-sec"><div className="bb-kv"><span className="k">Ask before doing it</span><span className="v">{r.review ? 'Yes' : 'No'}</span></div>
            <div className="bb-kv"><span className="k">Status</span><span className="v" style={{ color: r.enabled ? 'var(--good)' : 'var(--ink-3)' }}>{r.enabled ? 'Enabled' : 'Paused'}</span></div></div>
          <div className="bb-btn-row"><button className="bb-btn primary" onClick={() => flash('Simulated on Library — 6 items would match')}>Test on Library</button><button className="bb-btn">Edit</button></div>
        </div>
      </div>
    );
  }
  // activity
  if (conf.type === 'activity') {
    const e = ACTIVITY.find((x) => x.id === sel) || ACTIVITY[0];
    return (
      <div className="bb-inspector">
        <div className="bb-insp-head"><div className="grow" /><div className="bb-iconbtn"><Icon n="more" s={16} /></div></div>
        <div className="bb-insp-scroll bb-swap" key={e.id}>
          <div className="bb-sec"><div className="bb-sec-h">{e.kind}</div><div className="bb-insp-name" style={{ fontSize: 16 }}>{e.title}</div></div>
          <div className="bb-sec"><div style={{ fontSize: 12.5, lineHeight: 1.55, color: 'var(--ink-2)' }}>{e.detail}</div></div>
          <div className="bb-sec"><div className="bb-kv"><span className="k">When</span><span className="v">{e.when}</span></div>
            <div className="bb-kv"><span className="k">Reversible</span><span className="v" style={{ color: e.reversible ? 'var(--good)' : 'var(--ink-3)' }}>{e.reversible ? 'Yes' : 'No'}</span></div></div>
          {e.reversible && <button className="bb-btn" onClick={() => flash('Reverted — back to previous state')}><Icon n="undo" s={14} /> Undo this</button>}
        </div>
      </div>
    );
  }
  // source card (no item selected)
  if (!selItem && conf.type === 'src') {
    const s = SRC[conf.src];
    return (
      <div className="bb-inspector">
        {head()}
        <div className="bb-insp-scroll bb-swap" key={conf.src}>
          <div className="bb-insp-hero">
            <div className="bb-insp-thumb" style={{ width: 84, height: 84, color: s.color, background: s.color + '18', borderRadius: 18 }}><Icon n={s.ic} s={34} /></div>
            <div><div className="bb-insp-name">{s.name}</div><div className="bb-insp-sub" style={{ fontFamily: 'var(--mono)', fontSize: 11.5 }}>{s.path}</div></div>
            <span className={'bb-pill ' + s.pill[0]}>{s.pill[1]}</span>
          </div>
          <div className="bb-sec"><div className="bb-sec-h">Status</div><div style={{ fontSize: 12.5, color: 'var(--ink-2)' }}>{s.stat}</div>{s.meter && <div className="bb-meter" style={{ maxWidth: '100%' }}><i style={{ width: s.meter + '%' }} /></div>}</div>
          <div className="bb-sec"><div className="bb-sec-h">What Bipbox does here</div>
            <div className="bb-kv"><span className="k">Remembers</span><span className="v">Top-level items</span></div>
            <div className="bb-kv"><span className="k">Watches new arrivals</span><span className="v">{s.state !== 'Paused' ? 'Yes' : 'Paused'}</span></div>
            <div className="bb-kv"><span className="k">Moves files</span><span className="v">Only when you ask</span></div>
          </div>
          <div className="bb-btn-row">
            <button className="bb-btn" onClick={() => flash('Rescanning ' + s.name + '…')}><Icon n="refresh" s={14} /> Rescan</button>
            <button className="bb-btn" onClick={() => flash(s.state === 'Paused' ? 'Resumed watching' : 'Paused watching')}><Icon n={s.state === 'Paused' ? 'play' : 'pause'} s={14} /> {s.state === 'Paused' ? 'Resume' : 'Pause'}</button>
          </div>
        </div>
      </div>
    );
  }
  // empty
  if (!selItem) {
    return (
      <div className="bb-inspector"><div className="bb-insp-head"><div className="grow" /></div>
        <div className="bb-insp-empty"><div className="ring"><Icon n="layers" s={22} /></div>
          <div style={{ fontSize: 13.5, fontWeight: 600, color: 'var(--ink-2)' }}>Select an item</div>
          <div style={{ fontSize: 12.5 }}>Its details, connections and history show here.</div></div>
      </div>
    );
  }

  // item detail (the unified inspector)
  const it = selItem; const pend = isPending(it); const st = pillFor(it, resolved);
  return (
    <div className="bb-inspector">
      {head()}
      <div className="bb-insp-scroll bb-swap" key={it.id}>
        <div className="bb-insp-hero">
          <div className="bb-insp-thumb"><Icon n={it.folder ? 'folder' : (it.img ? 'desktop' : 'doc')} s={34} /></div>
          <div><div className="bb-insp-name">{it.name}</div><div className="bb-insp-sub">{it.kind} · from {SRC[it.src].name}</div></div>
          <span className={'bb-pill ' + st[0]}>{st[1]}</span>
        </div>

        {pend && (
          <div className="bb-decide">
            <div className="lead"><Icon n="spark" s={14} fill /> Assistant suggests</div>
            <div className="prop">Move to <b>{it.plan.move}</b>{it.plan.coll !== '—' && <> and add to <b>{it.plan.coll}</b></>}. Nothing moves until you approve — it stays findable either way.</div>
            <div className="bb-btn-row">
              <button className="bb-btn primary" onClick={() => decide(it, 'approve')}><Icon n="check" s={14} /> Approve</button>
              <button className="bb-btn" onClick={() => decide(it, 'keep')}>Keep, don’t move</button>
              <button className="bb-btn bad" onClick={() => decide(it, 'reject')}><Icon n="x" s={14} /> Reject</button>
            </div>
          </div>
        )}

        <div className="bb-sec"><div className="bb-why"><div className="lead"><Icon n="spark" s={13} fill /> Why you’re seeing this</div>{it.why}</div></div>

        <div className="bb-sec"><div className="bb-sec-h">Details</div>
          <div className="bb-kv"><span className="k">Kind</span><span className="v">{it.kind}</span></div>
          <div className="bb-kv"><span className="k">Where</span><span className="v mono">{it.path}</span></div>
          <div className="bb-kv"><span className="k">Source</span><span className="v">{SRC[it.src].name}</span></div>
          <div className="bb-kv"><span className="k">Added</span><span className="v">{it.date}</span></div>
        </div>

        <div className="bb-sec"><div className="bb-sec-h">In context</div>
          <div className="bb-ctx-wrap">{(it.ctx || []).map((cid) => { const c = CTXP[cid]; return c ? <span key={cid} className="bb-ctx"><span className="dot" style={{ background: c.c }} />{c.t}</span> : null; })}</div>
        </div>

        <div className="bb-sec"><div className="bb-sec-h">Related</div>
          <div className="bb-related">
            {it.similar && BYID[it.similar] && (
              <div className="bb-rel" onClick={() => setSel(it.similar)}>
                <span className="ic"><Icon n={BYID[it.similar].folder ? 'folder' : 'doc'} s={15} /></span>
                <div style={{ minWidth: 0 }}><div className="t">{BYID[it.similar].name}</div><div className="r">similar content · same source</div></div>
              </div>
            )}
            {it.collection && (
              <div className="bb-rel"><span className="ic"><Icon n="bookmark" s={15} /></span>
                <div style={{ minWidth: 0 }}><div className="t">{it.collection}</div><div className="r">collection it belongs to</div></div></div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
