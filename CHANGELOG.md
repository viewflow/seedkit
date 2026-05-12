# Changelog

Versioned `YY.WW.D` — `date +%y.%V.%u` — year / ISO week / ISO weekday. One section per day; all of a day's commits collapse into one block. Trim to ≤ 200 lines; git keeps the rest.

## 26.20.2 — 2026-05-12

### Fixed
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

## 26.20.1 — 2026-05-11

### Changed
- SQLite mini-prod defaults: when DB=SQLite, Foundation §3 writes the WAL/IMMEDIATE PRAGMAs into `production.py`; §5.3 cache backend defaults to `sqlite` (separate `cache.sqlite3` + `CacheRouter`); §5.4 background tasks default to `django-tasks-db`. The "optional" framing on the SQLite-in-production block in `database.md` is gone.
- Testcase 07 rewritten as the SQLite mini-prod exemplar (VPS + Caddy + single-stage Dockerfile + Litestream + `cache.sqlite3` + `django-tasks-db` + Sentry). Postgres/Redis/Celery coverage stays via cases 02/03/04/06/08/09. README adds a `Cache backend` variation dimension.
- §6 deploy: the `django-dbbackup` question now applies to `github-ssh` too (both `vps` and `github-ssh` deploy to self-managed hosts); skip for `managed` only, or for SQLite-on-VPS when Litestream is wired. Testcase 09 turns dbbackup on to keep coverage that moved out of 07.
- Testcase 04 picks up `asgi+channels` coverage: foundation §2.4 = `asgi+channels`, gunicorn + uvicorn worker `CMD`, `config/asgi.py` with `ProtocolTypeRouter`, `config/routing.py` + an `EchoConsumer`, channels-redis layer reusing the existing Redis service. Boot check round-trips one WS message via the `websockets` lib.
- New Foundation §2.4 question: Request handling = `wsgi` / `asgi` / `asgi+channels`. Default `wsgi`. Decided early because Dockerfile `CMD`, gunicorn worker class, and `manage.py`/`wsgi.py`/`asgi.py` defaults all hinge on it. New `references/async.md` covers WSGI vs stock ASGI (gunicorn + uvicorn worker); new `references/realtime.md` covers django-channels (routing, `channels-redis` layer, separate ASGI worker process pattern, Caddy WS proxy, idle-connection ping). New §5.7 Real-time question (channel-layer pick, asked only when foundation = `asgi+channels`). Testcase README gains a `Request handling` dimension.
- Reference prose cleanup: dropped redundant "Don't X" warnings adjacent to positive samples (tailwind vendored-asset commit, theme switching, DaisyUI specificity, `LOGGING` module-scope, `base.py` import rule, `django_extensions` usage scope, `dmr` library-only note). No behavioral guidance lost — every dropped negative either repeated an adjacent positive or restated the section heading. Speculative warnings about paths the snippets don't show are gone.
- Background tasks no longer auto-create a `jobs/` app on fresh projects: the SKILL.md pitfall now says wire the settings / services / Dockerfile and let the worker idle; the user adds `tasks.py` when they have a domain app. Testcases 03/04/06/07/09 now explicitly request `manage.py startapp jobs` + a sample task in their prompts.
- `references/logging.md` replaces the custom `RequestContextMiddleware` + Celery `task_prerun`/`task_postrun` handlers with `django-structlog`'s `RequestMiddleware` and `DjangoStructLogInitStep`. New runtime dep `django-structlog`. Testcase 04/07/09 review asserts updated.
- Boot-check flow split into §4 Foundation smoke (agent-driven: `migrate` + curl `/admin/login/` — no user keystrokes) and §7 Final smoke (user-driven: `createsuperuser` + browser login at the end, using task-runner names from §5.1 if one was picked). Avoids teaching `uv run manage.py …` muscle memory that §5.1 immediately replaces.
- SQLite + Docker: `docker.md` wires a named `sqlite_data:/data` volume on `web` (simple and override paths) with `DATABASE_URL=sqlite:////data/site.sqlite3`; the Foundation-step-4 warn is gone.
- Bootstrap is uv-on-host only; Docker is a runtime layer (`docker.md`).
- Settings split ships `base / local / production / test.py` from day one.
- `env.NOTSET` replaces `default=None` for the prod branch across env-driven settings.
- Skill prose trimmed: positive samples replace "don't" warnings; per-reference `Docs:` links instead of usage tutorials.

### Added
- Two-phase testcase runner: build and review agents see different contexts.
- `review-logs.sh` harness that loops over per-run logs, applies short skill fixes, and rolls a daily changelog bullet.
- `seedkit-examples` sibling submodule for committable generated reference projects.
- Task runner question (`mise` / `just` / `make` / `poe`) under Developer Experience.

### Fixed
- Wait-for-services rules: `docker compose up -d --wait` rather than hand-rolled `docker compose ps --format json` polling.
- CSP middleware appends to `MIDDLEWARE`; re-declaration drops WhiteNoise.
- Sentry init lives in `production.py`, not `base.py`.
- `django-bolt` builder image: full uv bookworm + `build-essential` (no aarch64-linux wheel).
- `setup.cfg [django_migration_linter] exclude_apps` uses app labels, not INSTALLED_APPS names.
