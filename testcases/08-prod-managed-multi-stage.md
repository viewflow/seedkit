# 08 — Production: Fly.io managed deploy, multi-stage Dockerfile, GlitchTip, GDPR, GA4

Covers managed-platform deployment with a slim multi-stage image, S3 storage, GA4 analytics, GlitchTip error reporting, GDPR scaffolding, and CI.

## Prompt

```
/cookiecutter

Project name: 08-fly-app
Purpose: production app deployed to Fly.io with a slim multi-stage runtime image and S3-compatible object storage.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: docker-compose (web + db + redis + minio).
Lint with Ruff: yes.
Custom user model: no.
Auth add-on: `django-mail-auth` (passwordless magic-link).
Add-ons:
  - redis
  - tasks: Celery
  - storage: S3-compatible (MinIO locally, real S3 in prod)
  - analytics: Google Analytics 4 (GA4)
Production setup:
  - apply Django security settings
  - error reporting: GlitchTip via sentry-sdk
  - GDPR: PII scrubbing in error reports, retention defaults, user data export/delete views
  - CI: GitHub Actions test workflow
  - deploy target: Fly.io managed (use `[processes]` for web + worker)
  - production Dockerfile: multi-stage (builder + slim runtime)

Run the foundation + boot check locally. Generate `Dockerfile`, `fly.toml`, `.github/workflows/test.yml`. Verify `docker build .` succeeds and the runtime stage uses `python:3.12-slim-bookworm`.
```

## Expected outcome

- Local `docker compose up -d` starts web + db + redis + worker + minio; `/admin/` login works.
- Production Dockerfile has two stages: `builder` (uv image) → `runtime` (`python:3.12-slim-bookworm`); only `/app/.venv` and project source copied into runtime.
- `docker build .` succeeds; final image notably smaller than 07 (`docker images` size diff).
- `fly.toml` has `[processes]` with `web = "gunicorn ..."` and `worker = "celery ..."`.
- GlitchTip wired via `sentry-sdk` in `production.py`, DSN from env.
- GDPR scaffolding present: `before_send` PII scrubber, `data_export` / `data_delete` views or management commands.
- GA4 snippet in base template, measurement ID from env.
- Security settings + CI workflow present.
- `django-mail-auth` installed; `mailauth` in `INSTALLED_APPS`; `MailAuthBackend` in `AUTHENTICATION_BACKENDS`; `accounts/` URL include with `mailauth` namespace; `/accounts/login/` renders an email-only form.

## Run

```sh
# Run from a scratch parent dir; the skill creates `08-fly-app/`.
# AI executes the skill here, then:
cd 08-fly-app
docker compose up -d
docker compose exec web uv run manage.py migrate
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
docker build -t 08-fly-app:test .
docker images 08-fly-app:test
```

## Check report

**Execute this command yourself before stopping. Do not present it as a "next step" for the user — the testcase isn't done until the review file exists.** It runs an independent review (the model that built the project shouldn't grade its own output) and writes the result to `REVIEW.md` in the project dir.

```sh
claude -p \
  --model claude-opus-4-7 \
  --allowedTools "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*)" \
  "Audit the existing code in this directory. This is a freshly generated Django *project starter / scaffold* — there is intentionally no business logic, no app code, no real content. Focus on configuration correctness, security, deployment readiness, and adherence to Django best practices for a starter. Do NOT flag the absence of feature code, app modules, or domain models. Do NOT create, generate, or modify any files — read-only review only. Do NOT invoke any skill (especially cookiecutter). List bugs, inconsistencies, and concrete fixes. Be brief, top issues first." \
  | tee REVIEW.md
```

Paste the output below.

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:

## Cleanup

Leave the code. Tear down local containers and the built image. If you ran `flyctl launch` for real, also `fly apps destroy 08-fly-app` and revoke any tokens; otherwise nothing to undo on Fly.io.

```sh
docker compose down -v
docker rmi 08-fly-app:test
```
