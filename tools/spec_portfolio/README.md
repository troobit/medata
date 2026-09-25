# Spec portfolio

Two stdlib-only scripts that turn `specs/` into one explorable page.

- `collect.py <out.json>` walks every spec folder (any directory under `specs/`
  with requirements, design, smolspec, prd, report, decision_log or a tasks
  file), asks `rune list -f json` for task counts, parses the decision log
  headers and status lines, reads git for first/last touched and 30-day commit
  count, and matches `specs/BACKLOG.md` items by name. It emits the JSON
  contract documented at the top of the file and prints a table for a sanity
  check. Order: last touched desc, then remaining tasks desc.
- `render.py --data data.json --out portfolio.html` renders a single
  self-contained HTML page: KPI tiles, search, area/state chips, a sort toggle
  (last touched / most remaining), one card per spec with a progress bar,
  remaining count, proposed-decision and blocked badges, and a details
  disclosure (pending tasks by phase, decisions, backlog refs, paths).
  Completed specs are greyed and collapsed at the bottom; dormant ones (not
  touched in 14 days, not complete) get a dashed border.

`make spec-portfolio` runs both into `/private/tmp/medata-portfolio/`. The
page is what gets published (as a private artifact); the JSON is the contract
between the two halves, so either can be swapped without touching the other.
State rules: complete = every task done and no proposed decision; active =
touched within 14 days; dormant = everything else.
