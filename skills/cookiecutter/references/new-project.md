# New Django Project

## Create

Pick the path that matches the user's chosen dev mode. The branches differ in **where the `.venv` lives**: on the host (uv-host) vs only inside the container (docker-compose). Mixing them causes uv to print `Ignoring existing virtual environment linked to non-existent Python interpreter` on every container start because the host's macOS / Windows venv symlinks are invalid in Linux.

### If dev mode is "uv on host"

```sh
uv init --bare {project_slug}     # --bare skips main.py / README.md / .python-version
cd {project_slug}
uv add 'django>=6.0,<7.0' django-environ
uv run django-admin startproject config .
```

### If dev mode is "docker-compose"

Don't run `uv add` / `uv run` on the host — that creates a `.venv` linked to the host Python, which then collides with the container's Linux venv. Do everything through the container:

```sh
uv init --bare {project_slug}
cd {project_slug}
# Generate Dockerfile + docker-compose.yml first (see references/docker.md).
# Then run installs and startproject inside the container — host stays venv-free:
docker compose run --rm web uv add 'django>=6.0,<7.0' django-environ
docker compose run --rm web uv run django-admin startproject config .
```

From here on, **every** Python command goes through `docker compose run --rm web …` or `docker compose exec web …`. Add `.venv` to `.dockerignore` so even an accidental host venv (created by an IDE or ad-hoc `uv` call) never enters the build context.

In `config/settings.py`, replace only `SECRET_KEY` / `DEBUG` / `ALLOWED_HOSTS` / `DATABASES`. Leave everything else `startproject` wrote.

## Settings — ask the user which structure they prefer

Use the snippets below verbatim.

---

### Option A: Single settings file (simpler)

Keep `config/settings.py` in place. Remove `SECRET_KEY`, `DEBUG`, `ALLOWED_HOSTS` and `DATABASES` — add at the top:

```python
from pathlib import Path
import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR / ".env")

DEBUG = env.bool("DJANGO_DEBUG", default=False)
SECRET_KEY = env("DJANGO_SECRET_KEY", default="django-insecure-build-only" if DEBUG else None)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])  # DEBUG already accepts localhost / 127.0.0.1 / [::1]
DATABASES = {"default": env.db("DATABASE_URL", default="sqlite:///db.sqlite3" if DEBUG else None)}
```

Dev defaults are gated by `DEBUG`: in production `DJANGO_DEBUG` is unset, the defaults vanish, and missing values raise `ImproperlyConfigured`.

---

### Option B: Split settings (base / local / production)

```sh
mkdir config/settings
mv config/settings.py config/settings/base.py
touch config/settings/__init__.py
```

**config/settings/base.py** — remove `SECRET_KEY`, `DEBUG`, `ALLOWED_HOSTS` and `DATABASES` — add at the top:

```python
from pathlib import Path
import environ

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR / ".env")

DEBUG = env.bool("DJANGO_DEBUG", default=False)
SECRET_KEY = env("DJANGO_SECRET_KEY", default="django-insecure-build-only" if DEBUG else None)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])  # DEBUG already accepts localhost / 127.0.0.1 / [::1]
DATABASES = {"default": env.db("DATABASE_URL", default="sqlite:///db.sqlite3" if DEBUG else None)}
```

**config/settings/local.py** and **config/settings/production.py** contain **only deltas** from `base.py` — settings that genuinely differ. Use them for things that *only make sense in that environment*: dev-only tooling (debug-toolbar, query loggers, relaxed CORS) goes in `local.py`; production hardening (HSTS, secure cookies, manifest static storage) goes in `production.py`. Never restate values that are already in base; never redeclare `MIDDLEWARE` / `INSTALLED_APPS` / `DATABASES` / `EMAIL_BACKEND` / `STORAGES`. Mutate the inherited list in place when something needs to be added (e.g. WhiteNoise middleware in production):

```python
# config/settings/local.py
from .base import *

# only what differs from base
```

```python
# config/settings/production.py
from .base import *

# Append when order doesn't matter:
# MIDDLEWARE += ["some.middleware.SomeThing"]
#
# Insert at a specific position when the middleware requires it
# (e.g. WhiteNoise must be directly after SecurityMiddleware):
# MIDDLEWARE.insert(1, "whitenoise.middleware.WhiteNoiseMiddleware")
```

Don't re-instantiate `env = environ.Env()` — it's already imported via `from .base import *`.

**manage.py** — change `DJANGO_SETTINGS_MODULE` to `"config.settings.local"`.

**config/wsgi.py and config/asgi.py** — change `DJANGO_SETTINGS_MODULE` to `"config.settings.production"`.

---

## Static files

In `config/settings.py` (or `config/settings/base.py` for split):

```python
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
```

## .env.example and .env

Write `.env.example` (committed) with every env var the settings module reads. Set `DATABASE_URL` per `references/database.md` (SQLite or PostgreSQL):

```sh
DJANGO_SECRET_KEY=replace-me
DJANGO_DEBUG=True
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
DATABASE_URL=sqlite:///db.sqlite3
```

Then `cp .env.example .env` and set `DJANGO_SECRET_KEY` to a real dev value (`uv run python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"`). `.env` is gitignored; `.env.example` is committed. Keep `.env.example` in sync whenever you add a new `env(...)` call to settings.

If a value contains a literal `$` (e.g. an autogenerated `SECRET_KEY` or a `DATABASE_URL` with `$` in the password) and the project uses docker-compose with `env_file:`, escape it as `$$` — Compose interpolates `${VAR}` and `$VAR` against its own environment otherwise.

## .gitignore

Write a `.gitignore` for a Django + uv project. Must include `.venv/`, `.env`, `*.sqlite3`, `staticfiles/`, `media/`. Add the other standard Python / Django / editor / tooling entries you know belong. Do this before the first commit.

## Boot check

For **uv on host**:

```sh
uv run manage.py migrate
uv run manage.py createsuperuser
uv run manage.py runserver
```

For **docker-compose** (container-only Python):

```sh
docker compose up -d
docker compose exec web uv run manage.py migrate
docker compose exec web uv run manage.py createsuperuser
```

Confirm `/admin/` login works before continuing.

## Scripts (optional — only if the user asks for task shortcuts)

```sh
uv add --dev poethepoet
```

```toml
[tool.poe.tasks]
dev     = "python manage.py runserver"
migrate = "python manage.py migrate"
test    = "pytest"
lint    = "ruff check ."
```

Run with `uv run poe <name>`.
