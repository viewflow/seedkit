# New Django Project

Bootstrap with uv on the host. Docker (`references/docker.md`) only
changes how the project runs — its `.venv` rebuilds from the
`pyproject.toml` / `uv.lock` written here.

## Create

```sh
uv init --bare {project_slug}     # --bare: no main.py / README.md / .python-version
cd {project_slug}
uv add 'django>=6.0,<7.0' django-environ
uv run django-admin startproject config .
```

In `config/settings.py`, replace only `SECRET_KEY` / `DEBUG` /
`ALLOWED_HOSTS` / `DATABASES`. Leave everything else `startproject` wrote.

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
SECRET_KEY = env("DJANGO_SECRET_KEY", default="django-insecure-build-only" if DEBUG else env.NOTSET)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])  # DEBUG already accepts localhost / 127.0.0.1 / [::1]
DATABASES = {"default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}" if DEBUG else env.NOTSET)}  # 4 slashes = absolute, survives running manage.py from any cwd

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
```

Defaults are gated by `DEBUG`: in production `DJANGO_DEBUG` is unset and
`env.NOTSET` makes `django-environ` raise `ImproperlyConfigured` naming
the missing variable. Don't write `default=None` for the prod branch —
`env.db(default=None)` crashes on URL parsing and `env(default=None)`
silently propagates `None` into Django settings.

After inserting these lines at the top of `settings.py`, delete the
original hardcoded `DATABASES` block + `# Database` comment that
`startproject` emitted — leaving both makes `DATABASE_URL` dead code.

### Option B — split (base / local / production)

```sh
mkdir config/settings
mv config/settings.py config/settings/base.py
touch config/settings/__init__.py
```

`config/settings/base.py` — same four-value replacement (note `BASE_DIR`
jumps one level up):

```python
from pathlib import Path
import environ

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR / ".env")

DEBUG = env.bool("DJANGO_DEBUG", default=False)
SECRET_KEY = env("DJANGO_SECRET_KEY", default="django-insecure-build-only" if DEBUG else env.NOTSET)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])
DATABASES = {"default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}" if DEBUG else env.NOTSET)}  # 4 slashes = absolute, survives running manage.py from any cwd
```

`local.py`, `production.py`, and `test.py` carry **only deltas** from
`base.py`. `test.py` overrides what tests need cheap and deterministic —
locmem email + cache, fast password hasher, eager task backend, in-memory
storage, `DEBUG=False` to surface template errors. Never restate values
base sets; never redeclare `MIDDLEWARE` / `INSTALLED_APPS` / `DATABASES`
/ `EMAIL_BACKEND` / `STORAGES`. Mutate inherited lists in place:

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

Don't re-instantiate `env = environ.Env()` — it's already imported via
`from .base import *`.

`manage.py` → `DJANGO_SETTINGS_MODULE = "config.settings.local"`.
`config/wsgi.py` and `config/asgi.py` → `DJANGO_SETTINGS_MODULE = "config.settings.production"`.

## Static files

```python
STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
```

## Root URL

`startproject`'s `config/urls.py` only routes `/admin/`, so `/` 404s.
Add a redirect so the starter is usable out of the box; replace once
the project has a real home view.

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
KEY=$(uv run python -c "import secrets; print(secrets.token_urlsafe(50))")
uv run python -c "
import pathlib, re
p = pathlib.Path('.env')
p.write_text(re.sub(r'^DJANGO_SECRET_KEY=.*$', f'DJANGO_SECRET_KEY=$KEY', p.read_text(), flags=re.M))
"
```

Use `secrets.token_urlsafe`, not Django's `get_random_secret_key()`.
The latter emits `$ & ( ) ' " \`, which breaks shell sourcing,
Compose's `$VAR` interpolation, and naive `sed` rewrites. `token_urlsafe`
produces `[A-Za-z0-9_-]` only.

`.env` is gitignored. Keep `.env.example` in sync as new `env(...)`
calls land.

## .gitignore

Must include `.venv/`, `.env`, `*.sqlite3`, `staticfiles/`, `media/`,
`.ruff_cache/`. Add other standard Python / Django / editor / tooling
entries before the first commit.

## Boot check

```sh
uv run manage.py migrate
uv run manage.py createsuperuser
uv run manage.py runserver
```

For docker-compose, see `references/docker.md`. Confirm `/admin/` login
works before continuing.

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
