# Database safety

Three tools that catch database mistakes before they reach production.

- **django-zeal** — raises an exception in dev when ORM code produces N+1 queries. No configuration beyond `INSTALLED_APPS`; catches the problem at the exact line that caused it.
- **django-migration-linter** — static-analyses every migration for dangerous operations: adding a NOT NULL column without a default on a large table, dropping a column, renaming without a transition period, etc. Runs as a management command or in CI.
- **django-test-migrations** — pytest fixture that applies and rolls back individual migrations in tests. Verifies a migration is reversible and that the `RunPython` forwards/backwards functions are correct.

Ask: which of these to include? Each is independent; all three are dev-only deps.

## django-zeal

### Install

```sh
uv add --dev django-zeal
```

### Settings (local / DEBUG-gated)

```python
# config/settings/local.py  (or DEBUG-gated block in single settings)
if DEBUG:
    INSTALLED_APPS += ["zeal"]
    MIDDLEWARE += ["zeal.middleware.zeal_middleware"]   # required to scope detection per request
    ZEAL_RAISE_ON_VIOLATION = True
```

### Silencing intentional N+1s

When a queryset is genuinely unavoidable (e.g. a management command that processes rows one at a time by design):

```python
from zeal import zeal_ignore

with zeal_ignore():
    for obj in MyModel.objects.all():
        do_something(obj.related_set.all())
```

Or silence a specific access pattern permanently:

```python
# config/settings/local.py
ZEAL_SILENCED_WARNINGS = [
    {"model": "myapp.MyModel", "field": "related_set"},
]
```

### pytest

Zeal works automatically in pytest-django tests that hit the DB — no extra setup needed.

## django-migration-linter

### Install

```sh
uv add --dev django-migration-linter
```

### Settings (local / DEBUG-gated)

```python
# config/settings/local.py
if DEBUG:
    INSTALLED_APPS += ["django_migration_linter"]   # registers the `lintmigrations` command
```

### Run

```sh
uv run manage.py lintmigrations
```

Exits non-zero if any migration contains a dangerous operation. Safe to run locally and in CI.

Exclude third-party apps (they maintain their own migrations):

```sh
uv run manage.py lintmigrations --exclude-apps allauth account socialaccount
```

### CI step

Add after `uv sync --frozen` and before the test step in `.github/workflows/test.yml`:

```yaml
      - run: uv run manage.py lintmigrations --exclude-apps allauth account socialaccount
```

### setup.cfg (optional — persist the exclusion list)

`django-migration-linter` reads `setup.cfg`, not `pyproject.toml`:

```ini
[django_migration_linter]
exclude_apps = silk,allauth,account,socialaccount
```

## django-test-migrations

Requires pytest + pytest-django (see `references/pytest.md`). Skip if the project uses `manage.py test`.

### Install

```sh
uv add --dev django-test-migrations
```

### Usage

If `startapp` already created `myapp/tests.py`, delete it before creating the `tests/` package — Django can't import both.

```python
# myapp/tests/test_migrations.py
import pytest
from django_test_migrations.contrib.unittest_case import MigratorTestCase

# pytest style
def test_migration_forward_and_back(migrator):
    old_state = migrator.apply_initial_migration(("myapp", "0001_initial"))
    new_state = migrator.apply_tested_migration(("myapp", "0002_add_status"))

    MyModel = new_state.apps.get_model("myapp", "MyModel")
    assert MyModel.objects.filter(status="active").count() == 0

    migrator.reset()  # rolls back to 0001 — verifies the backwards() function runs
```

The `migrator` fixture is provided by `django-test-migrations`; no extra `conftest.py` needed.

Write a migration test whenever a `RunPython` operation transforms data or when the migration is irreversible by design (document with `reverse_code=migrations.RunPython.noop` and a comment explaining why).
