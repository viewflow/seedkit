# django-tasks-rq

RQ backend for `django-tasks`. Wiring:

```python
# settings.py
INSTALLED_APPS = [
    # ...
    "django_rq",          # ships migrations — required even when using django-tasks-rq
    "django_tasks",
    "django_tasks_rq",
]

TASKS = {
    "default": {
        "BACKEND": "django_tasks_rq.backend.RQBackend",  # module is "backend" (singular), not "backends"
        "QUEUES": ["default"],
    },
}

RQ_QUEUES = {"default": {"URL": env("REDIS_URL", default="redis://127.0.0.1:6379/0")}}
RQ = {"JOB_CLASS": "django_tasks_rq.Job"}
```

Worker: `uv run manage.py rqworker default`.
