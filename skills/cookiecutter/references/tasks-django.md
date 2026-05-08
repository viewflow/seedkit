# Django Tasks (Django 6.0+)

Django 6.0 ships the `django.tasks` API in core: vendor-neutral `@task` decorator + `enqueue` / `enqueue_on_commit` / result-checking, modelled after `django.core.cache`. Pick a third-party backend for the actual queue. Lighter footprint than Celery (no broker if you pick the DB backend); but no Beat-equivalent scheduler, no chained workflows, no Flower-class UI yet.

Ask the user:

- **Database** — `tasks-django-db.md`. Simplest, no extra infrastructure.
- **Redis Queue** — `tasks-django-rq.md`. Needs Redis; better throughput.

Ask separately about **periodic tasks** (django-crontask) — `tasks-django-cron.md` if yes.

## Define and enqueue (both backends)

```python
from django.tasks import task

@task()
def send_welcome_email(user_id: int) -> None:
    ...
```

```python
from django.db import transaction

# Enqueue after the current transaction commits to avoid race conditions
transaction.on_commit(lambda: send_welcome_email.enqueue(user.id))
```
