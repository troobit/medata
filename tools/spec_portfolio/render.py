#!/usr/bin/env python3
"""Render the spec portfolio page from collect.py's data.json.

Usage: python3 tools/spec_portfolio/render.py --data data.json --out portfolio.html

Stdlib only. The output depends on the input alone (relative dates are taken
against generated_at, not the wall clock), so re-running is idempotent.
"""

import argparse
import datetime as dt
import json
from html import escape as esc

AREAS = ["estimation", "ui", "data", "bugfixes", "other"]
STATES = ["active", "dormant", "complete"]


def parse_date(s):
    if not s:
        return None
    try:
        return dt.date.fromisoformat(str(s)[:10])
    except ValueError:
        return None


def relative(date, today):
    if date is None or today is None:
        return "unknown"
    days = (today - date).days
    if days <= 0:
        return "today"
    if days == 1:
        return "1 d"
    if days < 14:
        return f"{days} d"
    if days < 60:
        return f"{days // 7} w"
    if days < 365:
        return f"{days // 30} mo"
    years = days // 365
    return f"{years} y"


def badge(text, cls=""):
    return f'<span class="tag {cls}">{esc(text)}</span>'


def render_pending(tasks):
    if not tasks:
        return "<p class=\"muted\">No pending tasks.</p>"
    groups = []
    index = {}
    for t in tasks:
        phase = t.get("phase") or "No phase"
        if phase not in index:
            index[phase] = len(groups)
            groups.append((phase, []))
        groups[index[phase]][1].append(t)
    out = []
    for phase, items in groups:
        out.append(f"<h4>{esc(phase)}</h4><ul>")
        for t in items:
            mark = ' <span class="tag acc">blocked</span>' if t.get("blocked") else ""
            file_note = ""
            if t.get("file") and t["file"] != "tasks.md":
                file_note = f' <span class="muted mono">{esc(t["file"])}</span>'
            out.append(
                f'<li><span class="mono muted">{esc(str(t.get("id", "")))}</span> '
                f'{esc(t.get("title", ""))}{mark}{file_note}</li>'
            )
        out.append("</ul>")
    return "".join(out)


def render_decisions(decisions):
    if not decisions:
        return "<p class=\"muted\">No decisions recorded.</p>"
    out = ["<table><tr><th>#</th><th>Decision</th><th>Status</th><th>Date</th></tr>"]
    for d in decisions:
        status = str(d.get("status", ""))
        cls = ""
        if status.startswith("proposed"):
            cls = "warn"
        elif status.startswith("accepted"):
            cls = "ok"
        elif status.startswith("rejected"):
            cls = "acc"
        row_cls = ' class="hl"' if cls == "warn" else ""
        out.append(
            f"<tr{row_cls}><td>{esc(str(d.get('id', '')))}</td><td>{esc(d.get('title', ''))}</td>"
            f"<td>{badge(status, cls)}</td><td>{esc(str(d.get('date') or ''))}</td></tr>"
        )
    out.append("</table>")
    return "".join(out)


def render_backlog(refs):
    if not refs:
        return ""
    out = ["<h4>Backlog refs</h4><ul>"]
    for r in refs:
        done = ' <span class="tag ok">done</span>' if r.get("done") else ""
        out.append(f'<li><span class="mono muted">#{esc(str(r.get("n", "")))}</span> {esc(r.get("text", ""))}{done}</li>')
    out.append("</ul>")
    return "".join(out)


def render_paths(paths):
    items = []
    for key in ("folder", "requirements", "design", "decision_log"):
        v = paths.get(key)
        if v:
            items.append(f"<li><span class=\"muted\">{esc(key)}</span> <span class=\"mono\">{esc(v)}</span></li>")
    for v in paths.get("tasks") or []:
        items.append(f"<li><span class=\"muted\">tasks</span> <span class=\"mono\">{esc(v)}</span></li>")
    if not items:
        return ""
    return "<h4>Files</h4><ul class=\"paths\">" + "".join(items) + "</ul>"


