'use strict';
// Turns a view from config.js into one HTML page. Pure: a string in, a
// string out, no file or network access. The copy is calm and plain, and
// nothing a person sees names a variable.

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

const STATE_WORD = { ready: 'Ready', partly: 'Partly', 'to do': 'To do' };
const STATE_CLASS = { ready: 'ready', partly: 'partly', 'to do': 'todo' };

const CSS = `
:root { --ink: #1f2a30; --soft: #5b6b73; --line: #dfe5e8; --bg: #f7f9fa; --card: #ffffff;
  --ready: #2e7d4f; --partly: #b7791f; --todo: #8a8f94; --link: #1d5fa8; }
@media (prefers-color-scheme: dark) {
  :root { --ink: #e6ebee; --soft: #a4b0b7; --line: #2d373d; --bg: #151a1d; --card: #1d2428;
    --ready: #6fcf97; --partly: #e2b35b; --todo: #8e989e; --link: #7fb2ef; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 1100px; margin: 0 auto; padding: 24px 16px 64px; }
h1 { font-size: 24px; margin: 0 0 4px; }
h2 { font-size: 18px; margin: 40px 0 12px; }
h3 { font-size: 15px; margin: 0 0 4px; }
p { margin: 0 0 8px; }
.lede { color: var(--soft); margin-bottom: 8px; }
nav a { margin-right: 16px; color: var(--link); text-decoration: none; }
a { color: var(--link); }
ul { padding-left: 20px; margin: 0; }
.todo li { margin: 6px 0; }
.todo .done { color: var(--soft); text-decoration: line-through; }
.todo .how { color: var(--soft); display: block; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 12px; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 14px; }
.card .head { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
.state { font-size: 12px; font-weight: 600; letter-spacing: .02em; text-transform: uppercase; }
.state.ready { color: var(--ready); } .state.partly { color: var(--partly); } .state.todo { color: var(--todo); }
.vendor, .note { color: var(--soft); font-size: 14px; }
.part { border-top: 1px solid var(--line); margin-top: 8px; padding-top: 8px; font-size: 14px; }
.links a { margin-right: 12px; font-size: 14px; }
.services { display: grid; grid-template-columns: 1fr; gap: 20px; }
@media (min-width: 900px) { .services { grid-template-columns: 3fr 2fr; } }
.map svg { width: 100%; height: auto; background: var(--card); border: 1px solid var(--line); border-radius: 8px; }
.map text { font: 12px system-ui, sans-serif; fill: var(--ink); }
.map .label { fill: var(--soft); font-size: 11px; }
.map .node { fill: var(--card); stroke: var(--ink); stroke-width: 1.2; }
.map .own { stroke-dasharray: 5 4; }
.map .edge { stroke: var(--soft); stroke-width: 1; fill: none; }
.map .ready { stroke: var(--ready); } .map .partly { stroke: var(--partly); } .map .todo { stroke: var(--todo); }
dl { margin: 0; }
dt { font-weight: 600; margin-top: 12px; }
dd { margin: 2px 0 0; color: var(--ink); }
.unbuilt { color: var(--partly); }
.numbers { display: flex; gap: 16px; flex-wrap: wrap; }
.number { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 12px 18px; min-width: 140px; }
.number b { font-size: 22px; display: block; }
footer { margin-top: 48px; color: var(--soft); font-size: 13px; }
`;

function renderTodo(todo) {
  if (!todo.length) return '<p class="lede">Nothing stands between here and launch.</p>';
  const open = todo.filter((t) => !t.done).length;
  const lede = open === 0
    ? 'Everything on the list is done.'
    : `${open} ${open === 1 ? 'item' : 'items'} left. Items clear themselves when the setting or flag they wait for is in place.`;
  const items = todo.map((t) => {
    const link = t.link ? ` <a href="${esc(t.link)}">How</a>` : '';
    return `<li class="${t.done ? 'done' : 'open'}">${esc(t.title)}${t.done ? '' : link}${t.done ? '' : `<span class="how">${esc(t.how)}</span>`}</li>`;
  }).join('\n');
  return `<p class="lede">${esc(lede)}</p>\n<ul class="todo">\n${items}\n</ul>`;
}

function renderCard(sys) {
  const parts = sys.parts.map((p) => `<div class="part"><b>${esc(p.name)}</b> <span class="state ${STATE_CLASS[p.state]}">${STATE_WORD[p.state]}</span><br>${esc(p.does)} <span class="note">${esc(p.note)}</span></div>`).join('');
  const links = sys.links.map((l) => `<a href="${esc(l.url)}" rel="noopener">${esc(l.label)}</a>`).join('');
  return `<section class="card" id="${esc(sys.id)}">
<div class="head"><h3>${esc(sys.name)}</h3><span class="state ${STATE_CLASS[sys.state]}">${STATE_WORD[sys.state]}</span></div>
${sys.vendor ? `<p class="vendor">${esc(sys.vendor)}</p>` : ''}
<p>${esc(sys.does)}</p>
<p class="note">${esc(sys.note)}</p>
${parts}
${links ? `<p class="links">${links}</p>` : ''}
</section>`;
}

