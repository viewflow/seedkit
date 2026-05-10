---
name: seedkit
description: Bootstrap a new Django project, or add components — auth (allauth, magic-link, axes, 2FA), payments (Stripe, dj-stripe), REST (django-modern-rest, django-bolt), Celery / django-tasks, Tailwind+DaisyUI, S3 storage, structlog, healthchecks, Docker, CI, deploy (VPS / Fly / GitHub-SSH), dbbackup, Sentry/Bugsink — to an existing Django codebase. Use whenever the user wants to scaffold Django, integrate a Django package, set up production deploys, wire CI/CD, or extend an existing Django project.
---

## How this skill works

Two paths:

- **New project** (empty dir, only `.git/` or stub README): run §2 → §6 in order.
- **Existing project** (has `pyproject.toml` and Django code): skip §2–§4. Read `references/existing-project.md` for the inventory workflow, then jump to §5/§6 and ask only about missing components.

Before either path, run `uv --version` to confirm uv is installed.

For every question that involves a third-party package: 1–2 sentences from the reference's intro on what it adds beyond stock Django, then ask. `none` (or `no`) is always a valid answer.

## Reference files

### Project Foundation

- `references/uv.md` — uv installation and commands
- `references/new-project.md` — Two Scoops layout, django-environ, uv
- `references/database.md` — SQLite vs PostgreSQL (host or Docker)
- `references/custom-user.md` — custom `AUTH_USER_MODEL` (set before first migrate)
- `references/docker.md` — local docker-compose dev + production image
- `references/existing-project.md` — inventory workflow when extending an existing repo

### Developer Experience

- `references/lint.md` — Ruff (Django-aware rules)
- `references/pytest.md` — pytest + pytest-django + coverage
- `references/typecheck.md` — pyright + django-stubs
- `references/pre-commit.md` — pre-commit hook config wiring lint / format / typecheck
- `references/devcontainer.md` — `.devcontainer/devcontainer.json` for VS Code / Codespaces / JetBrains Gateway
- `references/debug.md` — orbit / silk dispatcher
- `references/db-safety.md` — django-zeal / django-migration-linter / django-test-migrations
- `references/django-extensions.md` — `shell_plus`, `runserver_plus`, `show_urls`
- `references/logging.md` — `structlog` JSON-in-prod / pretty-in-dev

### Auth & Accounts

- `references/auth.md` — `django-allauth` or `django-mail-auth`
- `references/auth-hardening.md` — `django-axes` brute-force lockout + 2FA

### Data & Storage

- `references/redis.md` — Redis cache
- `references/storage-whitenoise.md` — static via WhiteNoise + media volume on VPS
- `references/storage-s3.md` — static + media on S3-compatible storage

### Background & Email

- `references/tasks-celery.md` — Celery + Redis
- `references/tasks-django.md` — Django Tasks dispatcher (`-db.md` / `-rq.md` / `-cron.md`)
- `references/email.md` — console / SMTP / Mailpit / anymail

### Frontend & Site Basics

- `references/tailwind.md` — Tailwind CSS standalone CLI; DaisyUI; custom 404/403/500
- `references/i18n.md` — gettext, LocaleMiddleware, makemessages
- `references/cors.md` — `django-cors-headers`
- `references/robots.md` — `robots.txt`

### SaaS / Product

- `references/rest.md` — REST API dispatcher (`-modern-rest.md` / `-bolt.md`)
- `references/billing.md` — Stripe SDK or dj-stripe
- `references/analytics.md` — dispatcher (`-goatcounter.md` / `-umami.md` / `-shynet.md` / `-ga4.md`)

### Production & Deploy

- `references/security.md` — Django security settings
- `references/csp.md` — `django-csp` Content Security Policy
- `references/healthcheck.md` — `/healthz` + `/readyz`
- `references/error-reporting.md` — Bugsink / Sentry / GlitchTip
- `references/gdpr.md` — PII scrubbing, retention, user export/delete
- `references/ci.md` — GitHub Actions test workflow
- `references/deploy-vps.md` — VPS with Docker + Caddy
- `references/deploy-managed.md` — Fly.io / Railway / Render
- `references/deploy-github-ssh.md` — GitHub Actions deploy via SSH
- `references/dbbackup.md` — `django-dbbackup` to S3-compatible target

