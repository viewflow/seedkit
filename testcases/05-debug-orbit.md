# 05 — django-orbit debug dashboard + Mailpit

Covers the django-orbit observability dashboard (with MCP) and the Mailpit dev mail catcher.

## Prompt

```
/cookiecutter

Project name: 05-orbit-demo
Purpose: scratch project to exercise django-orbit and verify outbound mail flows are captured.

Settings layout: single file.
Database: SQLite.
Local dev mode: uv on host.
Lint with Ruff: yes.
Add-ons:
  - debug: django-orbit (observability dashboard + MCP)
  - email: console backend in local, plus Mailpit running in Docker for richer inspection
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
```

## Check report

_(filled in after the run)_

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:
