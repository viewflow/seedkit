# Changelog

Versioned `YY.WW.D` — `date +%y.%V.%u` — year / ISO week / ISO weekday. One section per day; all of a day's commits collapse into one block. Trim to ≤ 200 lines; git keeps the rest.

## 26.20.1 — 2026-05-11

### Changed
- Bootstrap is uv-on-host only; Docker is a runtime layer (`docker.md`).
- Settings split ships `base / local / production / test.py` from day one.
- `env.NOTSET` replaces `default=None` for the prod branch across env-driven settings.
- Skill prose trimmed: positive samples replace "don't" warnings; per-reference `Docs:` links instead of usage tutorials.

### Added
- Two-phase testcase runner: build and review agents see different contexts.
- `review-logs.sh` harness that loops over per-run logs, applies short skill fixes, and rolls a daily changelog bullet.
- `seedkit-examples` sibling submodule for committable generated reference projects.
- Task runner question (`mise` / `just` / `make` / `poe`) under Developer Experience.

### Fixed
- Wait-for-services rules: `docker compose up -d --wait` rather than hand-rolled `docker compose ps --format json` polling.
- CSP middleware appends to `MIDDLEWARE`; re-declaration drops WhiteNoise.
- Sentry init lives in `production.py`, not `base.py`.
- `django-bolt` builder image: full uv bookworm + `build-essential` (no aarch64-linux wheel).
- `setup.cfg [django_migration_linter] exclude_apps` uses app labels, not INSTALLED_APPS names.
