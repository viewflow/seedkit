# Changelog

Versioned `YY.WW.D` — `date +%y.%V.%u` — year / ISO week / ISO weekday. One section per day; all of a day's commits collapse into one block. Trim to ≤ 200 lines; git keeps the rest.

## 26.29.6 — 2026-07-18

### Changed
- Review §4 missing-pieces sweep (REVIEW.md 2026-07-18): `error-reporting.md` gains a Background workers section — verified against sentry-sdk source that Celery/RQ integrations auto-enable and ERROR-level logs (which `django-tasks` workers emit on task failure, via the built-in `task_finished` receiver) become events, so the fix is documentation + a post-deploy check, not wiring; `gdpr.md` export now strips `password` and internal auth fields from the dump handed to the data subject, and deletion notes the required `stripe.Customer.delete` when billing is wired; `custom-user.md` email variant lowercases email in the manager and adds a `UniqueConstraint(Lower("email"))` backstop; `tasks-django-db.md` schedules `prune_db_task_results --min-age-days 14` (result rows otherwise grow forever — command verified in django-tasks-db source); `tasks-django-rq.md` documents the failed-job registry (`rq info --url "$REDIS_URL/3"`, requeue after fixing); `dbbackup.md` drops `mediabackup` when media is on S3 in favor of bucket versioning; `storage-s3.md` sets `AWS_S3_OBJECT_PARAMETERS` Cache-Control, notes media-bucket versioning, and its VPS deploy script gains the mandatory `--env-file`; `rest.md` states neither REST lib ships auth / rate limiting / pagination enabled — wire all three before a public deploy.
- Review §3 deploy-pipeline sweep (REVIEW.md 2026-07-18): `deploy-github-ssh.md` gates deploys on green tests (a `test` job running `test.yml` via `workflow_call`, `deploy` gets `needs: test`), pushes a `:<sha>` tag alongside `:latest`, parameterizes the compose image as `ghcr.io/${GITHUB_REPOSITORY}:${IMAGE_TAG:-latest}` with the deploy script exporting the commit SHA, and gains a `## Rollback` section (pull + `up -d` a known-good SHA; destructive migrations reversed explicitly); `ci.md` filters `push:` to `[main]` (kills the double PR run), adds the `workflow_call` trigger and a `makemigrations --check --dry-run` step, and drops the false "setup-uv releases are immutable" claim; `dev-tasks.md` deploy tasks in all four runners now carry `--env-file deploy/.env.prod` (required for compose interpolation of `${GITHUB_REPOSITORY}`), and the Makefile `.PHONY` line covers the deploy targets; `pytest.md` omits `.venv/**` from coverage and drops the scaffold-time `fail_under = 80` gate in favor of a set-it-when-real-code-exists note.
- Review §2 vertical-scaling sweep (REVIEW.md 2026-07-18): gunicorn `CMD` gains `--max-requests 1000` + jitter and `--access-logfile -`, with worker count driven by `WEB_CONCURRENCY` (gunicorn reads it natively; without it prod ran **1 sync worker**) — `docker.md`, `async.md` (both CMD variants, `GUNICORN_CMD_ARGS` snippet replaced), `database.md` Litestream entrypoint, `deploy-github-ssh.md` `.env.prod.example`; `redis.md` prod service gains a `redis_data` volume + `--appendonly yes` (queued Celery/RQ jobs survive restarts) and `--maxmemory … volatile-lru` (evicts only TTL'd cache keys, never broker keys); `deploy-vps.md` compose gains an `x-logging` anchor (json-file 10m×3 — unbounded logs fill the VPS disk) applied across all prod service fragments, a Postgres `shared_buffers` tuning pointer, Caddy `encode zstd gzip` + `request_body max_size 10MB` in both Caddyfile variants, `docker image prune -f` after deploy (also in `deploy-github-ssh.md`, prune-on-healthy only), a healthcheck comment tying the localhost probe to `DJANGO_ALLOWED_HOSTS`, and a sentence stating the few-seconds deploy blip; `tasks-celery.md` adds `CELERY_TASK_TIME_LIMIT`/`SOFT_TIME_LIMIT`, a `celery inspect ping` healthcheck on the worker service, and the Beat example path now targets `{app_label}.tasks` (a registered app) instead of the nonexistent `{project_slug}` module.

### Fixed
- Review §1 boot-blocker sweep (REVIEW.md 2026-07-18): `storage-whitenoise.md` replaces its broken Caddy media block (no prefix strip → every `/media/*` 404s) with a cross-reference to the canonical block in `deploy-vps.md`, whose prose now matches the named-volume mount (`media:/srv/media:ro`); `auth-hardening.md` restores the AND-form `AXES_LOCKOUT_PARAMETERS = [['ip_address', 'username']]` (flat list = username-lockout DoS / proxy-IP mass lockout — regression of the 26.27.6 fix), replaces the stale IPWARE pitfall with `django-axes[ipware]` + `AXES_IPWARE_*` settings for the Caddy-in-Docker path, and drops the false "forces 2FA in prod" comment (no such allauth setting); `billing.md` handles `customer.subscription.updated` with status-derived access (`active`/`trialing`) so payment failures revoke access; `csp.md`'s report-only rollout is now a real standalone `CONTENT_SECURITY_POLICY_REPORT_ONLY` dict replacing (not coexisting with) the enforcing setting; `tasks-django-cron.md` imports `from django_tasks import task` (backport, matching the db/rq siblings) and points Docs at the real repo `codingjoe/django-crontask`; `realtime.md` prefixes the dev uvicorn command with `DJANGO_SETTINGS_MODULE=config.settings.local` (asgi.py defaults to production) and wraps the WS test around `URLRouter` directly so the injected `scope["user"]` survives connect; `storage-s3.md` quotes `'django-storages[s3]'` (zsh globs brackets); `dev-tasks.md` poe tasks call `python manage.py …` and the `deploy-migrate` table row drops the in-container `uv run`; `rest-bolt.md`'s boot check polls with the PID-recorded `break`/`kill` idiom instead of `sleep 1` + bare curl.

## 26.28.2 — 2026-07-07

### Changed
- `rest-bolt.md` / `docker.md`: django-bolt Docker builds now pin `--platform=linux/amd64` on both stages so uv installs the published `manylinux2014_x86_64` wheel — no `build-essential`, no from-source Rust compile, and the image matches Fly's default amd64 machines. Replaces the old arm64-native compile-from-source guidance.

### Fixed
- `deploy-managed.md`: `fly.toml` example gained a `[[services.http_checks]]` block hitting `/readyz` (so Fly gates rollouts on readiness) and a note to bind the HTTP service to the `web` process (`processes = ["web"]`) when `[processes]` is set — the previous example was single-process with no health check.

## 26.28.1 — 2026-07-06

### Fixed
- `tasks-django-rq.md` / `tasks-django-db.md`: both 0.12.0 adapters are built against the standalone `django-tasks` backport (import `django_tasks`), not Django 6's stdlib `django.tasks` — register `django_tasks`, import `from django_tasks import task`, and use `django_tasks.backends.immediate.ImmediateBackend` as the test eager backend.
- `dev-tools.md`: `lintmigrations` `exclude_apps` used the wrong label `django_tasks_database`; the app label is `django_tasks_db`, so its migrations weren't skipped.
- `SKILL.md`: `startapp` ordering pitfall now also covers packages a settings block references (e.g. `orbit.handlers.OrbitLogHandler`) — `uv add` them before the next `startapp` imports settings.
- `ci.md`: CI `DJANGO_SECRET_KEY` placeholder dropped the `django-insecure-` prefix — that prefix trips `security.W009` at the `check --deploy` step regardless of length.

## 26.27.7 — 2026-07-05

### Added
- `seo.md` — meta/OG tags block for `base.html` + `django.contrib.sitemaps` wiring; defines the `SITEMAP_URL` that `robots.md`'s view already consumed. New §5.5 question (default no, skipped when Frontend = none).
- `favicon.md` — agent-drawn SVG favicon matching the project (initial/motif + theme colors), PNG fallbacks via `rsvg-convert`/`sips` when available (ImageMagick excluded — stock builds can't rasterize SVG `<text>`). Follow-up under Frontend, default yes with Tailwind.
- `email.md` gains an HTML email base template (table layout, inline styles) + `send_test_email` management command; follow-up under the email-backend question, default no. Testcase 05 exercises it end-to-end via Mailpit.
- SKILL.md §8: new-project runs now emit `AGENTS.md` (stack decisions, layout, key commands) plus a one-line `CLAUDE.md` (`@AGENTS.md`) so coding agents pick up project context.

### Fixed
- `ci.md`'s placeholder `DJANGO_SECRET_KEY` is now 50+ chars — the old `test-key` tripped `security.W009` at the workflow's own `check --deploy --fail-level WARNING` step.
- `pytest.md` seeds a smoke test per touched app — a project shipping only empty `startapp` stubs makes `pytest` exit 5 ("no tests collected"), turning CI red on first push. `dev-tasks.md` skips `deploy-migrate` for the SQLite + Litestream deploy (migrate runs in `entrypoint.sh`), so `deploy` is a bare `up -d`.
- Testcase 01 boot check no longer races: `runserver --noreload` + a `curl` poll loop, matching SKILL.md §4 (bare `runserver &` + one immediate `curl` fired before the WSGI listener was up).
- `dev-tools.md` drops the `silk_profile`-inside-a-`@task`-body example — Silk only records within a request-scoped `DataCollector`, so it silently no-ops in a worker; profile from a request-scoped view instead.
- `deploy-github-ssh.md` points the inherited compose `web` image at `ghcr.io/${GITHUB_REPOSITORY}:latest` — the CI-built tag — instead of the scaffold-time `{owner}/{project_slug}` placeholder that shipped a literal `{owner}` and broke `compose pull`.

## 26.27.6 — 2026-07-04

### Fixed
- seedkit-slim wrong correctives (REVIEW.md Part II, verified against installed packages): `django-modern-rest.md` rewritten around the real API — import name `dmr`, no `INSTALLED_APPS` entry, `dmr.routing.Router` + `Controller.as_view()` (the previous `modern_rest` module / `router.register` didn't exist); `django-zeal.md` drops the nonexistent `ZEAL_RAISE_ON_VIOLATION` (raising is `ZEAL_RAISE`'s default); `django-allauth.md` drops the `allauth.mfa.urls` include (auto-mounted at `accounts/2fa/`) and the optional `django.contrib.sites`/`SITE_ID`; `new-project.md` gates `ALLOWED_HOSTS` with `env.NOTSET` and compresses the root-URL section; `django-axes.md` uses the AND-form `[['ip_address', 'username']]` (flat list = username-lockout DoS), notes the allauth `login`-field gap and `[ipware]` behind proxies, drops LLM-known lines.

- REVIEW.md blockers: `email.md` anymail path relaxes the `EMAIL_URL` gate to an unconditional default (prod no longer sets the var — the `env.NOTSET` branch crashed boot); `billing.md` dj-stripe rewritten for 2.9+ (webhook endpoints are admin-created DB rows with UUID URLs — `DJSTRIPE_WEBHOOK_SECRET` and `DJSTRIPE_FOREIGN_KEY_TO_FIELD` dropped, `djstripe_receiver` replaces `WEBHOOK_SIGNALS`, checkout view sets `stripe.api_key` from `djstripe_settings`); `deploy-vps.md` deploy commands carry `--env-file deploy/.env.prod`; `dbbackup.md` cron lines get cwd + compose flags + a real host user + log redirect, restore commands get the same flags, pitfall notes pg_dump client ≥ server major; `i18n.md` installs `gettext` in the builder stage (`msgfmt` missing broke the image build) and on the dev host; `realtime.md` WS test sends an `Origin` header so `AllowedHostsOriginValidator` accepts the handshake; `async.md` pitfall drops the nonexistent `Model.objects.afilter(...)`.
- `typecheck.md` — `reportGeneralTypeIssues` / `reportOptionalMemberAccess` no longer downgraded to warnings (warnings never fail pyright's exit code, so CI passed on type errors). Verified 0 errors at error level across four generated example projects; django-stubs kept over django-types (whose stubs lack `UserChangeForm.Meta` and `django.tasks`).

### Added
- seedkit-slim anti-prior references where LLM priors are verifiably wrong: `dj-stripe.md` (2.9+ DB-row webhook endpoints, `djstripe_receiver`, SDK global not set), `deploy-pitfalls.md` (compose `--env-file`, pg_dump client ≥ server major, json-file log rotation, cron cwd/user/log traps); `csp.md` replaces `django-csp.md` — Django ≥ 6.0 ships CSP in core (`SECURE_CSP`, core middleware, `{{ csp_nonce }}`), don't install django-csp. SKILL.md: asgi modes use `uvicorn_worker.UvicornWorker`; deploy step reads deploy-pitfalls first.

### Changed
- Version refresh (all pins verified current 2026-07-04): base images `bookworm`/3.12 → `trixie`/3.13 across docker / rest-bolt / devcontainer / prose (trixie's `postgresql-client` 17 also fixes the pg_dump mismatch against `postgres:17`); `redis:7` → `redis:8`; Litestream 0.3.13 → 0.5.13 (new asset naming `linux-x86_64`, singular `replica:` config); `uvicorn.workers.UvicornWorker` (deprecated) → `uvicorn-worker` package; `checkout@v7`, `setup-uv@v8.2.0` (immutable — pin exact), `build-push-action@v7`, `codecov-action@v7`, `appleboy/ssh-action` SHA-pin placeholder; pre-commit revs bumped + `ruff` hook id → `ruff-check` + "run `pre-commit autoupdate` after writing the config"; DaisyUI downloads pinned to a versioned release URL; Tailwind CLI example 4.3.2; python pins 3.12 → 3.13 (mise, uv examples). New SKILL.md "Version pins" pitfall: resolve current releases at generation time instead of trusting reference pins.

## 26.21.1 — 2026-05-18

### Fixed
- `references/rest-bolt.md` — document all three `runbolt` discovery paths (explicit `BOLT_API`, project-level `config/api.py`, per-app). Default to project-level so an `api/` app isn't auto-created for stateless API surfaces; per-app stays the right choice once the API grows models/admin/migrations.

## 26.20.5 — 2026-05-15

### Fixed
- `testcases/04-media-vault.md` — align assertions with the storage-s3 reference: drop the stale `.dockerignore` requirement (deploy=none has no Dockerfile) and rename the expected MinIO volume `minio-data` → `miniodata`.
- `references/analytics.md` + `references/csp.md` — GA4 inline init `<script>` carries `nonce="{{ request.csp_nonce }}"` so the snippet survives the CSP policy (no `'unsafe-inline'` in `script-src`).
- `references/ci.md` — list `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `DBBACKUP_BUCKET` placeholders so `check --deploy` against `production` doesn't crash when `django-dbbackup` is wired. `testcases/09-internal-ops.md` CI env assertion updated to match (dropped stray `EMAIL_URL` requirement for the email=none path).
- `references/docker.md` + `references/storage-s3.md` + `references/email.md` — clean up `npx dclint` on the dev compose: add `name:` placeholder, reorder service keys to `image → volumes → environment → ports → command → healthcheck`, bind MinIO `9000`/`9001` to `127.0.0.1`, sort Mailpit ports alphabetically. `minio/minio` and `axllent/mailpit` stay on `:latest` — dev-only services, pin churn not worth it.

## 26.20.3 — 2026-05-13

### Added
- `skills/seedkit-slim/references/django-allauth.md` — modern `ACCOUNT_LOGIN_METHODS` / `ACCOUNT_SIGNUP_FIELDS` keys (allauth 0.65+) plus URL wiring for `allauth.mfa.urls`. Slim runs were emitting deprecated `ACCOUNT_AUTHENTICATION_METHOD` / `ACCOUNT_EMAIL_REQUIRED` / `ACCOUNT_USERNAME_REQUIRED` and getting startup warnings.
- `skills/seedkit-slim/references/new-project.md` — foundation snippets for §1 (settings with `DJANGO_*` env vars + `env.NOTSET` prod guards, `/` → `/admin/` redirect in `config/urls.py`, `.gitignore` contents, `django>=6.0,<7.0` pin, boot check using `--noreload`). Slim runs were missing all of these.
- `skills/seedkit-slim/references/django-mail-auth.md` — app label is `mailauth` (not `mail_auth`), backend `mailauth.backends.MailAuthBackend`, requires `django.contrib.sites` + `SITE_ID`, and ships no templates — `registration/login.html` + `registration/login_requested.html` must be scaffolded or `accounts/login/` returns 500.
- `skills/seedkit-slim/references/django-tasks-rq.md` — backend module is `django_tasks_rq.backend` (singular), `django_rq` must be in `INSTALLED_APPS` for its migrations, plus the `RQ = {"JOB_CLASS": "django_tasks_rq.Job"}` setting.
- `skills/seedkit-slim/references/django-modern-rest.md` — `pyjwt` is an implicit dep (imported unconditionally) and router-mount wiring for `config/urls.py`.
- `skills/seedkit-slim/references/pyright.md` — `djangoSettingsModule` belongs under `[tool.django-stubs]`, not `[tool.pyright]`; channels `as_asgi()` needs `# type: ignore[arg-type]` in `path()`.
- `skills/seedkit-slim/references/django-orbit.md` and `references/mailpit.md` — debug-only gating for orbit (app, middleware at index 1, URL mount, logging handler all inside `if DEBUG:`) and Mailpit compose with loopback-only port binds + `EMAIL_URL` wiring. Without these the slim agent shipped orbit in INSTALLED_APPS unconditionally and bound 1025/8025 to all interfaces.
- `skills/seedkit-slim/references/django-tasks-db.md`, `django-zeal.md`, `django-migration-linter.md` — DB backend ships as the separate `django-tasks-db` package (`django_tasks_db.backend.DatabaseBackend`); zeal 2.x middleware is the lowercase function `zeal.middleware.zeal_middleware`; `lintmigrations` needs `django_migration_linter` in `INSTALLED_APPS` plus `MIGRATION_LINTER_OPTIONS.exclude_apps` for third-party migrations.
- `skills/seedkit-slim/references/healthcheck.md`, `django-axes.md`, `django-bolt.md` — trivial `/healthz` + `/readyz` views (avoid pulling `django-health-check`, whose v4 `INSTALLED_APPS` shape broke slim runs); axes v8 wiring without the removed `AXES_LOCKOUT_CALLABLE`; bolt `urls_bolt.py` needs `urlpatterns: list = []` and the builder stage needs `build-essential pkg-config` for the aarch64-linux source build. `pyright.md` notes `user.pk` (django-stubs has no `User.id`).

### Changed
- `new-project.md` directs dev tools through `uv add --group dev` (PEP 735 `[dependency-groups]`). The old `[tool.uv] dev-dependencies` table is deprecated in uv 0.11+.
- `new-project.md` runs `uv python pin 3.12` right after `uv init --bare` so the project doesn't inherit a host 3.14 prerelease.

### Added
- `skills/seedkit-slim/references/django-csp.md` — django-csp 4.0+ uses the nested `CONTENT_SECURITY_POLICY = {"DIRECTIVES": {…}}` shape; the legacy flat `CSP_*` keys raise `csp.E001` at startup.

### Fixed
- `django-tasks-db.md` backend path is `django_tasks_db.DatabaseBackend` (no `.backend.` infix) — the previous snippet raised `ImportError` on boot.
- `new-project.md` boot check runs `makemigrations` before the first `migrate` so the §1.6 custom `AUTH_USER_MODEL` doesn't abort the initial `migrate`.
- `new-project.md` appends `[tool.uv] package = false` to `pyproject.toml` right after `uv init --bare`. Django apps aren't installable; without this, `uv sync` invoked hatchling and failed mid-foundation.
- `new-project.md` settings snippet guards `environ.Env.read_env()` with `if _env_file.exists()`. Docker images have no `.env` and bare `read_env()` raised `FileNotFoundError` during `collectstatic`.

### Changed
- Testcase Prompt blocks no longer name specific reference files for the agent to read (`references/docker.md`, `references/realtime.md`, `references/database.md`, `references/email.md`). The skill picks references itself; prompts only state the requirement. Touched 02-shop, 03-jobs-board, 04-media-vault, 07-saas, 09-internal-ops.

## 26.20.2 — 2026-05-12

### Added
- `skills/seedkit-slim/SKILL.md` — slim questionnaire-only variant. Same groups, package names, and defaults as the full skill; no references, no snippets, no procedural guidance. For runs where the model already knows how to wire each package and only needs requirements gathered.

### Changed
- Testcases (01-09) and `testcases/README.md` aligned with the new model: no `Dockerfile.dev`, no dev `web` / `worker` compose services, no `simple` / `override` Docker-structure choice. Cases that previously picked docker-compose dev (04 media-vault, 07 saas, 08 startup, 09 internal-ops) now run Django + workers on the host via `uv run …` and use `docker-compose.yml` for local services only (`db`, `redis`, `minio`, `mailpit`). 04's devcontainer assertion switched to the uv-on-host shape (Python image + uv feature + `${containerWorkspaceFolder}/.venv/bin/python`). 07's prod Dockerfile is now multi-stage (was single-stage); managed-deploy `release_command` and SSH deploy `worker` snippet use `python manage.py …` (no `uv run` in the slim runtime). Coverage rules in `testcases/README.md` drop the "Local dev mode" dimension.
- Dev mode is always uv-on-host — `SKILL.md` no longer asks "uv on host vs docker-compose" or "Docker structure simple/override". `docker.md` rewritten around a single production multi-stage Dockerfile (uv builder → `python:3.12-slim-bookworm` runtime) and a slim local-services `docker-compose.yml` (Postgres / Redis / Mailpit / MinIO only — never a `web` service). Workers (`tasks-celery.md`, `tasks-django-{db,rq,cron}.md`) run on the host alongside `manage.py runserver` via `uv run …`. `devcontainer.md` collapses to the uv-on-host flavour. `database.md` Variant C ("full stack in docker-compose") removed. `redis.md` local block publishes `127.0.0.1:6379`; `realtime.md` local section runs uvicorn on the host. `existing-project.md` detection drops the `simple` / `override` dev-mode flavour.
- `SKILL.md` Common pitfalls now carries the central rule: `uv run …` on the host, `python …` inside any container — the runtime slim image has no `uv` binary.
- Testcase boot-check cleanup drops `pkill -f 'manage.py'` — contradicted the `SKILL.md` rule against `pkill -f` and the harness already sweeps the process group.

### Fixed
- `database.md` Litestream Dockerfile snippet now bakes `litestream.yml` + `entrypoint.sh` into the image (with `ENTRYPOINT`/`CMD`) instead of leaving the entrypoint's `/etc/litestream.yml` path dangling for a compose bind-mount that silently failed when the config sat at the project root.
- `ci.md` env block calls out that `DATABASE_URL` must stay set regardless of DB choice and shows the SQLite alternative inline — agents adapting the Postgres snippet were dropping the var entirely and tripping the `DEBUG=False` `env.NOTSET` branch on import. Same block now lists opt-in `POSTMARK_SERVER_TOKEN` / `ANYMAIL_WEBHOOK_SECRET` placeholders for projects wiring `django-anymail`, which otherwise tripped the same gated-import branch in `manage.py check --deploy` and `pytest`.
- Migration / collectstatic invocations inside containers now use `python manage.py …` consistently across `deploy-vps.md`, `deploy-github-ssh.md`, `storage-s3.md`, `dev-tasks.md`, and `docker.md` "Waiting for Postgres". Previous `uv run` form broke deploys whose runtime stage is `python:3.X-slim-bookworm` (no `uv` binary).
- `devcontainer.md` interpreter path was `/app/.venv/bin/python`, but the project venv lives at `/opt/venv/bin/python` per `docker.md`. VS Code's Python extension now resolves the right interpreter.
- `storage-s3.md` "delete this RUN" snippet referenced `/app/.venv/bin/python manage.py collectstatic`, but `docker.md` writes the line as `python manage.py collectstatic`. VPS deploy block also corrected from `docker-compose.prod.yml` to `deploy/docker-compose.prod.yml`.
- `logging.md` Celery wiring is now framed as a one-line delta to the existing `config/celery.py` from `tasks-celery.md` instead of a full file rewrite that silently dropped `os.environ.setdefault` / `config_from_object` / `autodiscover_tasks`.
- `robots.md` declares `ROBOTS_DISALLOW_ALL = env.bool("ROBOTS_DISALLOW_ALL", default=False)` in settings — the documented `.env` toggle was a no-op without it.
- `dev-tools.md` orbit MCP config sets `DJANGO_SETTINGS_MODULE=config.settings.local` (split layout); single-file layout fallback noted inline.
- `SKILL.md` pitfall about deleting the hardcoded `DATABASES` block no longer claims Option B "writes `base.py` from scratch" — Option B replaces values in place too. `new-project.md` Option B carries the explicit delete instruction.
- `auth.md` allauth and `auth-hardening.md` axes settings use `INSTALLED_APPS += [...]` / `MIDDLEWARE += [...]` instead of full re-assignment. Re-declaring the lists in `base.py` would have dropped `production.py` insertions (WhiteNoise position, CSP middleware).
- `ci.md` runs `manage.py check --deploy --fail-level WARNING` against `config.settings.production` before tests — surfaces security-setting regressions at CI time.
- `new-project.md` `test.py` adds `CELERY_TASK_ALWAYS_EAGER = True` / `CELERY_TASK_EAGER_PROPAGATES = True` alongside the existing `django.tasks` Immediate backend.
- `deploy-github-ssh.md` deploy script uses plain `'{{.State.Health.Status}}'` instead of the Liquid-style `{{ '{{' }}.State.Health.Status{{ '}}' }}` escape — GitHub Actions only evaluates `${{ ... }}` expressions, so single-quoted `{{ ... }}` inside a `script:` block passes through unchanged. The escape was unnecessary and harder to read.
- `ci.md` `services:` now includes an opt-in `redis:` block alongside `postgres:` for projects using `cache` / `celery` / `django-tasks-rq`. The `REDIS_URL` env was already there, but the matching service wasn't.
- `analytics.md` ships a minimal `templates/base.html` stub for the `frontend: none` case so the `{% include "_analytics.html" %}` resolves. `csp.md` shows the env-driven Umami integration explicitly (`ANALYTICS_HOST` → `script-src` / `connect-src`). `gdpr.md` provides copy-paste `export_user_data` / `delete_user_data` management commands instead of just naming them.
- `tasks-django-rq.md` / `tasks-django-db.md` drop `django-tasks` from `uv add` (Django 6 ships `django.tasks` in stdlib; the standalone package shadows it). `tasks-django-rq.md` also adds the `include("django_rq.urls")` wiring — bare `django_rq.urls` is a module, not a URLconf, and raised `TypeError` at URL load.
- Testcase 07-saas aligns structural assertions with skill design: `deploy/docker-compose.prod.yml` / `deploy/Caddyfile` paths (per `deploy-vps.md`), `/opt/venv/bin` on PATH (per `docker.md`), CI runs `pytest` without a pre-`migrate` step (per `ci.md`), and `INSTALLED_APPS` only registers `django_tasks_db` since Django 6's `django.tasks` is in core.
- `dev-tools.md` prod `silk_profile` fallback is now a class implementing `__call__` + `__enter__`/`__exit__`, not a decorator factory — the same reference shows `with silk_profile(...)` inside `@task` bodies, which raised `AttributeError` on prod boot.
- `auth-hardening.md` promotes `AXES_HANDLER = 'axes.handlers.cache.AxesCacheHandler'` from a Pitfalls aside to a `production.py` code snippet; agents now copy the line into `production.py` instead of skipping it.
- `docker.md` Variant B multi-stage final stage is named `AS prod` (was `AS runtime`) so testcases that assert a `prod` target match the slim-runtime path.

### Changed
- `docker.md` BuildKit cache mount (`--mount=type=cache,target=/root/.cache/uv`) is now standard on every `RUN uv sync`, with `# syntax=docker/dockerfile:1` at the top of each Dockerfile. Was framed as "optional, speeds up CI"; it's actually load-bearing whenever a multi-stage build re-runs `uv sync` on Rust/C-backed packages without a manylinux/aarch64 wheel (e.g. `django-bolt` on linux/arm64) — without the cache mount the wheel recompiles in each stage.
- `typecheck.md` Pragmatics: documents that `get_user_model()` returns the generic `_UserModel` stub, with the `TYPE_CHECKING` import + annotation pattern as the idiomatic fix (instead of `getattr`).
- Testcases 04/06/07/08/09 relax `pages` app assertion to `pages/views.py (or equivalent — config/views.py is fine)`, matching the skill's recent move of trivial views to `config/views.py`.
- Testcase 02-shop deploy check passes `EMAIL_URL` / `DEFAULT_FROM_EMAIL` / `DJANGO_SECURE_SSL_REDIRECT=False` to the prod containers and uses a ≥ 50-char `DJANGO_SECRET_KEY`; structural assertions for Tailwind+DaisyUI sources moved to `tailwind-src/css/` and the spurious root `docker-compose.yml` requirement (dev mode is uv-on-host) dropped. Health/robots view assertions now point at `config/views.py` (matching `healthcheck.md` / `robots.md`) and `EMAIL_BACKEND` assertion quotes the `env.email_url` line in `base.py` instead of expecting it in `local.py`.

- `docker.md` venv moves to `/opt/venv` via `UV_PROJECT_ENVIRONMENT` so the `.:/app` bind-mount can't shadow it. Drops the anonymous `- /app/.venv` shadow volume from `web` and every worker compose service (`tasks-celery.md`, `tasks-django-db.md`, `tasks-django-rq.md`, `tasks-django-cron.md`). Cleaner cleanup — no `<project>_xxxx` hash-named anon volumes left over after `docker compose down -v`.
- Testcase cleanup now runs `docker compose down -v --rmi local` (was `down -v`) so the compose-built dev image is removed alongside the volumes. Pulled base images (postgres/redis/mailpit/minio) stay shared.

### Fixed
- `tailwind.md` DaisyUI inputs (`source.css`, `daisyui.mjs`, `daisyui-theme.mjs`) move to `tailwind-src/css/`, **outside** `STATICFILES_DIRS`. With them inside, `CompressedManifestStaticFilesStorage` walks the source CSS and fails to resolve `@import "tailwindcss"` / `@plugin "./daisyui.mjs"` as static URLs (`MissingFileError: css/tailwindcss`). Only the compiled `tailwind.css` stays under `assets/`.
- `tailwind.md` production Dockerfile passes `DJANGO_SETTINGS_MODULE=config.settings.production DJANGO_DEBUG=True` to **both** `tailwind build` and `collectstatic`. `manage.py` defaults to `local.py`, which demands `SECRET_KEY` / `DATABASE_URL` that don't exist at image-build time.
- `security.md` `SECURE_SSL_REDIRECT` reads from `DJANGO_SECURE_SSL_REDIRECT` (default `True`). Smoke / staging / direct-gunicorn runs need to disable it; hardcoded `True` returns 301 on every plain-HTTP probe, hiding security headers and breaking smoke assertions. Also adds `SILENCED_SYSTEM_CHECKS = ["security.W005", "security.W021"]` to match the deliberate HSTS opt-outs.
- `storage-s3.md` `production.py` static override is now guarded by `if AWS_STORAGE_BUCKET_NAME:`. ASGI projects load `production.py` in dev too; without the guard, an empty bucket env crashes every admin page with boto3 `ParamValidationError: Invalid bucket name ""`.
- `docker.md` dev compose `db` service no longer publishes 5432 to the host — every machine with host-installed Postgres collides on bind. Containers talk over the compose network; comment-only opt-in for host GUIs.
- `new-project.md` ships a concrete `config/settings/test.py` snippet including `TASKS = {"default": {"BACKEND": "django.tasks.backends.immediate.ImmediateBackend"}}` so split-layout projects get the eager test backend without reverse-engineering the path.
- `SKILL.md` §4 foundation smoke uses `runserver --noreload` + a 5-attempt curl poll instead of `sleep 2`; documents that `kill %1` and `pkill -f manage.py` both break in this harness (no job control / matches parent claude) — use the recorded PID.
- `SKILL.md` Common pitfalls: if i18n = no, drop the `USE_I18N = True` + `# Internationalization` block `startproject` emits.

- `uv.md` Project cheat-sheet now shows `uv init --bare {project_name}` to match `new-project.md`. Without `--bare`, `uv init` ships `main.py` / `README.md` / `.python-version` and the agent then has to delete them. Surfaced by a gemini build that read `uv.md` first and skipped `--bare`.
- `database.md` Litestream Dockerfile pre-creates `/data` and chowns it to `django` before `USER django`; the named SQLite volume mounts as root:root, so without this the prod container EACCES on first write.
- `csp.md` GA4 row now expands into an explicit three-directive snippet; the previous table format led the agent to put only one host in `script-src`.
- `auth-hardening.md` recommends `AXES_HANDLER = AxesCacheHandler` in `production.py` whenever Redis is in scope, not only "on heavy traffic".
- `deploy-github-ssh.md` `.env.prod.example` heading now spells the full `deploy/.env.prod.example` path; the prior heading was ambiguous and the file got skipped while the compose file landed under `deploy/`.

### Added
- `run-tests.sh` learned `BUILD_CLI=gemini` — build phase now runs through `gemini -p --yolo --skip-trust` with a model defaulting to `gemini-2.5-pro`. Review phase still uses `claude -p` (the read-only Bash() allowlist is claude-specific). Skill is linked into the workspace via `gemini skills link --scope workspace --consent` when gemini is selected.

### Changed
- `dev-tools.md` orbit logging section no longer marked "optional" — wire the orbit log handler whenever orbit is installed, otherwise the dashboard misses log records.
- SKILL.md pitfall: run `manage.py startapp <name>` **before** listing the app in `INSTALLED_APPS`. Otherwise `startapp` imports settings and crashes with `ModuleNotFoundError`.
- SKILL.md preflight rule — name the references the agent must read before the first tool call of a new-project run (`new-project.md`, `database.md`, plus one per selected add-on). Surfaced by gemini-flash builds where the agent activated the skill but never read its references.
- `robots.md` and `healthcheck.md` put trivial views in `config/views.py`, not a fresh `pages/` app. If a suitable existing app is present, host them there instead.
- SKILL.md now tells the agent to scan the user's initial request for answers already given and treat them as decided — don't re-ask to confirm. Only ask when the answer is genuinely missing or ambiguous.
- SKILL.md §8 README step requires the deploy command block from the matching `deploy-*.md` to be copied verbatim into a `## Deploy` section — surfaces the one-shot `manage.py migrate` step so first `up -d --build` doesn't hit an empty DB.
- `deploy-vps.md` Caddyfile snippets call out that `example.com` needs replacing — Caddy fails TLS issuance for the placeholder domain.
- `dev-tasks.md` generates `deploy-migrate` + `deploy` tasks when a deploy target was picked (vps / github-ssh / managed-fly). `deploy` depends on `deploy-migrate` so the one-shot migrate precedes `up -d`. Testcases 07/08/09 switch task runner to `mise` and assert the deploy tasks exist.
- README adds a status note that the testcase harness currently runs only against Claude Sonnet.
- `realtime.md` install line adds `daphne` (channels doesn't pull it transitively); routing snippet carries `# type: ignore[arg-type]` for `path(..., Consumer.as_asgi())`.
- `storage-s3.md` adds a MinIO docker-compose snippet with a `curl` healthcheck (`wget` is absent in `minio/minio:latest`) and a note not to gate `web.depends_on` on it.
- `email.md` Mailpit compose snippet adds a `wget /livez` healthcheck so `docker compose up -d --wait` actually blocks until SMTP is ready.
- `devcontainer.md` compose flavour gains `forwardPorts: [8000]`; testcase 04 venv-volume assertion aligns with the anonymous `/app/.venv` shown in `docker.md`.
- `tasks-django-rq.md` aligned with Django 6.0 core: drops `django-tasks` from the `uv add` line (pulled transitively by `django-tasks-rq`) and points the API import at `from django.tasks import task` instead of `django_tasks`.