def render_card(spec, today):
    t = spec.get("tasks") or {}
    total = int(t.get("total") or 0)
    done = int(t.get("done") or 0)
    blocked = int(t.get("blocked") or 0)
    remaining = max(total - done, 0)
    proposed = int((spec.get("decisions") or {}).get("proposed") or 0)
    state = spec.get("state") or "active"
    area = spec.get("area") or "other"
    if area not in AREAS:
        area = "other"
    touched = parse_date(spec.get("last_touched"))
    pct = round(100 * done / total) if total else 0
    name = spec.get("name") or spec.get("id") or "?"
    search_blob = " ".join(
        [name, spec.get("summary") or ""] + [p.get("title", "") for p in spec.get("pending_tasks") or []]
    ).lower()

    badges = [badge(area, "area"), badge(str(spec.get("kind") or "spec"))]
    if state == "complete":
        badges.append(badge("complete", "muted"))
    elif state == "dormant":
        badges.append(badge("dormant", "dormant"))

    stats = [f'<span class="remain"><b>{remaining}</b> remaining</span>']
    if proposed:
        stats.append(badge(f"{proposed} proposed decision{'s' if proposed != 1 else ''}", "warn"))
    if blocked:
        stats.append(badge(f"{blocked} blocked", "acc"))
    warnings = spec.get("warnings") or []
    if warnings:
        stats.append(badge(f"{len(warnings)} warning{'s' if len(warnings) != 1 else ''}", "muted"))

    details = [
        "<div class=\"section\"><h3>Pending tasks</h3>" + render_pending(spec.get("pending_tasks") or []) + "</div>",
        "<div class=\"section\"><h3>Decisions</h3>" + render_decisions(spec.get("decision_list") or []) + "</div>",
    ]
    backlog = render_backlog(spec.get("backlog_refs") or [])
    if backlog:
        details.append("<div class=\"section\">" + backlog + "</div>")
    if warnings:
        details.append(
            "<div class=\"section\"><h4>Warnings</h4><ul>"
            + "".join(f"<li>{esc(str(w))}</li>" for w in warnings)
            + "</ul></div>"
        )
    details.append("<div class=\"section\">" + render_paths(spec.get("paths") or {}) + "</div>")

    return f"""<article class="card {esc(state)}" data-area="{esc(area)}" data-state="{esc(state)}"
 data-remaining="{remaining}" data-touched="{esc(spec.get('last_touched') or '')}" data-search="{esc(search_blob)}">
<div class="head">
 <h3 class="name mono">{esc(name)}</h3>
 <span class="touched" title="last touched {esc(spec.get('last_touched') or 'unknown')}">{esc(relative(touched, today))}</span>
</div>
<div class="badges">{"".join(badges)}</div>
<p class="summary">{esc(spec.get('summary') or '')}</p>
<div class="bar" role="progressbar" aria-valuemin="0" aria-valuemax="{total}" aria-valuenow="{done}" aria-label="{done} of {total} tasks done"><span style="width:{pct}%"></span></div>
<div class="stats">{"".join(stats)}<span class="muted">{done} / {total} done{f", {t.get('in_progress')} in progress" if t.get('in_progress') else ""}</span></div>
<details><summary>details</summary>{"".join(details)}</details>
</article>"""