// Three columns: the browser on the left, the app's own parts in the middle,
// the external systems on the right. The browser and the app's parts are
// drawn dashed, as the spec asks, so the eye separates "ours" from "theirs".
function renderMap(view) {
  const own = [{ id: 'browser', name: 'Browser' }].concat(view.app.map((a) => ({ id: a.id, name: a.name })));
  const systems = view.systems;
  const rowH = 52, boxW = 150, boxH = 34;
  const colX = { own: 40, sys: 470 };
  const height = Math.max(own.length, systems.length) * rowH + 40;
  const pos = new Map();
  const ownStart = (height - own.length * rowH) / 2;
  own.forEach((n, i) => pos.set(n.id, { x: colX.own, y: ownStart + i * rowH + 10 }));
  const sysStart = (height - systems.length * rowH) / 2;
  systems.forEach((s, i) => pos.set(s.id, { x: colX.sys, y: sysStart + i * rowH + 10 }));

  const nodes = [];
  for (const n of own) {
    const p = pos.get(n.id);
    nodes.push(`<rect class="node own" x="${p.x}" y="${p.y}" width="${boxW}" height="${boxH}" rx="6"/><text x="${p.x + 10}" y="${p.y + 22}">${esc(n.name)}</text>`);
  }
  for (const s of systems) {
    const p = pos.get(s.id);
    nodes.push(`<rect class="node ${STATE_CLASS[s.state]}" x="${p.x}" y="${p.y}" width="${boxW}" height="${boxH}" rx="6"/><text x="${p.x + 10}" y="${p.y + 22}">${esc(s.name)}</text>`);
  }
  const edges = [];
  for (const s of systems) {
    for (const f of s.flows) {
      const from = pos.get(f.from);
      const to = pos.get(s.id);
      if (!from || !to) continue;
      const x1 = from.x + boxW, y1 = from.y + boxH / 2;
      const x2 = to.x, y2 = to.y + boxH / 2;
      const mx = (x1 + x2) / 2;
      edges.push(`<path class="edge" d="M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}"/>`);
      // Labels sit just before the system they flow into, where the lines
      // have fanned out, so they do not pile up in the middle.
      if (f.label) edges.push(`<text class="label" x="${x2 - 8}" y="${y2 - 5}" text-anchor="end">${esc(f.label)}</text>`);
    }
  }
  const legend = `<text class="label" x="40" y="${height - 8}">Dashed: the browser and this project's own parts. Solid: outside systems, colored by state.</text>`;
  return `<svg viewBox="0 0 640 ${height}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Map of the systems this project talks to">
${edges.join('\n')}
${nodes.join('\n')}
${legend}
</svg>`;
}

function renderFaqGroup(title, entries) {
  const items = entries.map((e) => {
    const built = e.built !== false;
    const answer = built ? esc(e.a) : `<span class="unbuilt">Not built yet.</span> ${esc(e.a)}`;
    const link = e.link ? ` <a href="${esc(e.link)}">${esc(e.link_label || 'Open')}</a>` : '';
    return `<dt id="faq-${esc(e.id)}">${esc(e.q)}</dt><dd>${answer}${link}</dd>`;
  }).join('\n');
  return `<h3>${esc(title)}</h3>\n<dl>\n${items}\n</dl>`;
}

function renderNumbers(view) {
  if (!view.numbers || !view.numbers.items || !view.numbers.items.length) return '';
  let body;
  if (view.mount !== 'online') {
    body = '<p class="lede">Live numbers show when the console is mounted online, behind the owner sign-in. This local copy leaves them out.</p>';
  } else if (!view.live) {
    body = '<p class="lede">The numbers could not be read just now. The rest of the page is still current.</p>';
  } else {
    body = '<div class="numbers">' + view.numbers.items.map((n) => {
      const v = view.live[n.key];
      return `<div class="number"><b>${esc(v == null ? '–' : v)}</b>${esc(n.label)}</div>`;
    }).join('') + '</div>';
  }
  return `<h2 id="numbers">Live numbers</h2>\n${body}`;
}

function renderPage(view) {
  const cards = view.systems.map(renderCard).join('\n');
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(view.project)} console</title>
<style>${CSS}</style>
</head>
<body>
<main>
<h1>${esc(view.project)}</h1>
<p class="lede">What this project talks to, what state each system is in, and how to do the routine things. Built from the project's configuration, not written by hand.</p>
<nav><a href="#todo">Launch to-do</a><a href="#services">Services</a><a href="#faq">FAQ</a>${view.numbers && view.numbers.items && view.numbers.items.length ? '<a href="#numbers">Live numbers</a>' : ''}</nav>

<h2 id="todo">Launch to-do</h2>
${renderTodo(view.todo)}

<h2 id="services">Services</h2>
<p class="lede">One card per outside system. A card is a system, never a task or a feature.</p>
<div class="services">
<div class="grid">
${cards}
</div>
<div class="map">
${renderMap(view)}
</div>
</div>

<h2 id="faq">FAQ</h2>
${renderFaqGroup('How do I', view.faq.how)}
${renderFaqGroup('What happens when', view.faq.when)}

${renderNumbers(view)}

<footer>Generated from the console configuration. To change a card, a to-do item or an answer, change the configuration and reload.</footer>
</main>
</body>
</html>
`;
}

module.exports = { renderPage, renderMap, renderCard, renderTodo, renderFaqGroup, renderNumbers, esc };
