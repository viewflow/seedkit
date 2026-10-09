# 05 — django-orbit debug dashboard + Mailpit

Covers the django-orbit observability dashboard (with MCP), Mailpit, and adding production static storage to an existing single-file project twice.

## Prompt

```
/django-seedkit

Project name: 05-orbit-demo
Purpose: scratch project to exercise django-orbit and verify outbound mail flows are captured.

Settings layout: single file.
Database: SQLite.
Lint with Ruff: yes.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: no.
Task runner: none.
Add-ons:
  - debug: django-orbit (observability dashboard + MCP)
  - email: SMTP to Mailpit running in Docker for local inspection
  - HTML email base template + `send_test_email` command: yes. Also `uv run manage.py startapp mailer`, register `mailer` in `INSTALLED_APPS`, and put the command under `mailer/management/commands/`.
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: yes.
  - robots.txt: no.
  - django-extensions: no.
  - Devcontainer: no.
Production setup: skip during the initial scaffold; the existing-project phase below adds the production image.

Run the foundation + boot check. Spin up Mailpit via a one-service `docker-compose.yml`, point Django at SMTP `localhost:1025`, send the test mail with `manage.py send_test_email`, and confirm it appears in Mailpit's UI on `:8025`. After the initial boot check, complete the existing-project extension and production checks below.
```

## Boot check

Run the checks in order. Before starting processes or services, wrap the shell blocks in a cleanup script that records child PIDs and resources created by this run and removes them on success or failure. Use a unique Compose project name. For host Postgres, reuse only a database created during this case's foundation step; fail if an unrelated database already has the requested name. Later acceptance subsections run from this project's root.

```sh
set -eu
cd 05-orbit-demo
docker compose up -d --wait mailpit
uv run manage.py migrate
uv run manage.py runserver --noreload &
RUNSERVER_PID=$!
up=
for i in 1 2 3 4 5; do curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null && up=1 && break; sleep 1; done
[ -n "${up:-}" ] || { echo "BOOT CHECK FAILED: runserver never came up"; kill "$RUNSERVER_PID"; exit 1; }
curl -sf http://127.0.0.1:8000/orbit/ > /dev/null
curl -sf http://127.0.0.1:8025/ > /dev/null
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# Send the test mail (text + HTML alternative) and verify Mailpit captured it.
uv run manage.py send_test_email to@example.com
sleep 1
TOTAL=$(curl -sf http://127.0.0.1:8025/api/v1/messages | python3 -c 'import json,sys; print(json.load(sys.stdin)["total"])')
test "$TOTAL" -ge 1
uv run ruff check .
if docker compose logs mailpit 2>&1 | grep -iE 'fatal|panic'; then
  echo "SMOKE CHECK FAILED: forbidden configuration or error output" >&2
  exit 1
fi
kill "$RUNSERVER_PID"
docker compose down -v --rmi local
```

### Existing-project extension and repeat pass

Keep this project and its database; do not scaffold a replacement. Seed a non-superuser account with a unique username, and record its primary key and password hash. Save hashes of the existing `mailer/` source, email templates, `.env`, and `AGENTS.md`/`CLAUDE.md`, plus the current README text, in a temporary directory. Do not print secrets.

Apply this follow-up request to the existing project:

> Add WhiteNoise static storage and a multi-stage production Dockerfile. Keep single-file settings, Orbit and Mailpit for development, and the existing email command. Add no other packages or features. Keep the existing README content and append the new commands.

After the change, verify the saved files and account are unchanged, and the old README remains intact. Run the original boot checks again, including delivery to Mailpit. Capture the resulting source/configuration file hashes (excluding runtime files, caches, and the database). Repeat the same follow-up request, then assert those files are unchanged: no duplicated middleware, settings blocks, dependencies, URLs, or README sections. Run `uv run manage.py check` and the stock test suite again. Keep the comparison inside this project; do not use Git or inspect sibling projects.

### Production acceptance

From the project root, build the final image and exercise the single-file settings path with `DEBUG=False`:

```sh
set -eu
docker build --target prod -t 05-orbit-demo:smoke .
docker run --rm --entrypoint python \
  -e DJANGO_SETTINGS_MODULE=config.settings -e DJANGO_DEBUG=False \
  -e DJANGO_SECRET_KEY=smoke-only-secret-key-padding-to-fifty-characters-123456 \
  -e DJANGO_ALLOWED_HOSTS=localhost -e DATABASE_URL=sqlite:////tmp/smoke.sqlite3 \
  -e DJANGO_MAIL_HOST=localhost -e DEFAULT_FROM_EMAIL=test@example.com \
  -e SERVER_EMAIL=test@example.com \
  05-orbit-demo:smoke manage.py check
```

Also start the image's default Gunicorn command on a dynamically allocated loopback port using the same test environment. Poll `/healthz` with a bounded deadline, then fetch a collected admin CSS asset through WhiteNoise and require status 200 with a CSS content type. Run this check from the built image without installing dev dependencies. Register cleanup before starting containers; remove only this run's containers and image on success or failure.

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `manage.py`, `config/settings.py`, `config/urls.py`, `docker-compose.yml`, `.env`, `.env.example`, `.gitignore`.
- `pyproject.toml` runtime deps include `django-environ`. Dev deps include `django-orbit[mcp]`, `ruff`. `[tool.ruff]` block present.
- `docker-compose.yml` defines a single `mailpit` service exposing 1025 (SMTP) and 8025 (UI) on localhost.
- `config/settings.py` configures the development mailer with the SMTP backend using `host="localhost"` and `port=1025` (uv-on-host hits the published port, not the Docker hostname).

**Settings**
- `config/settings.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- `MAILERS["default"]` uses the Mailpit SMTP backend in development; `DEFAULT_FROM_EMAIL` and `SERVER_EMAIL` use the gated-default idiom.
- `LOGGING` is at module scope (NOT inside `if DEBUG:`); `if DEBUG:` block only appends the orbit handler.
- `if DEBUG:` block adds `"orbit"` to `INSTALLED_APPS` and inserts `"orbit.middleware.OrbitMiddleware"` at MIDDLEWARE index 1 (after `SecurityMiddleware`, not before).

**HTML email**
- Files present: `templates/email/base.html` (table layout, inline `style=` attributes, `{% block content %}`), `templates/email/test.html` (extends `email/base.html`), `mailer/management/commands/send_test_email.py`.
- The command builds `EmailMultiAlternatives` and calls `attach_alternative(..., "text/html")` — not `send_mail`.
- `templates/email/base.html` contains no Tailwind utility classes and no `<style>` block.

**URLs + health**
- `config/urls.py` mounts `orbit.urls` only when `settings.DEBUG`.
- `pages/views.py` (or equivalent) defines `liveness` / `readiness`. `path('healthz', ...)` and `path('readyz', ...)` in `urlpatterns` (no trailing slash).

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks. Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
