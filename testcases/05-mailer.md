# 05 — django-orbit debug dashboard + Mailpit

Covers the django-orbit observability dashboard (with MCP) and the Mailpit dev mail catcher.

## Prompt

```
/seedkit

Project name: 05-orbit-demo
Purpose: scratch project to exercise django-orbit and verify outbound mail flows are captured.

Settings layout: single file.
Database: SQLite.
Local dev mode: uv on host.
Lint with Ruff: yes.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: no.
Add-ons:
  - debug: django-orbit (observability dashboard + MCP)
  - email: console backend in local, plus Mailpit running in Docker for richer inspection
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: yes.
  - robots.txt: no.
  - django-extensions: no.
  - Devcontainer: no.
Run the foundation + boot check. Spin up Mailpit via a one-service `docker-compose.yml`, point Django at SMTP `localhost:1025`, send a test mail, and confirm it appears in Mailpit's UI on `:8025`.
```

## Expected outcome

- `uv run manage.py runserver` boots; `/admin/` login works.
- `django-orbit` installed and visible at its mounted URL; MCP endpoint responds.
- `docker compose up -d mailpit` runs; sending a mail through `EmailMessage(...).send()` shows up in Mailpit UI.
- Ruff config present; `uv run ruff check .` exits 0.

## Run

```sh
# Run from a scratch parent dir; the skill creates `05-orbit-demo/`.
# AI executes the skill here, then:
cd 05-orbit-demo
docker compose up -d mailpit
uv run manage.py runserver &
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
curl -sf http://127.0.0.1:8025/ > /dev/null
# send a test mail via shell, check Mailpit JSON API for receipt
kill $(jobs -p) 2>/dev/null; pkill -f 'manage.py' 2>/dev/null; wait
```

## Log check

Run after the boot check; the testcase is a failure if any of these print matches:

```sh
docker compose logs --tail=30 mailpit
! docker compose logs mailpit 2>&1 | grep -iE 'fatal|panic'
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

Leave the code. Tear down the Mailpit container:

```sh
docker compose down -v
```
