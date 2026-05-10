# 01 — Minimal example

Smallest path that boots a working Django project. Baseline — if this fails, everything else is moot.

## Prompt

```
/seedkit

Project name: 01-minimal-blog
Purpose: a tiny blog to verify the skill works end-to-end.

Settings layout: single file (`config/settings.py`).
Database: SQLite.
Local dev mode: uv on host.
Lint with Ruff: no.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none (vanilla `django.contrib.auth`).
Structured logging: no.
Add-ons:
  - email: console backend (`EMAIL_URL=consolemail://`).
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: no (this case is the bare floor — no extra views).
  - robots.txt: no.
  - django-extensions: no.
  - Devcontainer: no.

Production setup: skip.

Run the foundation, the boot check (migrate + createsuperuser), and confirm /admin/ login works.
```

## Expected outcome

- `uv run manage.py runserver` boots without errors.
- `/admin/` renders and the superuser can log in.
- Files present: `pyproject.toml`, `uv.lock`, `manage.py`, `config/settings.py`, `db.sqlite3`, `.env`, `.gitignore`.
- No Docker, no Postgres deps, no Ruff config.

## Run

```sh
# Run from a scratch parent dir; the skill creates `01-minimal-blog/` via `uv init`.
# AI executes the skill here, then:
cd 01-minimal-blog
uv run manage.py runserver &
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
kill $(jobs -p) 2>/dev/null; pkill -f 'manage.py' 2>/dev/null; wait
```

## Check report

**Execute this command yourself before stopping. Do not present it as a "next step" for the user — the testcase isn't done until the review file exists.** It runs an independent review (the model that built the project shouldn't grade its own output) and writes the result to `REVIEW.md` in the project dir.

```sh
claude -p \
  --model claude-opus-4-7 \
  --allowedTools "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*)" \
  "Read-only audit of this directory. Generated runtime artifacts (`.env`, local DB files, `__pycache__/`, `staticfiles/`) are expected. The starter has no business logic and no production hardening beyond what the prompt requested — out of scope. Report only issues that (i) prevent the scaffold from booting, (ii) make one of the smoke checks above fail, or (iii) are an outright security hole. Every claim must quote the file path and the literal substring you read; do not infer state from training-data priors. Skip nitpicks (docstrings, style, hypothetical scaling, 'consider adding X'). Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for — a starter scaffold is supposed to be small. If unsure whether something is a real bug right now, omit it. If you patched something during this run, list it under 'Fixes applied', not 'Bugs'. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; 'No issues found.' is a valid report." \
  | tee REVIEW.md
```

Paste the output below.

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:

## Cleanup

Leave the code in place; no external resources to remove (SQLite file lives inside the project dir).
