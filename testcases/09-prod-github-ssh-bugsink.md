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
Lint with Ruff: yes.
Custom user model: no.
Auth add-on: none.
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Add-ons:
  - redis
  - tasks: Django Tasks with the Redis Queue backend (`django-tasks-rq`)
  - analytics: Umami (self-hosted, env-driven website ID and host)
  - email: none (deliberately skip `references/email.md`; this project does not send transactional mail and the test verifies the skip path).
Production setup:
  - apply Django security settings
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

## Run

```sh
# Run from a scratch parent dir; the skill creates `09-ssh-deploy/`.
# AI executes the skill here, then:
cd 09-ssh-deploy
docker compose up -d
docker compose exec web uv run manage.py migrate
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
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
  "Audit the existing code in this directory. The following are INTENTIONAL design decisions of the seedkit skill — do NOT flag them as bugs even if they look unusual: (a) `default=... if DEBUG else None` gated defaults on SECRET_KEY / DATABASES (fail-fast in prod, zero-config in dev/build); (b) `globals().update(env.email_url(...))` is the documented django-environ idiom for spreading email settings; (c) `local.py` containing only `from .base import *` (deltas-only design; all dev defaults live in base via env vars); (d) WhiteNoise `STORAGES` configured only in `production.py`, never base (manifest storage requires collectstatic, breaks runserver); (e) `wsgi.py` / `asgi.py` defaulting to `config.settings.production` while `manage.py` defaults to `local` (intentional safety asymmetry); (f) custom user model with `username = None`, `email` as `USERNAME_FIELD`, and a custom `UserManager` when email-only auth is chosen; (g) `ACCOUNT_EMAIL_VERIFICATION = \"optional\"` in base, `\"mandatory\"` in production.py. Skip these in the report. This is a freshly generated Django *project starter / scaffold* — there is intentionally no business logic, no app code, no real content. Focus on configuration correctness, security, deployment readiness, and adherence to Django best practices for a starter. Do NOT flag the absence of feature code, app modules, or domain models. Do NOT create, generate, or modify any files — read-only review only. Do NOT invoke any skill (especially seedkit). List bugs, inconsistencies, and concrete fixes. Be brief, top issues first." \
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
