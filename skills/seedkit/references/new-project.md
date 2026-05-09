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

uv runs on the host to manage `pyproject.toml` / `uv.lock` / `manage.py`; the container runs the actual server. This is fine because `.venv` is gitignored and dockerignored — the image rebuilds its own `.venv` from the lockfile, never the host's.

```sh
uv init --bare {project_slug}
cd {project_slug}
uv add 'django>=6.0,<7.0' django-environ
uv run django-admin startproject config .
# Generate Dockerfile.dev + docker-compose.yml (references/docker.md), then:
docker compose up -d --build
```

`.dockerignore` must include `.venv/`. Adding a dependency later: `uv add foo` on host, `docker compose build web` to refresh the image. Python commands inside the container go through `docker compose exec web python manage.py …`.

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

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
```

Defaults are gated by `DEBUG`: in production `DJANGO_DEBUG` is unset, the defaults vanish, and missing values raise `ImproperlyConfigured`.

After inserting these lines at the top of `settings.py`, delete the original hardcoded `DATABASES` block that `startproject` generated (the `# Database` comment + the dict). Use a single Edit that replaces the entire block — don't leave it in place or it will shadow the env-driven definition above it.

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

## Root URL

`startproject`'s `config/urls.py` only routes `/admin/`, so `/` 404s. Add a redirect so the starter is usable out of the box; replace once the project has a real home view.

```python
# config/urls.py
from django.contrib import admin
from django.urls import path
from django.views.generic import RedirectView

urlpatterns = [
    path("", RedirectView.as_view(url="/admin/", permanent=False)),
    path("admin/", admin.site.urls),
]
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
uv run python -c "import secrets; print(secrets.token_urlsafe(50))"
```

Use `secrets.token_urlsafe`, not Django's `get_random_secret_key()`. `get_random_secret_key()` draws from `string.printable[:64]` and freely emits `$`, `&`, `(`, `)`, `'`, `"`, `\` — all of which break (a) shell sourcing of `.env`, (b) Docker Compose `env_file:` (which interprets `$VAR` / `${VAR}`), and (c) any naive `sed` rewrite of the file. `token_urlsafe` produces `[A-Za-z0-9_-]` only — safe to drop in unquoted, anywhere. Django doesn't care about the alphabet, only the entropy.

Write the new key directly into `.env` (don't `sed` it in — a key containing `&` or `/` would mangle the sed replacement string):

```sh
KEY=$(uv run python -c "import secrets; print(secrets.token_urlsafe(50))")
uv run python -c "
import pathlib, re, sys
p = pathlib.Path('.env')
p.write_text(re.sub(r'^DJANGO_SECRET_KEY=.*$', f'DJANGO_SECRET_KEY=$KEY', p.read_text(), flags=re.M))
"
```

`.env` is gitignored. Keep `.env.example` in sync as new `env(...)` calls land.

For other secrets (DB passwords, API keys you cannot regenerate) that may contain `$` or quotes, either single-quote the value (`KEY='!@#$%'`) — django-environ accepts both single and double quotes — or, if the file is consumed by Docker Compose's `env_file:`, also escape `$` as `$$` (Compose interpolates `${VAR}` and `$VAR`). The `secrets.token_urlsafe` recommendation above sidesteps this problem entirely for `DJANGO_SECRET_KEY`.

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
test    = "python manage.py test"     # or "pytest" if `references/pytest.md` was applied
lint    = "ruff check ."
```

Run with `uv run poe <name>`.
