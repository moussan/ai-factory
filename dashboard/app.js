/* MS-AD-Kit dashboard. Vanilla JS, no dependencies, works offline.
   All tenant-supplied text is rendered via textContent (never innerHTML). */
(function () {
  'use strict';
  const meta = n => (document.querySelector(`meta[name=${n}]`) || {}).content || '';
  const TOKEN = meta('kit-token'), MODE = meta('kit-mode');
  const PALETTE = ['--c1', '--c2', '--c3', '--c4', '--c5', '--c6', '--c7', '--c8'];
  const color = i => `var(${PALETTE[i % PALETTE.length]})`;
  const SEV = { high: 0, medium: 1, low: 2, info: 3, good: 4 };
  let DATA = null, route = location.hash.slice(1) || 'overview', demo = false;

  // ---- tiny DOM builder -------------------------------------------------------------
  function h(tag, attrs, ...kids) {
    const el = document.createElement(tag);
    if (attrs) for (const k in attrs) {
      if (k === 'class') el.className = attrs[k];
      else if (k.startsWith('on')) el.addEventListener(k.slice(2), attrs[k]);
      else if (k === 'style') el.setAttribute('style', attrs[k]);
      else if (attrs[k] !== false && attrs[k] != null) el.setAttribute(k, attrs[k]);
    }
    for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
    return el;
  }
  const svgNS = 'http://www.w3.org/2000/svg';
  function s(tag, attrs) { const el = document.createElementNS(svgNS, tag); for (const k in attrs) el.setAttribute(k, attrs[k]); return el; }
  const fmt = n => (typeof n === 'number' ? n.toLocaleString() : n);

  // ---- data loading -----------------------------------------------------------------
  async function api(path, opts) {
    const r = await fetch(path, Object.assign({ headers: { 'X-Kit-Token': TOKEN } }, opts));
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error || r.statusText);
    return j;
  }
  async function load() {
    if (window.__KIT_DATA__) { DATA = window.__KIT_DATA__; return; }
    if (MODE === 'live') { DATA = await api('/api/data'); return; }
    if (window.DEMO_DATA) { DATA = window.DEMO_DATA(); demo = true; return; }
    throw new Error('No data available');
  }
  const cols = () => (DATA.collectors || []).slice().sort((a, b) => a.order - b.order);

  // ---- components -------------------------------------------------------------------
  function countUp(el, to) {
    if (typeof to !== 'number' || to > 1e7) { el.textContent = fmt(to); return; }
    const t0 = performance.now(), d = 700;
    (function step(t) { const p = Math.min(1, (t - t0) / d), e = 1 - Math.pow(1 - p, 3); el.textContent = fmt(Math.round(to * e)); if (p < 1) requestAnimationFrame(step); })(t0);
  }
  function kpi(k, i) {
    const v = h('div', { class: 'v' + (k.text ? ' t' : '') });
    if (k.text) v.textContent = k.value; else countUp(v, k.value);
    return h('div', { class: `card kpi fade ${k.tone || ''}`, style: `animation-delay:${i * 40}ms` }, v, h('div', { class: 'l' }, k.label), k.hint ? h('div', { class: 'h' }, k.hint) : null);
  }
  function donut(items) {
    items = items.filter(x => x.value > 0);
    const total = items.reduce((a, b) => a + b.value, 0);
    if (!total) return h('div', { class: 'empty' }, 'No data');
    const R = 54, C = 2 * Math.PI * R, svg = s('svg', { width: 132, height: 132, viewBox: '0 0 132 132' });
    svg.append(s('circle', { cx: 66, cy: 66, r: R, stroke: 'var(--panel2)' }));
    let off = 0;
    const arcs = items.slice(0, 8).map((it, i) => { const c = s('circle', { cx: 66, cy: 66, r: R, stroke: color(i), 'stroke-dasharray': `0 ${C}`, 'stroke-dashoffset': -off }); off += (it.value / total) * C; svg.append(c); return [c, (it.value / total) * C]; });
    requestAnimationFrame(() => requestAnimationFrame(() => arcs.forEach(([c, len]) => c.setAttribute('stroke-dasharray', `${Math.max(len - 1.5, 0)} ${C}`))));
    const legend = h('div', { class: 'legend' }, items.slice(0, 8).map((it, i) => h('div', null, h('i', { style: `background:${color(i)}` }), h('span', { title: it.label }, it.label), h('b', null, fmt(it.value)))));
    return h('div', { class: 'donut-wrap' }, h('div', { class: 'donut' }, svg, h('div', { class: 'c' }, h('b', null, fmt(total)), h('span', null, 'total'))), legend);
  }
  function bars(items) {
    items = items.slice(0, 12);
    const max = Math.max(1, ...items.map(x => x.value));
    if (!items.length) return h('div', { class: 'empty' }, 'No data');
    const wrap = h('div', { class: 'bars' });
    items.forEach((it, i) => { const fill = h('i', { style: `background:${color(i)}` }); wrap.append(h('div', { class: 'row' }, h('span', { title: it.label }, it.label), h('div', { class: 'bar' }, fill), h('b', null, fmt(it.value)))); requestAnimationFrame(() => requestAnimationFrame(() => fill.style.width = (it.value / max * 100) + '%')); });
    return wrap;
  }
  function line(items) {
    if (items.length < 2) return h('div', { class: 'empty' }, 'Not enough points');
    const W = 400, H = 150, p = 6, max = Math.max(1, ...items.map(x => x.value));
    const pts = items.map((it, i) => [p + i * (W - 2 * p) / (items.length - 1), H - p - (it.value / max) * (H - 2 * p - 8)]);
    const svg = s('svg', { viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: 'none' });
    const d = pts.map((q, i) => (i ? 'L' : 'M') + q[0].toFixed(1) + ' ' + q[1].toFixed(1)).join(' ');
    const grad = 'g' + Math.random().toString(36).slice(2, 7);
    const defs = s('defs', {}), lg = s('linearGradient', { id: grad, x1: 0, y1: 0, x2: 0, y2: 1 });
    lg.append(s('stop', { offset: '0%', 'stop-color': 'var(--c1)', 'stop-opacity': .35 }), s('stop', { offset: '100%', 'stop-color': 'var(--c1)', 'stop-opacity': 0 }));
    defs.append(lg); svg.append(defs);
    svg.append(s('path', { d: d + ` L${W - p} ${H} L${p} ${H} Z`, fill: `url(#${grad})` }));
    const path = s('path', { d, fill: 'none', stroke: 'var(--c1)', 'stroke-width': 2.2, 'stroke-linejoin': 'round', 'vector-effect': 'non-scaling-stroke' });
    svg.append(path);
    pts.forEach((q, i) => { const c = s('circle', { cx: q[0], cy: q[1], r: 8, fill: 'transparent' }); const t = s('title', {}); t.textContent = `${items[i].label}: ${fmt(items[i].value)}`; c.append(t); svg.append(c); });
    return h('div', { class: 'line' }, svg, h('div', { class: 'axis' }, h('span', null, items[0].label), h('span', null, `peak ${fmt(max)}`), h('span', null, items[items.length - 1].label)));
  }
  function chartCard(c, i) {
    const body = c.type === 'donut' ? donut(c.items || []) : c.type === 'line' ? line(c.items || []) : bars(c.items || []);
    return h('div', { class: 'card fade', style: `animation-delay:${i * 50}ms` }, h('h3', null, c.title), body);
  }
  function toCsv(columns, rows) {
    const q = v => { v = v == null ? '' : String(v); return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
    return [columns.map(q).join(','), ...rows.map(r => columns.map(c => q(r[c])).join(','))].join('\r\n');
  }
  function download(name, text) {
    const a = h('a', { href: URL.createObjectURL(new Blob(['﻿' + text], { type: 'text/csv' })), download: name }); document.body.append(a); a.click(); a.remove();
  }
  function table(t) {
    const columns = t.columns && t.columns.length ? t.columns : Object.keys((t.rows || [])[0] || {});
    let rows = (t.rows || []).slice(), sortKey = null, dir = 1, page = 0, q = '';
    const PAGE = 25, body = h('tbody'), head = h('tr'), info = h('span'), prev = h('button', null, '‹'), next = h('button', null, '›');
    const search = h('input', { type: 'search', placeholder: `Search ${rows.length.toLocaleString()} rows…`, oninput: e => { q = e.target.value.toLowerCase(); page = 0; draw(); } });
    const view = () => { let r = rows; if (q) r = r.filter(x => columns.some(c => String(x[c] ?? '').toLowerCase().includes(q))); if (sortKey) r = r.slice().sort((a, b) => { const x = a[sortKey], y = b[sortKey]; return (typeof x === 'number' && typeof y === 'number' ? x - y : String(x ?? '').localeCompare(String(y ?? ''), undefined, { numeric: true })) * dir; }); return r; };
    function draw() {
      const r = view(), pages = Math.max(1, Math.ceil(r.length / PAGE)); page = Math.min(page, pages - 1);
      body.replaceChildren(...r.slice(page * PAGE, page * PAGE + PAGE).map(row => h('tr', null, columns.map(c => { const v = row[c]; const sv = String(v ?? ''); const cls = /^(true|yes|enabled|compliant|serviceOperational|operational)$/i.test(sv) ? 'good' : /^(false|no|disabled|noncompliant|non-compliant|expired|high)$/i.test(sv) ? 'bad' : ''; return h('td', { class: cls, title: sv }, sv); }))));
      info.textContent = `${r.length.toLocaleString()} rows · page ${page + 1}/${pages}`; prev.disabled = page === 0; next.disabled = page >= pages - 1;
    }
    columns.forEach(c => head.append(h('th', { onclick: () => { dir = sortKey === c ? -dir : 1; sortKey = c; draw(); } }, c)));
    prev.onclick = () => { page--; draw(); }; next.onclick = () => { page++; draw(); };
    draw();
    return h('div', { class: 'card fade', style: 'margin-bottom:16px' },
      h('div', { class: 'tbl-tools' }, h('h3', null, t.title + (t.truncated ? ' (truncated)' : '')), search, h('button', { onclick: () => download((t.title || 'table').replace(/\W+/g, '_') + '.csv', toCsv(columns, view())) }, 'CSV')),
      h('div', { class: 'tbl-scroll' }, h('table', null, h('thead', null, head), body)), h('div', { class: 'pager' }, info, prev, next));
  }
  function findingRow(f, showLink) {
    return h('div', { class: 'f' }, h('span', { class: 'sev ' + f.severity }, f.severity), h('span', null, f.text),
      showLink ? h('a', { href: '#c/' + f.cid }, f.ctitle + ' →') : null);
  }

  // ---- views ------------------------------------------------------------------------
  function overview() {
    const all = cols(), v = h('div');
    const org = all.find(c => c.id === 'org');
    const findings = all.flatMap(c => (c.findings || []).map(f => Object.assign({ cid: c.id, ctitle: c.title }, f))).sort((a, b) => SEV[a.severity] - SEV[b.severity]);
    const n = k => findings.filter(f => f.severity === k).length;
    const heads = [];
    if (org && org.summary) heads.push(...org.summary.slice(0, 2).map(x => ({ label: x.label, value: x.value, text: true })));
    heads.push({ label: 'Critical findings', value: n('high'), tone: n('high') ? 'bad' : 'good' }, { label: 'Warnings', value: n('medium'), tone: n('medium') ? 'warn' : 'good' }, { label: 'Notes', value: n('low') + n('info') });
    all.filter(c => c.id !== 'org' && c.status === 'ok').forEach(c => { const k = (c.summary || [])[0]; if (k) heads.push({ label: c.title + ' · ' + k.label, value: k.value, text: k.text, tone: k.tone }); });
    v.append(h('div', { class: 'grid kpis' }, heads.slice(0, 14).map(kpi)));
    const feats = findings.filter(f => f.severity !== 'good');
    v.append(h('div', { class: 'card findings fade', style: 'margin-bottom:16px' }, h('h3', null, `Findings (${feats.length})`), feats.length ? feats.slice(0, 40).map(f => findingRow(f, true)) : h('div', { class: 'empty' }, 'Nothing needs attention 🎉'), findings.filter(f => f.severity === 'good').slice(0, 5).map(f => findingRow(f, true))));
    const feat = all.filter(c => c.status === 'ok' && (c.charts || []).length && c.id !== 'org').slice(0, 9).map(c => Object.assign({}, c.charts[0], { title: c.title + ' · ' + c.charts[0].title }));
    v.append(h('div', { class: 'grid charts' }, feat.map(chartCard)));
    v.append(h('h3', { class: 'muted' }, 'Collector health'), h('div', { class: 'grid health' }, all.map(c => h('div', { class: 'h', title: c.error || '', onclick: () => location.hash = 'c/' + c.id }, h('span', { class: 'dot ' + c.status }), h('span', null, c.title), h('span', { class: 'muted', style: 'margin-left:auto' }, c.status === 'ok' ? c.ms + ' ms' : c.status)))));
    return v;
  }
  function section(c) {
    const v = h('div');
    if (c.status !== 'ok') { v.append(h('div', { class: 'card err' }, h('h3', null, c.status === 'skipped' ? 'Skipped' : 'This collector failed'), h('div', null, c.error || ''), h('p', { class: 'muted' }, 'Most failures are a missing admin role/licence or un-granted consent for the permission this collector needs. Other sections are unaffected.'))); return v; }
    if ((c.summary || []).length) v.append(h('div', { class: 'grid kpis' }, c.summary.map(kpi)));
    if ((c.findings || []).length) v.append(h('div', { class: 'card findings fade', style: 'margin-bottom:16px' }, h('h3', null, 'Findings'), c.findings.slice().sort((a, b) => SEV[a.severity] - SEV[b.severity]).map(f => findingRow(f))));
    if ((c.charts || []).length) v.append(h('div', { class: 'grid charts' }, c.charts.map(chartCard)));
    (c.tables || []).forEach(t => v.append(table(t)));
    return v;
  }
  const PRESETS = ['/me', '/organization', '/users?$top=5', '/groups?$top=5', '/subscribedSkus', '/domains', '/devices?$top=5', '/applications?$top=5', '/servicePrincipals?$top=5', '/directoryRoles', '/identity/conditionalAccess/policies', '/policies/authorizationPolicy', '/deviceManagement/managedDevices?$top=5', '/deviceManagement/deviceCompliancePolicies', '/deviceAppManagement/mobileApps?$top=5', '/security/alerts_v2?$top=5', '/sites?search=*', '/teams', "/reports/getOffice365ActiveUserDetail(period='D30')", '/admin/serviceAnnouncement/issues?$top=5', '/subscriptions?api-version=2022-12-01', '/providers/Microsoft.Management/managementGroups?api-version=2021-04-01'];
  function query() {
    const out = h('div'), target = h('select', null, h('option', { value: 'graph' }, 'Microsoft Graph v1.0'), h('option', { value: 'graph-beta' }, 'Microsoft Graph beta'), h('option', { value: 'arm' }, 'Azure Resource Manager'));
    const path = h('input', { type: 'text', list: 'presets', value: '/users?$top=5', placeholder: '/users?$top=5' });
    const all = h('input', { type: 'checkbox', id: 'allp' });
    const run = h('button', { class: 'primary' }, 'Run');
    const dl = h('button', null, 'CSV'); dl.hidden = true;
    let last = null;
    const flat = o => { const r = {}; for (const k in o) { const v = o[k]; r[k] = v === null || v === undefined ? '' : typeof v === 'object' ? JSON.stringify(v) : v; } return r; };
    async function go() {
      out.replaceChildren(h('div', { class: 'empty' }, 'Running…')); dl.hidden = true; run.disabled = true;
      try {
        if (MODE !== 'live') throw new Error('Live queries need the running tool (not demo/export mode).');
        const res = await api(`/api/query?target=${target.value}&path=${encodeURIComponent(path.value)}&all=${all.checked ? 1 : 0}`);
        last = res;
        const arr = Array.isArray(res.value) ? res.value : null;
        if (arr && arr.length && typeof arr[0] === 'object') {
          const rows = arr.map(flat), columns = [...new Set(rows.flatMap(Object.keys))].slice(0, 14);
          out.replaceChildren(table({ title: `${rows.length} result(s)`, columns, rows }), h('details', null, h('summary', { class: 'muted' }, 'Raw JSON'), h('pre', null, JSON.stringify(res, null, 2))));
          dl.hidden = false; dl.onclick = () => download('query.csv', toCsv(columns, rows));
        } else if (res.csv) {
          const lines = res.csv.replace(/^﻿/, '').trim().split(/\r?\n/), head = lines[0].split(','), rows = lines.slice(1).map(l => { const p = l.split(','); const o = {}; head.forEach((k, i) => o[k] = p[i]); return o; });
          out.replaceChildren(table({ title: `${rows.length} report row(s)`, columns: head, rows })); dl.hidden = false; dl.onclick = () => download('report.csv', res.csv);
        } else out.replaceChildren(h('pre', null, JSON.stringify(res, null, 2)));
      } catch (e) { out.replaceChildren(h('div', { class: 'card err' }, String(e.message || e))); }
      run.disabled = false;
    }
    run.onclick = go; path.addEventListener('keydown', e => { if (e.key === 'Enter') go(); });
    return h('div', null, h('datalist', { id: 'presets' }, PRESETS.map(p => h('option', { value: p }))),
      h('div', { class: 'card', style: 'margin-bottom:16px' }, h('h3', null, 'Query explorer — read-only (GET). Ask the tenant for anything the signed-in account is allowed to see.'),
        h('div', { class: 'q-row' }, target, path, h('label', { class: 'muted' }, all, ' all pages'), run, dl),
        h('div', { class: 'muted' }, 'Tip: start typing for common endpoints. Permissions are limited to what you consented to at sign-in.')), out);
  }

  // ---- shell ------------------------------------------------------------------------
  function drawNav() {
    const nav = h('aside', { id: 'nav' }, h('div', { class: 'brand' }, h('i'), 'MS-AD-Kit'),
      h('a', { class: 'nav-item' + (route === 'overview' ? ' active' : ''), href: '#overview' }, '📊 Overview'));
    nav.append(h('div', { class: 'nav-sep' }, 'Sections'));
    cols().forEach(c => nav.append(h('a', { class: 'nav-item' + (route === 'c/' + c.id ? ' active' : ''), href: '#c/' + c.id }, (c.icon || '•') + ' ' + c.title, h('span', { class: 'dot ' + c.status }))));
    nav.append(h('div', { class: 'nav-sep' }, 'Tools'), h('a', { class: 'nav-item' + (route === 'query' ? ' active' : ''), href: '#query' }, '🔎 Query explorer'));
    document.getElementById('nav').replaceWith(nav);
  }
  function drawTop(title) {
    const gen = DATA.generated ? new Date(DATA.generated).toLocaleString() : '';
    const btn = (t, fn, cls) => h('button', { class: cls || '', onclick: fn }, t);
    const refresh = btn('⟳ Refresh', async e => { e.target.disabled = true; e.target.textContent = 'Collecting…'; try { await api('/api/refresh', { method: 'POST' }); await load(); render(); } catch (x) { alert(x.message); e.target.disabled = false; e.target.textContent = '⟳ Refresh'; } });
    const upd = btn('⬆ Check for updates', async e => { e.target.disabled = true; try { const r = await api('/api/update-check'); if (r.error) alert('Update check failed: ' + r.error); else if (!r.available) alert('Already up to date.'); else if (confirm(`New version: ${r.message}\nUpdate now?`)) { const u = await api('/api/update', { method: 'POST' }); alert(u.message); } } catch (x) { alert(x.message); } e.target.disabled = false; });
    const theme = btn('◐', () => { const d = document.documentElement; const n = d.dataset.theme === 'dark' ? 'light' : 'dark'; d.dataset.theme = n; try { localStorage.setItem('kit-theme', n); } catch (e) { } });
    const top = h('header', { id: 'top' }, h('h1', null, title), h('span', { class: 'sub' }, [DATA.user && 'Signed in: ' + DATA.user, gen && 'Collected: ' + gen].filter(Boolean).join(' · ')), ...(MODE === 'live' ? [refresh, upd] : []), theme);
    document.getElementById('top').replaceWith(top);
  }
  function render() {
    drawNav();
    let title = 'Overview', body;
    if (route === 'query') { title = 'Query explorer'; body = query(); }
    else if (route.startsWith('c/')) { const c = cols().find(x => x.id === route.slice(2)); if (c) { title = (c.icon || '') + ' ' + c.title; body = section(c); } }
    if (!body) body = overview();
    drawTop(title);
    const view = h('section', { id: 'view' });
    if (demo) view.append(h('div', { class: 'banner' }, 'Demo data — fictional tenant. Run without -Demo and sign in to see yours.'));
    view.append(body);
    document.getElementById('view').replaceWith(view);
    window.scrollTo(0, 0);
  }
  window.addEventListener('hashchange', () => { route = location.hash.slice(1) || 'overview'; if (DATA) render(); });
  try { const t = localStorage.getItem('kit-theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'); document.documentElement.dataset.theme = t; } catch (e) { document.documentElement.dataset.theme = 'dark'; }
  load().then(render).catch(e => { document.getElementById('view').replaceChildren(h('div', { class: 'card err' }, 'Could not load data: ' + e.message)); });
})();
