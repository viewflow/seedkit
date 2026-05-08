# New Django Project

## Create

```sh
uv init --bare {project_slug}     # --bare skips main.py / README.md / .python-version
cd {project_slug}
uv add django django-environ
uv run django-admin startproject config .
```

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

**config/settings/local.py**

```python
from .base import *
```

**config/settings/production.py**

```python
from .base import *
```

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

## .gitignore

Write a `.gitignore` for a Django + uv project. Must include `.venv/`, `.env`, `*.sqlite3`, `staticfiles/`, `media/`. Add the other standard Python / Django / editor / tooling entries you know belong. Do this before the first commit.

## Boot check

```sh
uv run manage.py migrate
uv run manage.py createsuperuser
uv run manage.py runserver
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
