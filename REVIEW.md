# Seedkit skill review

**Date:** 2026-07-04 · **Scope:** `skills/seedkit/SKILL.md` + all 45 reference files · **Method:** 8 parallel review passes (core, auth/email, security, tasks, REST/realtime, deploy/infra, frontend/storage/billing, dev tooling), each verified against current upstream docs and releases (July 2026).

**Goal reviewed against:** generate a full-featured but minimal Django project, free of bad practices and performance issues, immediately ready to work with — as if created by a very experienced senior Django system-design engineer.

**Status update 2026-07-04:** §1 blockers fixed in the references (CHANGELOG 26.27.6), §1.5 revised after empirical testing against generated projects, and the version-rot sweep from §2.1 applied (verified-current pins + a SKILL.md generation-time freshness rule). §2.2–§2.5, §3, §4 remain open.

---

## Executive summary

The skill's architecture is genuinely strong: the questionnaire flow, the DEBUG-gated `env.NOTSET` fail-fast idiom, the multi-stage uv Docker build, liveness/readiness probe semantics, migrate-before-`up` ordering, and the Django 6 `django.tasks` backend split are all current, correct, and reflect real senior judgment. Most files boot as written.

The review found **7 blockers** (paths where a generated project crashes, silently loses money-handling webhooks, or never produces a backup), a systemic **staleness problem** (every version pin is 1–2 years old; several snippets target APIs that have since been removed or deprecated), a **defaults posture** that contradicts the stated goal (security settings, lint, and CI all default *no*), and a handful of **confidently-wrong claims** that agents copy verbatim into generated projects (nonexistent ORM methods, hallucinated setting names, false rationale comments).

Fix priority: §1 blockers → §2 cross-cutting themes (staleness habit + defaults) → §3 majors → §4 minors.

---

## 1. Blockers — generated project fails or silently breaks

### 1.1 `email.md` — anymail path crashes on prod boot
`EMAIL_URL` is gated `default="consolemail://" if DEBUG else env.NOTSET` (~line 18), but the anymail section says "`EMAIL_URL` is no longer needed in prod" and its `.env.prod` sample omits it — the project raises `ImproperlyConfigured` at startup. Either drop the NOTSET gate on the anymail path or keep `EMAIL_URL` in `.env.prod`.

