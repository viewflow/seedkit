# django-migration-linter

The `lintmigrations` management command is only registered when the app is installed. Dev-only.

```sh
uv add --group dev django-migration-linter
```

```python
# config/settings.py (or local.py in a split layout — keep out of base.py)
if DEBUG:
    INSTALLED_APPS += ["django_migration_linter"]
```

Configure via `setup.cfg` at the project root. The Django app label for `django-tasks-db` is `django_tasks_database` (the package ships its AppConfig under that label).

```ini
# setup.cfg
[django_migration_linter]
exclude_apps = silk,django_tasks_database,django_rq,axes
```

Run: `uv run manage.py lintmigrations`.