CSS = """
:root{--bg:#f7f6f2;--fg:#1c1c1a;--muted:#5f5e58;--line:#d9d6cc;--acc:#8a2b1e;--ok:#2d6a4f;--warn:#a5641b;--card:#fffdf8;--fill:#ecebe5;--focus:#2b5c9a}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15161a;--fg:#ececea;--muted:#a3a39c;--line:#33353b;--acc:#e07a63;--ok:#7bc99e;--warn:#e2a95b;--card:#1d1f25;--fill:#2a2c33;--focus:#8ab4f8}}
:root[data-theme="dark"]{--bg:#15161a;--fg:#ececea;--muted:#a3a39c;--line:#33353b;--acc:#e07a63;--ok:#7bc99e;--warn:#e2a95b;--card:#1d1f25;--fill:#2a2c33;--focus:#8ab4f8}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Helvetica Neue",Helvetica,Arial,sans-serif}
main{max-width:960px;margin:0 auto;padding:32px 16px 64px}
h1{font-size:1.9rem;margin:0 0 4px;letter-spacing:-.01em}
h2{font-size:1.25rem;margin:40px 0 8px;border-bottom:1px solid var(--line);padding-bottom:4px}
h3{font-size:1rem;margin:20px 0 6px}h4{font-size:.9rem;margin:14px 0 4px;color:var(--muted);font-weight:600}
.sub{color:var(--muted);margin:0 0 24px}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
.muted{color:var(--muted)}
.kpi{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;margin:16px 0}
.kpi div{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.kpi b{display:block;font-size:1.4rem;letter-spacing:-.01em}.kpi span{color:var(--muted);font-size:.9rem}
.kpi .warn b{color:var(--warn)}
.controls{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px;margin:16px 0;display:flex;flex-direction:column;gap:10px}
.controls input[type=search]{width:100%;font:inherit;padding:8px 10px;border:1px solid var(--line);border-radius:8px;background:var(--bg);color:var(--fg)}
.row{display:flex;flex-wrap:wrap;gap:6px;align-items:center}
.row .lbl{color:var(--muted);font-size:.85rem;margin-right:4px;min-width:3.2em}
.chip{font:inherit;font-size:.85rem;padding:2px 10px;border-radius:999px;border:1px solid var(--line);background:transparent;color:var(--muted);cursor:pointer}
.chip[aria-pressed=true],.chip[aria-checked=true]{background:var(--fg);color:var(--bg);border-color:var(--fg)}
.chip:focus-visible,summary:focus-visible,input:focus-visible,.toggle:focus-visible{outline:2px solid var(--focus);outline-offset:2px}
.count{color:var(--muted);font-size:.9rem;margin:8px 0 0}
.list{display:flex;flex-direction:column;gap:12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px}
.card.dormant{border-style:dashed}
.card.complete{opacity:.6}
.hidden{display:none}
.head{display:flex;justify-content:space-between;align-items:baseline;gap:12px;flex-wrap:wrap}
.name{font-size:1.05rem;margin:0;font-weight:600;overflow-wrap:anywhere}
.touched{color:var(--muted);font-size:.9rem;white-space:nowrap}
.badges{margin:6px 0 4px;display:flex;flex-wrap:wrap;gap:4px}
.summary{margin:6px 0 10px}
.bar{height:8px;background:var(--fill);border-radius:4px;overflow:hidden}
.bar span{display:block;height:100%;background:var(--ok)}
.stats{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:8px 0 4px;font-size:.9rem}
.remain b{font-size:1.15rem}
.tag{display:inline-block;padding:1px 8px;border-radius:999px;font-size:.8rem;border:1px solid var(--line);color:var(--muted)}
.tag.ok{color:var(--ok);border-color:var(--ok)}.tag.warn{color:var(--warn);border-color:var(--warn)}.tag.acc{color:var(--acc);border-color:var(--acc)}
.tag.area{color:var(--fg);border-color:var(--fg)}.tag.dormant{border-style:dashed}
details{margin-top:6px}summary{cursor:pointer;color:var(--muted);font-size:.9rem;user-select:none}
details .section{margin-top:4px}
details h3{margin:14px 0 4px}
ul{margin:4px 0 8px;padding-left:20px}li{margin:3px 0;overflow-wrap:anywhere}
ul.paths{list-style:none;padding-left:0}ul.paths li{font-size:.85rem}
table{border-collapse:collapse;width:100%;margin:6px 0;font-size:.9rem}th,td{text-align:left;padding:5px 6px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--muted);font-weight:600}
tr.hl td{background:var(--fill)}
.toggle{font:inherit;background:none;border:none;color:var(--fg);cursor:pointer;padding:0;font-size:1.25rem;font-weight:600;text-align:left}
.toggle::before{content:"\\25B8";display:inline-block;width:1em;color:var(--muted)}
.toggle[aria-expanded=true]::before{content:"\\25BE"}
.empty{color:var(--muted);padding:12px 0}
"""

