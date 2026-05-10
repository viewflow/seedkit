# 04 — Full docker-compose stack, S3 storage, Django-Tasks (RQ)

Covers full Compose dev mode, S3-compatible object storage, and the Django Tasks API with the Redis Queue backend.

## Prompt

```
/seedkit

Project name: 04-media-vault
Purpose: media-heavy app where uploads land in S3 and processing runs as Redis-queued background tasks.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: docker-compose (full stack: web + db + redis).
Docker structure: simple (separate `Dockerfile.dev`, single `docker-compose.yml`).
Lint with Ruff: yes.
Test runner: manage.py test (stock Django).
Type check (pyright + django-stubs): yes.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: no.
Auth add-on: none.
Structured logging: yes (`structlog`, JSON in prod / pretty in dev, request-scoped `request_id`).
Add-ons:
  - redis
  - storage: S3-compatible (use MinIO in local Compose; configure via env)
  - tasks: Django Tasks with the Redis Queue backend (`django-tasks-rq`)
  - email: console backend in local (`EMAIL_URL=consolemail://`).
  - CORS: yes.
  - REST API: `django-modern-rest` with the `msgspec` + `openapi` extras (`uv add 'django-modern-rest[msgspec,openapi]'`). Create an `api` app (`uv run manage.py startapp api`) with a single `MediaController` exposing `POST /api/media/` that accepts `{ "filename": str, "size": int }` (msgspec.Struct) and returns `{ "uid": uuid, "filename": str }`. Wire the `Router` from `api/urls.py` into `config/urls.py` under the `api` namespace. Do NOT add `dmr` to `INSTALLED_APPS`.
  - Frontend: none.
  - Devcontainer: yes.
  - Health check endpoints: yes.
  - `robots.txt`: no.
  - `django-extensions`: no.

Production setup: skip.

Generate `docker-compose.yml` with services `web`, `db`, `redis`, `worker`, `minio`. Run the foundation, `docker compose up -d`, migrate, createsuperuser, and confirm a sample task enqueues and completes.
```

## Expected outcome

- `docker compose up -d` starts all five services healthy.
- `web` runs `runserver` on `:8000`; `/admin/` login works.
- `worker` runs `manage.py rqworker default` and processes a queued task.
- `minio` exposes a bucket; uploaded media land there (verify via `mc` or admin UI).
- `psycopg[binary]`, `django-tasks`, `django-tasks-rq`, `django-storages[s3]` (or `boto3`) in dependencies.
- Ruff config present; `docker compose exec web uv run ruff check .` exits 0.
- Pyright + `django-stubs` + `django-stubs-ext` configured; `[tool.pyright]` block in `pyproject.toml`; `django_stubs_ext.monkeypatch()` called from `config/settings/base.py` (inside an `except ImportError: pass` guard so the prod image without the dev dep keeps booting); `docker compose exec web uv run pyright` exits 0.
- Named volumes for `pgdata`, `venv`, `uv-cache`, `minio-data`.
- `structlog` installed; `LOGGING` configured with both `json` and `console` formatters, `console` chosen when `DEBUG`; `RequestContextMiddleware` inserted into `MIDDLEWARE`; a request to `/admin/login/` produces a log line carrying `request_id`.
- `django-modern-rest[msgspec,openapi]` in dependencies; `dmr` is **not** in `INSTALLED_APPS`. `api/` Django app exists with `controllers.py`, `schemas.py`, `urls.py`. `MediaController(Controller[MsgspecSerializer])` defines `post()` typed with `Body[MediaCreate]` returning `MediaOut`. Router mounted under `/api/`. `POST /api/media/` with a valid JSON body returns 200 + parsed body echoed; an invalid body (missing `size`) returns a 422-class error from dmr's validator.
- `.devcontainer/devcontainer.json` exists, sets `"dockerComposeFile": ["../docker-compose.yml"]`, `"service": "web"`, `"workspaceFolder": "/app"`, and `"shutdownAction": "stopCompose"`. `forwardPorts` includes `8000`. The file does **not** contain any secrets / DB passwords (those stay in `.env`).
- `pages` app exposes `liveness` / `readiness`; `curl /healthz` → `ok`, `curl /readyz` → `ready` (DB reachable inside Compose).

## Run

```sh
# Run from a scratch parent dir; the skill creates `04-media-vault/`.
# AI executes the skill here, then:
cd 04-media-vault
docker compose up -d
docker compose exec web uv run manage.py migrate
docker compose exec web uv run manage.py createsuperuser --noinput || true
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
# REST endpoint — happy path
curl -sf -X POST http://127.0.0.1:8000/api/media/ \
  -H 'content-type: application/json' \
  -d '{"filename":"a.png","size":42}' > /dev/null
# REST endpoint — invalid body must NOT 200
! curl -sf -X POST http://127.0.0.1:8000/api/media/ \
  -H 'content-type: application/json' \
  -d '{"filename":"a.png"}' > /dev/null
# Healthchecks
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
docker compose exec -T web uv run pyright
# Devcontainer file present and machine-readable
test -f .devcontainer/devcontainer.json
python3 -c "import json; d=json.load(open('.devcontainer/devcontainer.json')); assert d['service']=='web'; assert '../docker-compose.yml' in d['dockerComposeFile']"
# enqueue + observe one task
```

## Log check

Run after the boot check; the testcase is a failure if any of these print matches:

```sh
docker compose logs --tail=80 web worker db redis minio
# fail on any traceback / unhandled error in any service:
! docker compose logs web worker 2>&1 | grep -iE 'traceback|^error|critical|unhandled'
# worker should print rqworker startup line:
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

Leave the code. Tear down containers and volumes (web, db, redis, worker, minio + named volumes):

```sh
docker compose down -v
```
