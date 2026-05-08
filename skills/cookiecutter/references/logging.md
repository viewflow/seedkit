# Logging — structured (structlog)

Pretty console in dev, JSON lines in production. Foreign loggers (Django, Celery, urllib3, …) flow through the same stream and format because both renderers are stdlib `logging` formatters wrapped by `structlog.stdlib.ProcessorFormatter`. Per-request context (`request_id`, `user_id`) is attached via `contextvars` so every log line — including ones from Django internals — carries it without manual plumbing.

## Install

```sh
uv add structlog
```

## Settings

In `config/settings.py` (or `config/settings/base.py` for split). The pre/post processor split is what lets stdlib log records (Django, third parties) and structlog log records share one renderer.

```python
import logging

import structlog

# Processors that run for *every* log record before the formatter renders it.
# Used both in structlog.configure() (foreign_pre_chain target) and as
# `foreign_pre_chain` in the formatter, so non-structlog records get them too.
PRE_CHAIN = [
    structlog.contextvars.merge_contextvars,
    structlog.stdlib.add_log_level,
    structlog.stdlib.add_logger_name,
    structlog.processors.TimeStamper(fmt="iso", utc=True),
    structlog.processors.StackInfoRenderer(),
    structlog.processors.format_exc_info,
]

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {
            "()": "structlog.stdlib.ProcessorFormatter",
            "processor": structlog.processors.JSONRenderer(),
            "foreign_pre_chain": PRE_CHAIN,
        },
        "console": {
            "()": "structlog.stdlib.ProcessorFormatter",
            "processor": structlog.dev.ConsoleRenderer(colors=True),
            "foreign_pre_chain": PRE_CHAIN,
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "console" if DEBUG else "json",
        },
    },
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        # Quiet noisy stdlib / third-party loggers in prod; raise to DEBUG locally if needed.
        "django.db.backends": {"level": "WARNING"},
        "django.request": {"level": "WARNING"},
        "urllib3": {"level": "WARNING"},
        "botocore": {"level": "WARNING"},
        "celery": {"level": "INFO"},
    },
}

structlog.configure(
    processors=[
        *PRE_CHAIN,
        # Hand off to the stdlib formatter (defined above) so structlog and
        # stdlib records render identically.
        structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
    ],
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)
```

## Per-request context

Bind `request_id` and (if available) `user_id` to `contextvars` so every log emitted while the request is on the call stack carries them. Add a tiny middleware:

```python
# config/middleware/logging.py
import uuid

import structlog


class RequestContextMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(
            request_id=request.headers.get("X-Request-ID") or uuid.uuid4().hex,
            user_id=getattr(getattr(request, "user", None), "id", None),
        )
        try:
            return self.get_response(request)
        finally:
            structlog.contextvars.clear_contextvars()
```

Insert near the top of `MIDDLEWARE` (after `SecurityMiddleware`, before anything else that logs):

```python
MIDDLEWARE.insert(1, "config.middleware.logging.RequestContextMiddleware")
```

For Celery tasks, bind the same way at task entry:

```python
from celery.signals import task_prerun, task_postrun
import structlog

@task_prerun.connect
def _bind_task(task_id=None, task=None, **_):
    structlog.contextvars.bind_contextvars(task_id=task_id, task_name=task.name)

@task_postrun.connect
def _clear_task(**_):
    structlog.contextvars.clear_contextvars()
```

## Sentry / GlitchTip / Bugsink integration

If `references/error-reporting.md` is configured, sentry-sdk's `LoggingIntegration` is enabled by default — every `WARNING+` log record becomes a Sentry breadcrumb and every `ERROR+` becomes a Sentry event. No extra wiring. To suppress a specific noisy logger from Sentry, add it to `LoggingIntegration(level=…, event_level=…)` overrides.

## Use

```python
import structlog

log = structlog.get_logger(__name__)

# free-form key-value pairs — JSON in prod, key=value in dev
log.info("user_signed_up", user_id=user.id, plan="free")
log.warning("payment_retry", invoice_id=inv.id, attempt=3)

# bind context for a scope:
log = log.bind(order_id=order.id)
log.info("order_paid")          # carries order_id
log.info("invoice_sent")        # also carries order_id

# exceptions:
try:
    do_thing()
except ValueError:
    log.exception("thing_failed", thing_id=thing.id)
```

## Tests

In `pytest`/`unittest`, capture log records with `caplog` (pytest) or `assertLogs`. Records carry the structlog event-dict as `record.msg` (a string) — assert against the rendered output rather than the dict, or use `structlog.testing.capture_logs()`:

```python
from structlog.testing import capture_logs

def test_signup_logs_event():
    with capture_logs() as cap:
        client.post("/signup/", {...})
    assert any(e["event"] == "user_signed_up" for e in cap)
```

## Common pitfalls

- **Don't call `structlog.configure()` at import time of an app module.** Settings is the only safe place — it's loaded exactly once before any logger is touched.
- **Keep `cache_logger_on_first_use=True`.** Without it, every `get_logger()` re-runs the processor chain setup, slowing hot paths.
- **Don't ship `ConsoleRenderer` to prod.** ANSI colour codes pollute log aggregators and break JSON parsers.
- **`exc_info=True` is implicit in `log.exception(...)`.** Don't double-log it manually.