### 1.2 `billing.md` — dj-stripe option targets the API removed in dj-stripe 2.9
`DJSTRIPE_WEBHOOK_SECRET` + "register `/stripe/webhook/`" (~lines 212–252) is the pre-2.9 flow; current dj-stripe (2.10.x) uses DB-backed `WebhookEndpoint` rows with UUID-suffixed URLs created via admin. As written: webhook URL 404s, billing state never syncs, `stripe listen --forward-to` fails. Additionally the Option B checkout view calls `stripe.checkout.Session.create()` without ever setting `stripe.api_key` (dj-stripe doesn't set the global) → `AuthenticationError` on first checkout. Rewrite Option B against the 2.9+ webhook model and set the key explicitly.

### 1.3 `deploy-vps.md` — manual deploy fails on first boot
The Deploy section's three `docker compose` commands (~lines 92–99) omit `--env-file deploy/.env.prod`; compose never auto-loads that path, so `POSTGRES_PASSWORD` interpolates empty and Postgres refuses to initialize. `deploy-github-ssh.md` states the rule this file violates. Add `--env-file` to all three commands.

### 1.4 `dbbackup.md` + `docker.md` — backups never happen, silently
Two independent failures: (a) the cron line (~lines 55–58) has no `cd`, no `-f`, no `--env-file`, and runs as a `django` host user that no reference creates — cron logs "bad username" and skips it; (b) bookworm's `postgresql-client` is v15 while the prod DB is `postgres:17` — `pg_dump` aborts on server-version mismatch even when invoked correctly. Since the only invocation is cron, failure is invisible. Fix the cron line (cwd + flags + real user + log redirect) and install `postgresql-client-17` from PGDG or move to trixie images (see 2.1).

### 1.5 `typecheck.md` — warning downgrades neutralized CI *(revised after empirical testing)*
Original finding recommended swapping django-stubs for `django-types` (django-stubs' ORM typing is materialized by its mypy plugin, which pyright can't run). **Tested 2026-07-04 against four generated projects** (02-shop, 04-media-vault, 07-vps-sqlite-saas, 08-fly-app): pyright + django-stubs at error level reports **0 errors**, while django-types produces real false positives — its `UserCreationForm`/`UserChangeForm` stubs lack `Meta` (breaks the skill's own custom-user admin snippet) and it has no `django.tasks` stubs (Django 6). **django-stubs stays.** The valid half of the finding is fixed: `reportGeneralTypeIssues`/`reportOptionalMemberAccess` were downgraded to warnings, which never fail pyright's exit code — the downgrades are removed so the rules report at error level.

### 1.6 `i18n.md` — selecting i18n breaks the Docker image build
The reference adds `RUN python manage.py compilemessages` to the production Dockerfile, but the runtime stage installs no `gettext` — `msgfmt` not found, build dies. Add `gettext` to the runtime apt line when i18n is selected.

### 1.7 `realtime.md` — the shipped WebSocket test cannot pass locally
`WebsocketCommunicator(application, ...)` sends no `Origin` header, so the skill's own `AllowedHostsOriginValidator` denies the handshake — `assert connected` fails everywhere except CI (where `DJANGO_ALLOWED_HOSTS: "*"` masks it). Pass an origin header or test against `AuthMiddlewareStack(URLRouter(...))` directly.

---

## 2. Cross-cutting themes

### 2.1 Version rot is systemic — the skill needs a "current at generation time" habit
Found stale in one sweep: `uvicorn.workers.UvicornWorker` (deprecated since 0.30, removal pending — `async.md`, `realtime.md`); Litestream pinned to abandoned v0.3.13 (0.5.x is the maintained line with a changed replica format — `database.md`); `actions/checkout@v4`, `setup-uv@v3`, `build-push-action@v5`, `codecov-action@v4` (all a major behind; Node 20 runner deprecation is live); pre-commit revs ~2 years old with the legacy `ruff` hook id (current: `ruff-check`/`ruff-format`) — and the pinned hook-ruff will *format-fight* the current uv dev-dep ruff; `redis:7-alpine` (Redis 8 GA May 2025); bookworm/py3.12 image generation (uv's own images moved to trixie; the builder/runtime pairing rule doesn't mention the Debian-suite match, so an innocent builder bump → glibc import errors); `storages.backends.s3boto3.*` legacy path; "pin allauth >= 0.58" (current: 65.x); `python = "3.12"` pins in dev-tasks/typecheck.

Beyond the individual bumps, add a generation-time rule to SKILL.md: for pinned artifacts (actions, pre-commit revs, base images, standalone binaries) instruct the agent to check the latest release at generation time (`pre-commit autoupdate`, GitHub releases lookup) instead of trusting the reference's literal pin.

### 2.2 Defaults contradict the "senior engineer, production-ready" promise
A user who accepts every default gets: no security settings (`Default no` — prod fails `check --deploy`, cookies over HTTP, no HSTS), no lint, no CI, no tests beyond Django's stub, no static-file story. Recommended posture changes in `SKILL.md`:

- **Security settings: apply unconditionally** whenever `production.py` / a deploy target is generated. They're env-gated and cost nothing in dev. Keep CSP as the opt-in sub-question.
- **Ruff: default yes** (one dev dep, zero runtime footprint).
- **CI: default yes** when the repo has a GitHub remote.
- **Static storage: force a real answer when a deploy target is chosen** — deploy + `storage=none` ships a prod site with unserved static files.
- Defensible as-is: test-runner default (stock), typecheck no, debug toolbar none, i18n no.

### 2.3 Confidently-wrong claims — worst failure class for an agent-executed skill
Agents follow "Snippet integrity" and copy these verbatim: `Model.objects.afilter(...)` doesn't exist (`async.md`); daphne "needed for management commands and signal hooks" is false, and with daphne in `INSTALLED_APPS` `runserver` *does* serve WebSockets, contradicting line 117 (`realtime.md`); `ZEAL_RAISE_ON_VIOLATION` and `ZEAL_SILENCED_WARNINGS` are hallucinated names (real: `ZEAL_RAISE`, `ZEAL_ALLOWLIST`), and "zeal works automatically in pytest" is false — as wired, zeal never runs in tests at all (`dev-tools.md`); the `UserChangeForm` `field_classes` comment misstates Django source and ships dead config (`custom-user.md`); pytest-django "builds once, then reuses" is backwards — default is create+destroy every run; the snippet lacks `--reuse-db` (`pytest.md`); "Caddy default read_timeout 60s" — no such default (`realtime.md`); `WHITENOISE_USE_FINDERS` "doesn't exist" — it does (`storage-whitenoise.md`); "pyjwt is an unpinned transitive dep" — it's an optional extra; the install ships a dead auth lib into every project (`rest-modern-rest.md`); axes pitfall implies proxy wiring makes IP detection work — plain `django-axes` has no ipware (`auth-hardening.md`).

Consider adding a review gate to the maintenance workflow: every factual claim in a reference ("X requires Y", "default is Z") must be verifiable against upstream docs, same standard the wiki research rules already apply.

### 2.4 Cross-file contradictions
- `cors.md` sets `*_COOKIE_SECURE = not DEBUG`; `security.md` sets them unconditionally `True` in `production.py` — no stated target file, whichever pastes last wins.
- `new-project.md` says point all three entry points at production settings; `async.md`'s table says only the deployed one — and the untouched file then points at `config.settings`, an empty package (import-error trap).
- `deploy-vps.md` hardcodes `image: ghcr.io/{owner}/{project_slug}:latest`; `deploy-github-ssh.md` assumes `image: ghcr.io/${GITHUB_REPOSITORY}:latest` — one of the two is wrong for any given project.
- `healthcheck.md` mandates a Fly `[checks]` block and a GH-Actions `/readyz` gate; `deploy-managed.md`'s `fly.toml` has no checks section and the GH workflow polls `/healthz` instead.
- `lint.md`'s `core.hooksPath .githooks` makes `pre-commit install` refuse to run ("Cowardly refusing…"); no arbitration between the two hook mechanisms, and both applied → ruff runs twice in CI at two versions.
- `gdpr.md` ships a second, drifting `sentry_sdk.init` next to `error-reporting.md`'s canonical one; its SameSite advice contradicts `cors.md`.
- `tasks-celery.md`'s Beat snippet enqueues `{project_slug}.tasks.example_task` — a task the skill (per its own app-layout rule) never creates, and the wrong module-path form; the worker logs unregistered-task errors from day one.

### 2.5 Strategic: the REST offering is two pre-1.0 frameworks
`rest.md` offers only `django-modern-rest` (0.11, ~39k total downloads) and `django-bolt` (0.8, "under active development") — no DRF (3.17.x, Django 6 support), no django-ninja (stable 1.x, exactly the typed/async niche this skill wants). A skill claiming senior judgment shouldn't put churn risk on the most load-bearing dependency without at least saying so. Add django-ninja as the stable default (or an honest table row explaining the exclusion so users can veto it).

---

## 3. Major findings by area

### Core foundation
- **`new-project.md`** — `ALLOWED_HOSTS = env.list(..., default=[])` boots fine in prod then 400s every request; gate it with `env.NOTSET` like `SECRET_KEY` (the file's own prose says "defaults are gated by DEBUG").
- **`database.md`** — no mention of Django ≥5.1 native psycopg pooling (`OPTIONS: {"pool": True}`), the current recommendation and the safer option for the ASGI mode this skill offers; document it and the mutual exclusion with `conn_max_age`.
- **`database.md`** — Litestream 0.3.13 pin (see 2.1); re-verify restore flags against the 0.5 migration guide when bumping.

### Auth
- **`auth-hardening.md`** — axes + allauth is not plug-and-play: allauth posts the identifier as `login` but reports `username` in failure signals, so the `username` lockout dimension silently never fires. Add the documented integration steps or scope lockout to `ip_address` and say why.
- **`auth-hardening.md`** — plain `uv add django-axes` ships no ipware; behind Caddy/nginx every failure resolves to the proxy IP → one attacker locks out the whole site. Install `'django-axes[ipware]'` and fix the pitfall text.
- **`auth-hardening.md`** — `AXES_LOCKOUT_PARAMETERS = ['ip_address', 'username']` (OR semantics) enables trivial username-lockout DoS; the AND form is `[['ip_address', 'username']]`.
- **`auth-hardening.md`** — the "Only force 2FA in prod" comment forces nothing; allauth.mfa has no require-2FA setting. Delete the comment or add real enforcement (adapter/middleware).

### Security
- **`csp.md`** — the whole reference installs `django-csp` for a feature Django 6.0 ships in core (`SECURE_CSP`, `django.middleware.csp.ContentSecurityPolicyMiddleware`, `{{ csp_nonce }}`). Rewrite around core CSP; drop the dependency. Also the report-only recipe assigns the same dict to both settings (comment says don't), keeps enforcement active anyway, and has no `report-uri` — so "check the logs" observes nothing.
- **`cors.md`** — `CORS_ALLOW_CREDENTIALS = True` always-on with a wrong rationale (`Authorization` header doesn't need it), plus blanket `SameSite=None` advice triggered by header-auth too. Default credentials off; gate the SameSite block on cookie auth only.

### Tasks & Redis
- **`tasks-celery.md`** — no `CELERY_TASK_TIME_LIMIT`/soft limit, no acks_late/prefetch note: one hung task occupies a worker slot forever and deploy restarts drop in-flight tasks. Also consider `CELERY_TASK_IGNORE_RESULT = True` until results are consumed, and `stop_grace_period` on worker services (applies to all three worker compose blocks).
- **`tasks-django-db.md`** — no result pruning: the upstream `prune_db_task_results` command is never wired; task table grows unbounded in prod.
- **`redis.md`** — installs django-redis where Django's built-in `RedisCache` (4.0+) suffices; premise sentence omits it. Also one shared instance hosts cache + broker with no `maxmemory` guidance (default `noeviction` → OOM takes the broker down; `allkeys-lru` would evict queue keys) and no persistence for queued tasks. Add a short memory/eviction/persistence block; default to the built-in backend.
- **`tasks-django.md`** — the comparison omits django.tasks' biggest gap vs Celery: no retries.

### Deploy & Docker
- **`docker.md`** — default CMD is 1 sync gunicorn worker, no `--max-requests`/jitter, no access logs. Add worker recycling + `--access-logfile -` + `WEB_CONCURRENCY` in `.env.prod.example`.
- **`deploy-github-ssh.md`** — `:latest`-only tagging → no rollback path; add the `:${{ github.sha }}` tag and a one-line rollback note. Also `@v1` mutable tag on `appleboy/ssh-action` directly contradicts the pin-to-SHA comment above it; no `cache-from/to: gha`, so every deploy cold-rebuilds.
- **`deploy-vps.md`** — no container log rotation (json-file driver never rotates → disk fills on exactly the small-VPS profile targeted); add `logging: {max-size, max-file}` per service. Caddy lacks `443:443/udp` (advertised HTTP/3 unreachable); active health check on a single upstream converts container swaps into 502 windows.
- **`deploy-managed.md`** — Fly config uses legacy `[[services]]` and never wires the health check `healthcheck.md` promises.

### Storage & billing
- **`storage-s3.md`** — static-from-bucket 403s on default AWS Block-Public-Access with zero bucket-policy/CloudFront guidance; and no cache-busting or `Cache-Control` (WhiteNoise path gets manifest hashing, S3 path gets neither). Use `S3ManifestStaticStorage` + object parameters, add the policy/OAC section, and keep `MEDIA_ROOT` for the FileSystemStorage fallback.
- **`billing.md`** — webhook handler never processes `customer.subscription.updated`, so `past_due`/`unpaid` subscribers keep access; `payment_method_types=["card"]` disables dashboard-managed payment methods; global `stripe.api_key` is the legacy SDK pattern (StripeClient is current).

### Dev tooling & CI
- **`ci.md`** — redis service sits uncommented inside the paste-ready YAML (violates the skill's own snippet-integrity rule — every project gets it); no `concurrency` group (double runs on PRs); no `permissions: contents: read`.
- **`pytest.md`** — missing `--reuse-db` (see 2.3); no parallelization mention anywhere (`pytest-xdist` / `--parallel`).
- **SKILL.md §5.1/§6.5 defaults** — see 2.2.

---

## 4. Minor findings (quick edits)

- **Dead/wrong URLs:** `dev-tools.md` line 3 both repo links 404 (real: `astro-stack/django-orbit`, `taobojlen/django-zeal`); `rest.md`/`rest-bolt.md` header link 404 (real: `bolt.farhana.li`); `tasks-django-db.md` (real: `RealOrangeOne/django-tasks-db`); `tasks-django-cron.md` (real: `codingjoe/django-crontask`); `analytics.md` Shynet link NXDOMAIN (use the GitHub repo); `tasks-django.md` link `/en/dev/` → `/en/6.0/`.
- **`new-project.md`** — insert-snippet duplicates `BASE_DIR`/`DEFAULT_AUTO_FIELD`/`STATIC_URL` that startproject already wrote; the "never restate values" rule contradicts the `test.py` snippet two paragraphs later (scope the rule).
- **`database.md`** — `DATABASES["cache"]["OPTIONS"] = DATABASES["default"]["OPTIONS"]` aliases a mutable dict; wrap in `dict(...)`. Add the one-line `psycopg[c]` production trade-off note.
- **`uv.md`** — `uv python pin 3.12` writes the `.python-version` the `--bare` comments advertise avoiding, and pins the oldest supported interpreter.
- **`existing-project.md`** — inventory never detects the package manager but the boot check hardcodes `uv run`; add lockfile detection and phrase commands as "the project's runner".
- **`auth.md`** — `django.contrib.sites` presented as required with a wrong failure-mode claim (allauth builds URLs from the request host); drop it or fix the rationale. Also "pin allauth >= 0.58" is dead weight; "`django-otp-totp`" names a nonexistent package (the plugin ships inside django-otp); prefer `AxesStandaloneBackend`.
- **`auth-hardening.md`** — note allauth's built-in login rate limits (two overlapping lockout systems otherwise); axes adds near-zero value on the passwordless mail-auth path — consider default no there.
- **`email.md`** — `ANYMAIL_WEBHOOK_SECRET` must be a `user:password` pair; without the colon every webhook silently fails validation. Show the format.
- **`security.md`** — `SECURE_REFERRER_POLICY = "same-origin"` restates the Django default unannotated; `CSRF_TRUSTED_ORIGINS` needs the `https://` scheme example.
- **`gdpr.md`** — the user-data export serializes the password hash and internal flags; use `fields=`. Reduce the sentry snippet to a delta on `error-reporting.md`'s init.
- **`error-reporting.md`** — GlitchTip compose depends on an undefined `redis` service, mixes inline env with `env_file`, lacks `GLITCHTIP_DOMAIN` and a migration step; `bugsink:latest` unpinned for a stateful service.
- **`rest-modern-rest.md`** — default endpoint is an unauthenticated CSRF-exempt POST with no auth section (bolt's file has one), no throttling/pagination word; version claim wrong (upstream is `django>=5.0,<6.1`); the `INSTALLED_APPS` pitfall misdiagnoses (dmr has no app discovery). `rest-bolt.md` — the 60-line "fast-path settings" section optimizes middleware that never runs on bolt's path (opt-in only); shrink to two sentences. State bolt's Python 3.12+ floor.
- **`tasks-django-db.md`** — duplicated "run worker" section; note `db_worker` DB polling (contention on SQLite). `tasks-django-cron.md` — compose `depends_on` assumes the DB backend; mirror the chosen backend.
- **`dev-tasks.md`** — poe tasks invoke `manage.py` without an interpreter (breaks on Windows / lost exec bit); `[tools] python = "3.12"` stale.
- **`custom-user.md`** — reduce the admin form override to `Meta(UserChangeForm.Meta)` and delete the false comment.
- **`i18n.md`** — LocaleMiddleware detection order is reversed and cites session lookup removed in Django 4.0.
- **`tailwind.md`** — DaisyUI fetched from `releases/latest/` while the file mandates pinning; use a versioned URL. Revisit the `4.1.3` CLI pin example.
- **`analytics.md`** — self-hosted GoatCounter snippet still loads `count.js` from the SaaS host; serve it from the instance.
- **`devcontainer.md`** — `host.docker.internal` needs `runArgs: ["--add-host=…:host-gateway"]` on Linux and is unfollowable in Codespaces; scope the advice.
- **`deploy-managed.md`** — stale `/app/.venv/bin` comment (actual: `/opt/venv`). `deploy-github-ssh.md` — `.env.prod.example` ships `REDIS_URL` with no redis service in prod compose. `docker.md` — `uv sync --frozen` → `--locked` per current uv docs.
- **`pytest.md`** — `codecov-action@v4` → v5.

---

## 5. What's already right (keep)

Verified sound against current upstream: allauth 65.x settings names (`ACCOUNT_LOGIN_METHODS`/`ACCOUNT_SIGNUP_FIELDS`); the allauth-2fa-is-dead / `[mfa]` extra guidance; django-mail-auth choice and the email-uniqueness hijack warning; the whole `django.tasks` backend architecture (all four worker paths boot on current versions; package names/app labels/commands verified); the `env.NOTSET` fail-fast idiom; SQLite WAL/`transaction_mode` production block and `CacheRouter`; `security.md`'s proxy-spoofing guidance and deliberate HSTS opt-outs; liveness-without-DB / readiness-with-DB split; non-root Docker user, two-step `uv sync`, venv-copy runtime stage; migrate-as-one-shot before `up -d`; the health-status wait loop; whitenoise STORAGES config and the media-volume chown trap; structlog/django-structlog wiring (fully current); the silk no-op decorator and LOGGING-never-inside-DEBUG rules; robots.md's "not a security control" framing.

---

## 6. Suggested fix order

1. **Blockers (§1)** — seven items, each a one-file fix.
2. **SKILL.md posture (2.2)** — security always-on with production settings; ruff/CI defaults; storage question forced by deploy.
3. **Confidently-wrong claims (2.3)** and **cross-file contradictions (2.4)** — cheap edits, high trust payoff.
4. **Version-rot sweep (2.1)** — one pass over every pin + the "check latest at generation time" rule in SKILL.md, so it doesn't rot again.
5. **REST strategy (2.5)** — decide the django-ninja/DRF question deliberately; it's a positioning choice, not a bug fix.
6. Majors (§3), then minors (§4) opportunistically per file touched.
