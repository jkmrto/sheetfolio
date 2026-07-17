---
name: verify
description: Run sheetfolio locally and drive it in a browser to verify UI changes.
---

# Verifying sheetfolio changes

## Launch

```bash
mix deps.get   # worktrees start without deps/_build
export $(sed 's|~/|'$HOME'/|g' ~/projects/sheetfolio/.env | xargs) && mix phx.server
```

- Serves on `127.0.0.1:4000` (hardcoded in `config/dev.exs`). Check the port is free first — the user may have `make run` going.
- `.env` lives in the main checkout (`~/projects/sheetfolio/.env`), not in worktrees.
- `.env` has no `APP_PASSWORD`, so it defaults to `""`: on `/login`, submit the form with an empty password.

## Drive

- Pages outside the `live_session :authenticated` block (`/history`, `/cash`, `/expenses`, `/control`) load immediately — no waiting on `OperationsServer`.
- Pages inside it (`/earnings`, `/operations`, `/summary*`, `/snapshot`) redirect to `/loading` for several minutes after boot while Gmail operations load. Avoid them unless you can wait.
- Charts are canvas via the `HistoryChart` hook; they don't appear in accessibility snapshots — take screenshots to observe them. The hook re-renders on any `data-chart` change.
- Mongo Atlas is shared with production: reading is fine, avoid writes (e.g. the Cash "Save today" form upserts today's real snapshot).

## Cleanup

Kill the server and delete screenshots/`.playwright-mcp/` before committing — the Stop hook blocks on a dirty tree.
