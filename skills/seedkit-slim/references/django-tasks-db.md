# django-tasks (Database backend)

`django-tasks` core has no DB backend; `django-tasks-db` is a separate package.

```toml
# pyproject.toml
dependencies = [
    "django-tasks",
    "django-tasks-db",
]
```

```python
# settings.py
INSTALLED_APPS = [
    # ...
    "django_tasks",
    "django_tasks_db",  # ships migrations for the queue tables
]

TASKS = {
    "default": {
        "BACKEND": "django_tasks_db.DatabaseBackend",
        "QUEUES": ["default"],
    },
}
```

Worker: `uv run manage.py db_worker`.
