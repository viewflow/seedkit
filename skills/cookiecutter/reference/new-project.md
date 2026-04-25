# New Django Project

## Create

```sh
uv init {project_slug}
cd {project_slug}
uv add django django-environ
uv run django-admin startproject config .
```

## Settings — ask the user which structure they prefer

---

### Option A: Single settings file (simpler)

Keep `config/settings.py` in place. Remove `SECRET_KEY`, `DEBUG`, `ALLOWED_HOSTS` and `DATABASES` — add at the top:

```python
from pathlib import Path
import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR / ".env")

SECRET_KEY = env("DJANGO_SECRET_KEY")
DEBUG = env.bool("DJANGO_DEBUG", default=False)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])
DATABASES = {"default": env.db("DATABASE_URL")}
```

`manage.py`, `config/wsgi.py`, and `config/asgi.py` keep the default `DJANGO_SETTINGS_MODULE = "config.settings"`.

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

SECRET_KEY = env("DJANGO_SECRET_KEY")
DEBUG = env.bool("DJANGO_DEBUG", default=False)
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])
DATABASES = {"default": env.db("DATABASE_URL")}
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

## .env

```sh
DJANGO_SECRET_KEY=local-dev-secret-key-change-in-production
DJANGO_DEBUG=True
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
DATABASE_URL=sqlite:///db.sqlite3
```

## .gitignore

Create `.gitignore` for Django + uv.

## Run

```sh
uv run manage.py migrate
uv run manage.py runserver
```

## Scripts

Add [Poe the Poet](https://poethepoet.natn.io/) for cross-platform task shortcuts:

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

Run any task with `uv run poe <name>`:

```sh
uv run poe dev
uv run poe migrate
uv run poe test
uv run poe lint
```
