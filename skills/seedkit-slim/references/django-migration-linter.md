# django-migration-linter

The `lintmigrations` management command is only registered when the app is installed.

```python
# settings (base.py or single file)
INSTALLED_APPS += ["django_migration_linter"]

MIGRATION_LINTER_OPTIONS = {
    # third-party migrations trip false positives; lint only first-party apps
    "exclude_apps": ["silk", "django_tasks_db", "django_rq", "axes"],
}
```

Run: `uv run manage.py lintmigrations`.