## Instructions

### 1. Open the conversation

List the groups above, one sentence each. For existing projects: first follow `references/existing-project.md` and note what's already detected per group. Invite the user to begin.

### 2. Project Foundation — new projects only, one question at a time, in order

1. Project name + one-line purpose (the explicit two-answer pair).
2. Settings layout: single `settings.py` or split `base/local/production`.
3. Database: SQLite or PostgreSQL.
4. Local dev mode: uv on host or docker-compose.
   - Postgres + uv-on-host → host Postgres or Postgres-only in Docker.
   - docker-compose → full stack.
   - SQLite + Docker — warn the file lives in a container volume.
   - If docker-compose: ask Docker structure — `simple` (default; separate `Dockerfile.dev`) or `override` (one multi-stage `Dockerfile` + auto-loaded `docker-compose.override.yml`; recommend for serious projects). See `references/docker.md`.
5. Custom user model: yes / no — decide now (see `references/custom-user.md`).

Never bundle questions beyond the explicit pair in step 1.

### 3. Apply the foundation (new projects only)

Generate files from the matching references. `.env` `DATABASE_URL` must match DB + dev mode. If custom user = yes, apply `references/custom-user.md` **before** the boot check.

### 4. Boot check — mandatory, new projects only

Ask the user to run, in the chosen mode:

- `migrate`
- `createsuperuser` (interactive — the user runs it themselves)
- `collectstatic --noinput` only if a static-files add-on was applied

Wait for the user to confirm `/admin/` login works before continuing.

### 5. Add-ons — one group at a time, one question at a time

For new projects: ask every question. For existing projects: only ask about components not already detected in §1; confirm and skip the rest.

#### 5.1 Developer Experience

1. Ruff lint: yes / no. **Default no.**
2. Test runner: pytest or stock `manage.py test`. **Default no** (stock).
3. Type checking with pyright + django-stubs: yes / no. **Default no.**
4. Pre-commit hooks: yes / no. **Default no** — recommend yes if lint=yes; wires whichever of lint / format / typecheck were chosen.
5. Devcontainer: yes / no. **Default no.** Match the dev-mode flavour: uv-on-host or docker-compose. New projects use the answer from §2.4; existing projects detect from `Dockerfile` / `compose*.yml` (see `references/existing-project.md`).
6. Debug toolbar: `django-orbit` / `django-silk` / `none`. **Default none.**
7. DB safety: any of `django-zeal` / `django-migration-linter` / `django-test-migrations`. **Default none.** Skip `django-test-migrations` if pytest = no.
8. `django-extensions`: yes / no. **Default no.**
9. Structured logging via `structlog`: yes / no. **Default no.**

#### 5.2 Auth & Accounts

1. Auth: `django-allauth` / `django-mail-auth` / `none`. **Default none.**
2. `django-axes` brute-force lockout: yes / no. **Default yes.** Skip if auth = none.
3. 2FA: yes / no. **Default no.** Skip if auth = none. When yes: built-in `allauth.mfa` if auth = allauth (via `django-allauth[mfa]` extra — never `allauth-2fa`, which is unmaintained), else `django-otp`.

#### 5.3 Data & Storage

1. Redis cache: yes / no. **Default no.**
2. Static + media storage: `whitenoise` / `s3` / `none`. **Default none** — required before production but not for first boot.

#### 5.4 Background & Email

1. Background tasks: `celery` / `django-tasks-db` / `django-tasks-rq` / `none`. **Default none.**
2. Email backend: `console` / `smtp` / `mailpit` / `anymail` / `none`. **Always ask** — every project sends mail eventually (password resets, error reports, allauth verification).

#### 5.5 Frontend & Site Basics