JS = """
(function(){
var q=document.getElementById('q');
var areaChips=[].slice.call(document.querySelectorAll('[data-filter=area]'));
var stateChips=[].slice.call(document.querySelectorAll('[data-filter=state]'));
var sortChips=[].slice.call(document.querySelectorAll('[data-sort]'));
var lists={open:document.getElementById('open-list'),done:document.getElementById('done-list')};
var cards=[].slice.call(document.querySelectorAll('.card'));
var doneToggle=document.getElementById('done-toggle');
var doneSection=document.getElementById('done');
var doneOpen=false;
function pressed(chips){return chips.filter(function(c){return c.getAttribute('aria-pressed')==='true'}).map(function(c){return c.dataset.value})}
function sortKey(){var s=sortChips.filter(function(c){return c.getAttribute('aria-checked')==='true'})[0];return s?s.dataset.sort:'touched'}
function cmp(a,b){
  var ta=a.dataset.touched,tb=b.dataset.touched,ra=+a.dataset.remaining,rb=+b.dataset.remaining;
  if(sortKey()==='remaining'){if(ra!==rb)return rb-ra;return tb<ta?-1:tb>ta?1:0}
  if(ta!==tb)return tb<ta?-1:1;return rb-ra;
}
function apply(){
  var text=(q.value||'').trim().toLowerCase();
  var areas=pressed(areaChips),states=pressed(stateChips);
  var shown={open:0,done:0};
  cards.forEach(function(c){
    var ok=true;
    if(areas.length&&areas.indexOf(c.dataset.area)<0)ok=false;
    if(states.length&&states.indexOf(c.dataset.state)<0)ok=false;
    if(text&&c.dataset.search.indexOf(text)<0)ok=false;
    c.classList.toggle('hidden',!ok);
    if(ok)shown[c.dataset.state==='complete'?'done':'open']++;
  });
  Object.keys(lists).forEach(function(k){
    var l=lists[k];var kids=[].slice.call(l.querySelectorAll('.card')).sort(cmp);
    kids.forEach(function(c){l.appendChild(c)});
    var e=l.querySelector('.empty');if(e)l.appendChild(e);
    e.classList.toggle('hidden',shown[k]>0);
  });
  document.getElementById('open-count').textContent=shown.open+' shown';
  var forced=!!text&&shown.done>0;
  var expanded=doneOpen||forced;
  doneToggle.setAttribute('aria-expanded',expanded?'true':'false');
  doneToggle.textContent='Completed ('+shown.done+')'+(forced&&!doneOpen?' matching search':'');
  lists.done.classList.toggle('hidden',!expanded);
}
function toggleChip(c){c.setAttribute('aria-pressed',c.getAttribute('aria-pressed')==='true'?'false':'true');apply()}
areaChips.concat(stateChips).forEach(function(c){c.addEventListener('click',function(){toggleChip(c)})});
sortChips.forEach(function(c){c.addEventListener('click',function(){sortChips.forEach(function(o){o.setAttribute('aria-checked',o===c?'true':'false')});apply()})});
q.addEventListener('input',apply);
doneToggle.addEventListener('click',function(){doneOpen=!doneOpen;apply()});
document.getElementById('expand-all').addEventListener('click',function(){
  var open=this.getAttribute('aria-pressed')!=='true';this.setAttribute('aria-pressed',open?'true':'false');
  cards.forEach(function(c){if(!c.classList.contains('hidden'))c.querySelector('details').open=open});
});
apply();
})();
"""


