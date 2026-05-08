# New Django Project

## Create

Pick the path matching the chosen dev mode. They differ in **where the `.venv` lives** — host (uv-host) vs only inside the container (docker-compose). Mixing them makes uv print `Ignoring existing virtual environment linked to non-existent Python interpreter` because host venv symlinks aren't valid in Linux.

### uv on host

```sh
uv init --bare {project_slug}     # --bare: no main.py / README.md / .python-version
cd {project_slug}
uv add 'django>=6.0,<7.0' django-environ
uv run django-admin startproject config .
```

### docker-compose

Don't run `uv add` / `uv run` on the host (creates a venv that collides with the container's). Run installs and `startproject` inside the container:

```sh
uv init --bare {project_slug}
cd {project_slug}
# Generate Dockerfile + docker-compose.yml first (references/docker.md), then:
docker compose run --rm web uv add 'django>=6.0,<7.0' django-environ
docker compose run --rm web uv run django-admin startproject config .
```

Every Python command from here goes through `docker compose run --rm web …` or `docker compose exec web …`. `.venv` must be in `.dockerignore` so an accidental host venv never enters the build context.

In `config/settings.py`, replace only `SECRET_KEY` / `DEBUG` / `ALLOWED_HOSTS` / `DATABASES`. Leave everything else `startproject` wrote.

## Settings — ask which structure

Use the snippets verbatim.

### Option A — single file

Replace the four named values in `config/settings.py`:

```python
from pathlib import Path
import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR / ".env")

DEBUG = env.bool("DJANGO_DEBUG", default=False)
SECRET_KEY = env("DJANGO_SECRET_KEY", default="django-insecure-build-only" if DEBUG else None)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])  # DEBUG already accepts localhost / 127.0.0.1 / [::1]
DATABASES = {"default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}" if DEBUG else None)}  # 4 slashes = absolute, survives running manage.py from any cwd
```

Defaults are gated by `DEBUG`: in production `DJANGO_DEBUG` is unset, the defaults vanish, and missing values raise `ImproperlyConfigured`.

### Option B — split (base / local / production)

```sh
mkdir config/settings
mv config/settings.py config/settings/base.py
touch config/settings/__init__.py
```

`config/settings/base.py` — same four-value replacement (note `BASE_DIR` jumps one level up):

```python
from pathlib import Path
import environ

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR / ".env")

DEBUG = env.bool("DJANGO_DEBUG", default=False)
SECRET_KEY = env("DJANGO_SECRET_KEY", default="django-insecure-build-only" if DEBUG else None)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])
DATABASES = {"default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}" if DEBUG else None)}  # 4 slashes = absolute, survives running manage.py from any cwd
```

`local.py` and `production.py` carry **only deltas** from `base.py`. Use them for things that only make sense per-environment: dev tooling (debug-toolbar, query loggers, relaxed CORS) in `local.py`; production hardening (HSTS, secure cookies, manifest static storage) in `production.py`. Never restate values base sets; never redeclare `MIDDLEWARE` / `INSTALLED_APPS` / `DATABASES` / `EMAIL_BACKEND` / `STORAGES`. Mutate inherited lists in place:

```python
# config/settings/local.py
from .base import *
```

```python
# config/settings/production.py
from .base import *

# MIDDLEWARE += [...]                      # order doesn't matter
# MIDDLEWARE.insert(1, "...")              # order matters (e.g. WhiteNoise after SecurityMiddleware)
```

Don't re-instantiate `env = environ.Env()` — it's already imported via `from .base import *`.

`manage.py` → `DJANGO_SETTINGS_MODULE = "config.settings.local"`.
`config/wsgi.py` and `config/asgi.py` → `DJANGO_SETTINGS_MODULE = "config.settings.production"`.

## Static files

```python
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
```

## .env.example and .env

Commit `.env.example` with every env var settings reads:

```sh
DJANGO_SECRET_KEY=replace-me
DJANGO_DEBUG=True
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
```

Then `cp .env.example .env` and set a real dev key:

```sh
uv run python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
```

`.env` is gitignored. Keep `.env.example` in sync as new `env(...)` calls land.

If a value contains `$` and the project uses `docker-compose` with `env_file:`, escape as `$$` — Compose interpolates `${VAR}` and `$VAR` otherwise.

## .gitignore

Must include `.venv/`, `.env`, `*.sqlite3`, `staticfiles/`, `media/`, `.ruff_cache/`. Add other standard Python / Django / editor / tooling entries before the first commit.

## Boot check

**uv on host**:

```sh
uv run manage.py migrate
uv run manage.py createsuperuser
uv run manage.py runserver
```

**docker-compose**:

```sh
docker compose up -d
docker compose exec web uv run manage.py migrate
docker compose exec web uv run manage.py createsuperuser
```

Confirm `/admin/` login works before continuing.

## Scripts (optional)

Only if the user asks for task shortcuts:

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
