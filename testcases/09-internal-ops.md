# 09 — Production: GitHub Actions SSH deploy, Bugsink, Umami, Django Tasks (RQ)

Covers the GitHub-Actions-over-SSH deploy path, self-hosted Bugsink for error reporting, Umami analytics, Django Tasks with the Redis Queue backend, GDPR scaffolding, and CI.

## Prompt

```
/seedkit

Project name: 09-ssh-deploy
Purpose: production app deployed to a remote host over SSH from GitHub Actions, using self-hosted services.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: docker-compose (web + db + redis).
Docker structure: override (one multi-stage `Dockerfile` with `dev`/`prod` targets, `docker-compose.yml` + `docker-compose.override.yml`).
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): no.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Add-ons:
  - redis
  - tasks: Django Tasks with the Redis Queue backend (`django-tasks-rq`)
  - analytics: Umami (self-hosted, env-driven website ID and host)
  - email: none (deliberately skip `references/email.md`; this project does not send transactional mail and the test verifies the skip path).
  - CORS: no.
  - REST API: none.
  - Frontend: none.
  - Auth hardening: N/A (auth = none).
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.
  - Devcontainer: no.

Production setup:
  - apply Django security settings
  - CSP via `django-csp`: yes
  - error reporting: Bugsink (self-hosted, sentry-sdk DSN)
  - GDPR: PII scrubbing in error reports, retention defaults, user data export/delete
  - CI: GitHub Actions test workflow
  - deploy: GitHub Actions deploy via SSH (rsync + remote `docker compose pull && up -d`)
  - production Dockerfile: single-stage (small enough; multi-stage not needed)

Run the foundation + boot check locally. Generate `Dockerfile`, `docker-compose.prod.yml`, `.github/workflows/test.yml`, `.github/workflows/deploy.yml`. Do not actually deploy — verify all artifacts are present, `docker build .` succeeds, and the deploy workflow references `secrets.SSH_HOST`, `secrets.SSH_USER`, `secrets.SSH_KEY`.
```

## Expected outcome

- Local `docker compose up -d` starts web + db + redis + worker; `/admin/` login works.
- `worker` runs `manage.py rqworker default` and processes a queued task.
- Bugsink wired via `sentry-sdk` in `production.py`, DSN from env.
- Umami snippet in base template (website ID + host from env).
- GDPR scaffolding present (PII scrubber, export/delete views or commands).
- `.github/workflows/test.yml` runs migrations + pytest.
- `.github/workflows/deploy.yml` uses SSH secrets, rsyncs source, runs `docker compose pull && up -d` on the remote.
- Security settings applied only in `production.py`.
- `structlog` installed; `LOGGING` with `json` (prod) / `console` (dev) formatters; `RequestContextMiddleware` inserted into `MIDDLEWARE`; production logs are valid JSON lines carrying `request_id`.
- `axes` is **not** in `INSTALLED_APPS` and `django-axes` is **not** in dependencies — the auth-hardening follow-up must be skipped because auth = none.
- `dbbackup` is **not** in `INSTALLED_APPS` and `django-dbbackup` is **not** in dependencies — the dbbackup follow-up is gated on `deploy = vps`, and this case is `github-ssh`.
- `django-csp` installed; `csp.middleware.CSPMiddleware` only in `production.py` `MIDDLEWARE`. `CONTENT_SECURITY_POLICY['DIRECTIVES']['script-src']` resolves to include the Umami host at runtime (read from env). No `'unsafe-inline'` in `script-src`.
- `pages` app exposes `liveness` / `readiness`; `urlpatterns` wires `path('healthz', ...)` and `path('readyz', ...)`. `.github/workflows/deploy.yml` curls `/readyz` against the remote after `docker compose up -d` and fails the job on non-200.

## Run

```sh
# Run from a scratch parent dir; the skill creates `09-ssh-deploy/`.
# AI executes the skill here, then:
cd 09-ssh-deploy
docker compose up -d
docker compose exec web uv run manage.py migrate
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
# Healthchecks
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# Deploy workflow probes /readyz post-deploy
grep -q '/readyz' .github/workflows/deploy.yml
# CSP enforced in production
grep -q 'csp.middleware.CSPMiddleware' config/settings/production.py
# Auth-hardening + dbbackup are correctly gated OFF
! grep -E '^django-axes' pyproject.toml
! grep -E '^django-dbbackup' pyproject.toml
docker build -t 09-ssh-deploy:test .
grep -E 'SSH_(HOST|USER|KEY)' .github/workflows/deploy.yml
```

## Log check

Run after the boot check; the testcase is a failure if any of these print matches:

```sh
docker compose logs --tail=80 web worker db redis
! docker compose logs web worker 2>&1 | grep -iE 'traceback|^error|critical|unhandled'
docker compose logs worker 2>&1 | grep -iE 'rqworker|listening on|default'
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

Leave the code. Tear down local containers and the built image. If you actually ran the deploy workflow, SSH into the remote and `docker compose down -v` there, then revoke the deploy SSH key from `~/.ssh/authorized_keys` and the GitHub repo secrets.

```sh
docker compose down -v
docker rmi 09-ssh-deploy:test
```