def render(data):
    today = parse_date(data.get("generated_at"))
    specs = data.get("specs") or []
    totals = data.get("totals") or {}
    open_cards = [render_card(s, today) for s in specs if (s.get("state") or "active") != "complete"]
    done_cards = [render_card(s, today) for s in specs if (s.get("state") or "active") == "complete"]

    kpis = [
        ("specs", totals.get("specs", len(specs)), ""),
        ("active", totals.get("active", 0), ""),
        ("dormant", totals.get("dormant", 0), ""),
        ("complete", totals.get("complete", 0), ""),
        ("tasks remaining", totals.get("tasks_remaining", 0), ""),
        ("proposed decisions", totals.get("decisions_proposed", 0), "warn" if totals.get("decisions_proposed") else ""),
    ]
    kpi_html = "".join(
        f'<div class="{cls}"><b>{esc(str(v))}</b><span>{esc(label)}</span></div>' for label, v, cls in kpis
    )
    area_chips = "".join(
        f'<button type="button" class="chip" data-filter="area" data-value="{a}" aria-pressed="false">{a}</button>'
        for a in AREAS
    )
    state_chips = "".join(
        f'<button type="button" class="chip" data-filter="state" data-value="{s}" aria-pressed="false">{s}</button>'
        for s in STATES
    )
    payload = json.dumps(data, sort_keys=True, separators=(",", ":")).replace("</", "<\\/")
    generated = esc(str(data.get("generated_at") or "unknown"))
    head = esc(str(data.get("repo_head") or "unknown"))

    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>MeData Spec Portfolio</title>
<meta name="description" content="Remaining work across the MeData specs: tasks, decisions and state per spec.">
<style>{CSS}</style></head><body><main>
<h1>MeData Spec Portfolio</h1>
<p class="sub">Generated {generated} at <span class="mono">{head}</span>. One card per spec; the order is last touched first.</p>
<div class="kpi">{kpi_html}</div>
<div class="controls">
 <label class="muted" for="q" style="font-size:.85rem">Search name, summary and pending task titles</label>
 <input id="q" type="search" placeholder="Search" autocomplete="off">
 <div class="row"><span class="lbl">area</span>{area_chips}</div>
 <div class="row"><span class="lbl">state</span>{state_chips}</div>
 <div class="row" role="radiogroup" aria-label="sort"><span class="lbl">sort</span>
  <button type="button" class="chip" role="radio" data-sort="touched" aria-checked="true">last touched</button>
  <button type="button" class="chip" role="radio" data-sort="remaining" aria-checked="false">most remaining</button>
  <span class="lbl" style="margin-left:auto"></span>
  <button type="button" class="chip" id="expand-all" aria-pressed="false">expand all details</button>
 </div>
</div>
<h2>Open <span class="count" id="open-count"></span></h2>
<div class="list" id="open-list">{"".join(open_cards)}<p class="empty hidden">No open specs match.</p></div>
<section id="done">
<h2><button type="button" class="toggle" id="done-toggle" aria-expanded="false" aria-controls="done-list">Completed ({len(done_cards)})</button></h2>
<div class="list hidden" id="done-list">{"".join(done_cards)}<p class="empty hidden">No completed specs match.</p></div>
</section>
<script id="portfolio-data" type="application/json">{payload}</script>
<script>{JS}</script>
</main></body></html>
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--data", required=True, help="path to data.json from collect.py")
    ap.add_argument("--out", required=True, help="path to write portfolio.html")
    args = ap.parse_args()
    with open(args.data, encoding="utf-8") as f:
        data = json.load(f)
    html = render(data)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"wrote {args.out} ({len(html.encode('utf-8'))} bytes, {len(data.get('specs') or [])} specs)")


if __name__ == "__main__":
    main()
