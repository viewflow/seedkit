# Seedkit skill review — core Django + system design pass

Date: 2026-07-18. Scope: `skills/seedkit/SKILL.md` + all 47 references. Method: manual pass over the production-critical path plus three parallel deep-read reviews (auth/billing/compliance, APIs/tasks/storage, CI/deploy/frontend).

**Verdict up front:** a well-above-average scaffold. The bones are right — fail-fast env handling (`env.NOTSET`), migrate-before-`up`, non-root multi-stage image, gated `SECURE_PROXY_SSL_HEADER`, honest SQLite/Litestream trade-off documentation, axes-on-by-default. But it is **not "ship blind" prod-ready yet**: 6 references contain bugs that break every project generated from them, the default WSGI path wastes the box it's supposed to vertically scale on, and the deploy pipeline has no test gate and no rollback path.

## 1. Boot-blockers and broken-on-paste (fix first)

- **`storage-whitenoise.md` — every media file 404s on VPS.** Its Caddy block uses `handle /media/*` with `root * /srv/media` but no prefix strip, so `/media/x.png` resolves to `/srv/media/media/x.png`. Notably `deploy-vps.md:80-86` has the *correct* version (`uri strip_prefix /media`) — the two files show different Caddyfiles for the same feature and one is broken. Also `deploy-vps.md:88` says "mount the same media **named volume**" but shows a bind mount `./media:/srv/media:ro`.
- **`auth-hardening.md:41` — `AXES_LOCKOUT_PARAMETERS = ['ip_address', 'username']`** as a flat list means lockout on *either* dimension alone (combination requires a nested list `[["ip_address", "username"]]`). Username-only: an attacker DoSes any known account with 5 bad passwords. IP-only: behind the skill's own Caddy compose, `REMOTE_ADDR` is the proxy container's IP for everyone — one lockout locks out **all users**. Nothing in the reference wires X-Forwarded-For handling, and the "IPWARE" pitfall note is stale (axes ≥ 6 dropped ipware). The same file's comment claiming a settings block "forces 2FA in prod" is false — no listed setting does that, and `ACCOUNT_LOGIN_BY_2FA_REQUIRED` doesn't exist.
- **`billing.md` (raw-SDK path)** — `is_subscribed` only reacts to `subscription.created`/`.deleted`; `customer.subscription.updated` is unhandled, so users whose payments fail (`past_due`, `unpaid`) keep paid access until Stripe deletes the subscription weeks later. No livemode check, no event-ID dedup. (An initial finding that the dj-stripe path misses `DJSTRIPE_FOREIGN_KEY_TO_FIELD` was refuted: the setting was removed in dj-stripe 2.9+; current source has no trace of it.)
- **`csp.md:84` — the report-only rollout doesn't work as written.** `CONTENT_SECURITY_POLICY_REPORT_ONLY = CONTENT_SECURITY_POLICY` assigns the same dict reference (the comment on that very line says not to), and leaving both set sends both headers — the enforcing policy still breaks pages during the "report-only" phase.
- **`tasks-django-cron.md:25` — `from django.tasks import task`** contradicts the other two task backends' explicit rule that 0.12.0 backends need the backport import `from django_tasks import task`. The pasted snippet won't register tasks. The reference also cites three different package/repo names (`django-cron-tasks` / `django-crontask` / `crontask`) — at least one is wrong.
- **`realtime.md` — dev boots on production settings.** Its `asgi.py` defaults `DJANGO_SETTINGS_MODULE` to `config.settings.production`, and the documented dev command is `uv run uvicorn config.asgi:application --reload` — which inherits that default and either crashes on missing prod env vars or runs dev with prod hardening. The WebSocket test snippet also fails as written (`AuthMiddlewareStack` overwrites the injected `scope["user"]` at connect).
- **Smaller paste-breakers:** `storage-s3.md` has unquoted `uv add django-storages[s3]` (zsh globs the brackets); `dev-tasks.md` poe tasks invoke `manage.py` as a program (not on PATH); `rest-bolt.md`'s boot check curls port 8000 for a server that isn't on 8000.

## 2. System design — does it actually vertically scale?

The skill's own positioning (SQLite path: "scale CPU/workers, not containers") is single-big-box vertical scaling — and the defaults don't use the box:

