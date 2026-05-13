# New Django Project

Foundation conventions for §1. Use the snippets verbatim.

## Create

```sh
uv init --bare {project_slug}
cd {project_slug}
sed -i.bak -E 's/^requires-python = .*/requires-python = ">=3.12"/' pyproject.toml && rm pyproject.toml.bak
printf '\n[tool.uv]\npackage = false\n' >> pyproject.toml  # Django apps aren't installable packages — without this, uv sync invokes hatchling and fails
uv add 'django>=6.0,<7.0' django-environ
uv run django-admin startproject config .
```

Add dev tools with `uv add --group dev <pkg>` — that writes to the PEP 735 `[dependency-groups]` table. The older `[tool.uv] dev-dependencies` key is deprecated in uv 0.11+.

## Settings — single file

Replace only `SECRET_KEY` / `DEBUG` / `ALLOWED_HOSTS` / `DATABASES` in `config/settings.py`:

```python
from pathlib import Path
import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env()
_env_file = BASE_DIR / ".env"
if _env_file.exists():
    environ.Env.read_env(_env_file)  # Docker images have no .env; bare read_env() raises FileNotFoundError

DEBUG = env.bool("DJANGO_DEBUG", default=False)
SECRET_KEY = env("DJANGO_SECRET_KEY", default="django-insecure-build-only" if DEBUG else env.NOTSET)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])
DATABASES = {"default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}" if DEBUG else env.NOTSET)}  # 4 slashes = absolute path
```

Delete the hardcoded `DATABASES` block + `# Database` comment that `startproject` emitted — bottom wins, leaving both makes `DATABASE_URL` dead code.

In production `DJANGO_DEBUG` is unset and `env.NOTSET` makes django-environ raise `ImproperlyConfigured` naming the missing variable.

## Settings — split (base / local / production)

`base.py` carries the same four-value replacement (note `BASE_DIR` jumps one extra level). `local.py` / `production.py` / `test.py` carry only deltas — never restate `MIDDLEWARE` / `INSTALLED_APPS` / `DATABASES`. Edit `DJANGO_SETTINGS_MODULE` in `manage.py` (→ `config.settings.local`), `config/wsgi.py` and `config/asgi.py` (→ `config.settings.production`).

## Root URL

`startproject`'s `config/urls.py` only routes `/admin/`, so `/` 404s. Add a redirect:

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

```sh
# .env.example
DJANGO_SECRET_KEY=replace-me
DJANGO_DEBUG=True
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
```

`cp .env.example .env`, then write a real dev key with `secrets.token_urlsafe(50)` — not Django's `get_random_secret_key()` (its `$ & ( ) ' " \` output breaks shell sourcing and Compose interpolation).

## .gitignore

Must include `.venv/`, `.env`, `*.sqlite3`, `staticfiles/`, `media/`, `.ruff_cache/`. Add standard Python / Django / editor entries before the first commit.

## Boot check

```sh
uv run manage.py migrate
uv run manage.py createsuperuser
uv run manage.py runserver --noreload &
until curl -sf http://127.0.0.1:8000/admin/login/ >/dev/null; do sleep 0.2; done
kill %1; wait
```

`--noreload` avoids the autoreloader child that `kill $(jobs -p)` would orphan.