1. Frontend: `tailwind` / `none`. **Default none.**
   - If tailwind: custom 404/403/500 templates? **Default no.**
   - If tailwind: DaisyUI components? **No default — always ask explicitly.**
2. i18n (gettext, LocaleMiddleware, makemessages): yes / no. **Default no** — cost of adding later is real.
3. CORS: yes / no. **Default no** — only when there's a separate frontend on a different domain.
4. `robots.txt`: yes / no. **Default no** — only for public-facing sites.

#### 5.6 SaaS / Product

1. REST API: `django-modern-rest` / `django-bolt` / `none`. **Default none.**
2. Billing: `stripe` (raw SDK) / `dj-stripe` / `none`. **Default none.**
3. Analytics: `goatcounter` / `umami` / `shynet` / `ga4` / `none`. **Default none.**

### 6. Production & Deploy — one question at a time

1. Security settings: yes / no. **Default no.**
   - If yes: Content Security Policy via `django-csp`? **Default yes.**
2. Health check endpoints (`/healthz`, `/readyz`): yes / no. **Default yes.** Apply before the deploy target so the deploy reference can wire the matching probe block in compose / `fly.toml` / nginx.
3. Error reporting: `bugsink` / `sentry` / `glitchtip` / `none`. **Default none.**
4. GDPR helpers: yes / no. **Default no.**
5. CI on GitHub Actions: yes / no. **Default no.**
6. Deploy target: `vps` / `managed` / `github-ssh` / `none`. **Default none.**
   - If `vps`: database backups via `django-dbbackup`? **Default yes.** Managed platforms have native backups, so skip for `managed` / `github-ssh`.

### 7. README

After applying any reference, append the decision and any new commands to `README.md`. Finalize at the end of the run with stack summary and key commands (install, test, migrate, run, deploy). Don't hardcode dependency versions — read them from `pyproject.toml`.

## Common pitfalls

Each rule has a *why* so you can judge edge cases.

**Snippet integrity**

- Use snippets verbatim. Don't drop lines that look obvious or redundant — `DEFAULT_AUTO_FIELD`, gated env defaults, top-level `RQ = {"JOB_CLASS": ...}`. They look optional and are not.
- The fail-fast idiom for env vars is `default=<dev-value> if DEBUG else env.NOTSET`. `env.NOTSET` raises `ImproperlyConfigured` naming the variable when the env var is missing in prod.
- Don't restate values in `local.py` / `production.py` that `base.py` already sets.
- Don't reimplement `django-environ` (no manual `.split(",")`, no leftover `import os`).

**Env vars and `.env.example`**

- Always `DJANGO_DEBUG` / `DJANGO_SECRET_KEY` / `DJANGO_ALLOWED_HOSTS` — these names are referenced across many references.
- When adding an add-on, append every env var its reference reads to `.env.example` so the file stays the canonical list.
- `.env.example` comments belong on their own lines, never trailing the value. `django-environ` reads everything after `=` verbatim, so `EMAIL_URL=consolemail://    # dev` becomes the literal URL `consolemail://    # dev` and breaks any deploy that copies the file.

**App layout**

- Don't create an app dir named after the project unless asked.
- `tasks.py` must live inside a registered Django app, not at project root or under `config/`. Both Celery autodiscovery and `django-tasks` only scan `INSTALLED_APPS`. If no app exists, create one (`uv run manage.py startapp jobs`) before placing `tasks.py`.

**After `startproject` / `uv init`**

- Set `requires-python = ">=3.12"` in `pyproject.toml` after `uv init`. Django 6 supports 3.12+; the auto-detected pin from the host interpreter is too tight.
- After inserting the env-driven `DATABASES = {...}` line in Option A of `references/new-project.md`, **delete** the original hardcoded `DATABASES` block + `# Database` comment that `startproject` emitted. Bottom wins; leaving both makes `DATABASE_URL` dead code. (Option B writes `base.py` from scratch, so this only applies to Option A.)

**Add-on scope**

- Don't add packages the user didn't ask for. `django-extensions` is an explicit add-on question — apply only if the user said yes.