- **Gunicorn ships with 1 sync worker.** The WSGI `CMD` in `docker.md` has no `--workers`, and gunicorn's default is 1. On the default path (wsgi + Postgres), a 16-core VPS serves exactly one request at a time. `async.md` covers worker counts for the ASGI path only. There's also no `--timeout`, no `--max-requests`/`--max-requests-jitter` (the standard memory-leak backstop for long-lived boxes), and no access-log config feeding the structlog story.
- **Redis in prod has no persistence and no memory policy.** `redis.md`'s prod service has no volume and no `--appendonly` — the same instance is the Celery broker (`/1`), so a container restart silently drops every queued task. And with no `maxmemory-policy`, the cache and broker share one eviction fate: `noeviction` (default) can OOM the instance; `allkeys-lru` would evict broker keys.
- **No Docker log rotation.** Neither compose file sets `logging:` options; the default `json-file` driver grows unbounded. On a VPS measured in months, this is a classic disk-full outage. Same disk story: the SSH deploy never runs `docker image prune`, so `:latest` pulls accumulate layers forever.
- **Celery has no runtime limits or health.** No `CELERY_TASK_TIME_LIMIT` (one hung task pins a worker forever), no worker healthcheck in compose, no retry/acks_late guidance. The Beat example schedules `{project_slug}.tasks.example_task` — a module the skill's own pitfall rule ("don't create an app named after the project", "tasks.py lives in a registered app") says will never exist.
- **Postgres is stock.** `postgres:17` with default `shared_buffers=128MB` on a "strong box" leaves most of the RAM unused; a one-line pointer to tuning is missing. `conn_max_age` via URL is covered — good.
- **The web healthcheck may fail out of the box.** `deploy-vps.md` probes `http://localhost:8000/healthz`; with `DEBUG=False` and `DJANGO_ALLOWED_HOSTS=example.com`, that Host header is rejected → 400 → container permanently unhealthy. `healthcheck.md` documents the gotcha but the deploy reference doesn't resolve it.
- **Caddy serves uncompressed dynamic responses and unlimited request bodies.** Caddy does not compress by default (`encode gzip zstd` is absent — WhiteNoise only covers static), and has no default body limit.
- **Zero-downtime is honestly absent** — `up -d` recreate means a blip per deploy. Acknowledged only in the SQLite section; the Postgres path should say it too.

## 3. Deploy pipeline gaps

CI itself is strong for a scaffold (uv caching, service healthchecks, `check --deploy --fail-level WARNING` against prod settings, health-wait instead of sleep-and-curl). The gaps:

- **Deploys aren't gated on tests.** `deploy-github-ssh.md`'s workflow triggers on push to main independently of test.yml — red tests still deploy.
- **No rollback path.** Images are tagged `:latest` only (mutable, overwritten). When the health-wait fails, the old container is already gone and there's no previous image to fall back to. SHA tags + a documented rollback command are the minimum.
- **`dev-tasks.md` deploy tasks are broken against the deploy contract**: all four runner variants omit `--env-file deploy/.env.prod` and the `GITHUB_REPOSITORY` export that `deploy-github-ssh.md` itself calls mandatory; its own table says `uv run manage.py migrate` inside a container that has no uv.
- **`ci.md`'s missing check:** no `makemigrations --check --dry-run`, so model/migration drift lands silently. `pytest.md`'s `fail_under = 80` will likely fail a fresh scaffold's first push, and `source = ["."]` doesn't omit the venv.
- No staging tier anywhere (robots.md implies one exists).

## 4. Missing pieces a core Django dev would expect

- **Background-task errors are invisible.** `error-reporting.md` inits Sentry with `DjangoIntegration` only — exceptions inside django-tasks workers never reach it.
- REST refs have no rate limiting, pagination, or versioning story (auth is fully deferred upstream).
- `gdpr.md`'s export command hands the data subject a JSON containing their `password` hash and `is_superuser`, and doesn't mention deleting the Stripe customer when billing is in scope.
- `custom-user.md`'s email manager doesn't guard case-duplicate emails (`Foo@x` vs `foo@x` are distinct unique values).
- Result-table pruning for `tasks-django-db` (grows unbounded), RQ failed-job registry, media backup on the WhiteNoise+volume path, S3 lifecycle/`Cache-Control`.

## 5. Cross-file drift (the systemic smell)

Individual references are tight, but pairs contradict each other because there's no shared-contract layer:

- `gdpr.md` sets `SESSION_COOKIE_SAMESITE = "Lax"`, `cors.md` sets `"None"` — both applied, last one wins silently.
- The `REDIS_URL` contract ("bare, no `/db`") is stated in `redis.md` but `realtime.md` passes it raw to channels-redis (→ db 0, colliding with the cache) and GlitchTip hardcodes `/1` (Celery's broker db).
- `env_file: .env.prod` vs `.env`, `ghcr.io/{owner}/...` vs `${WEB_IMAGE}`, `service_healthy` vs `service_started` — same concepts, different spellings across compose fragments.
- Version floors disagree (`auth-hardening.md` pins allauth ≥ 0.58, 2023-era; `auth.md` uses 65.x-only settings), Python pins disagree (3.12 in typecheck vs 3.13 elsewhere), and `pytest.md`'s `config.settings.test` vs `deploy-github-ssh.md`'s claim of `local`.
- Two Caddyfile variants for media, one broken (§1). Two doc domains for django-bolt.

Given the skill's "snippet integrity — paste verbatim" rule, drift between files is the highest-leverage class of bug: the agent can't reconcile contradictions it pastes one at a time. A `conventions.md` (env var names, Redis db map, compose service key template, image ref format) that other references defer to would kill most of this category.

## Bottom line

As a Django scaffold: **credible and better-grounded than most**, with unusually honest trade-off documentation. As a prod-ready generator for a vertically scaling product: **not yet** — the generated project ships with a 1-worker gunicorn, a non-persistent task broker, no log rotation, an auth lockout that can lock out the whole userbase, and a deploy that isn't test-gated and can't roll back. Priority order: (1) the §1 paste-breakers, (2) gunicorn workers + Redis persistence + log rotation, (3) test-gated deploys with SHA tags, (4) a conventions reference to stop cross-file drift.
