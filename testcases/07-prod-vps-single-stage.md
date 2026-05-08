# 07 — Production: VPS deploy, single-stage Dockerfile, Sentry

Covers full production path on a VPS with Caddy, single-stage Dockerfile, security settings, Sentry SaaS error reporting, GitHub Actions test CI, and Celery in prod.

## Prompt

```
/cookiecutter

Project name: 07-vps-saas
Purpose: production-ready SaaS skeleton deployed to a single VPS via docker-compose + Caddy.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: docker-compose (full stack: web + db + redis).
Lint with Ruff: yes.
Add-ons:
  - redis
  - tasks: Celery (no Beat)
  - storage: WhiteNoise (static), media volume on the VPS host
Production setup:
  - apply Django security settings (HSTS, secure cookies, X-Frame, SSL redirect)
  - error reporting: Sentry SaaS (sentry-sdk)
  - CI: GitHub Actions test workflow
  - deploy target: VPS (Docker + Caddy)
  - production Dockerfile: single-stage
Skip GDPR for this case.

Run the foundation + boot check locally. Generate `Dockerfile`, `docker-compose.prod.yml`, `Caddyfile`, `.github/workflows/test.yml`. Do not actually push to a remote VPS — just verify all artifacts are present and `docker build .` succeeds.
```

## Expected outcome

- Local `docker compose up -d` starts web + db + redis + worker, `/admin/` login works.
- Production Dockerfile is single-stage, uses `UV_COMPILE_BYTECODE=1`, `UV_LINK_MODE=copy`, two-step `uv sync`, `/app/.venv/bin` on `PATH`, runs as `django` user.
- `docker build .` succeeds; final image is non-root and has `gunicorn` on PATH.
- `Caddyfile` terminates TLS, proxies `:8000`, serves `/static/` and `/media/`.
- `docker-compose.prod.yml` has `web`, `db`, `redis`, `celery` services with `restart: unless-stopped`.
- Sentry initialised in `production.py` only, DSN from env.
- `.github/workflows/test.yml` runs migrations + pytest against Postgres.
- Security settings apply only in `production.py`.

## Run

```sh
# Run from a scratch parent dir; the skill creates `07-vps-saas/`.
# AI executes the skill here, then:
cd 07-vps-saas
docker compose up -d
docker compose exec web uv run manage.py migrate
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
docker build -t 07-vps-saas:test .
```

## Check report

_(filled in after the run)_

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:
