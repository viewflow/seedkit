# Logging — structured (structlog)

Pretty console in dev, JSON lines in prod. Foreign loggers (Django, Celery, urllib3) render identically because both renderers are stdlib `logging` formatters wrapped by `ProcessorFormatter`. Per-request `request_id` / `user_id` flow via `contextvars`.

## Install

```sh
uv add structlog
```

## Settings

In `config/settings.py` (or `config/settings/base.py` for split):

```python
import structlog

# Shared chain. Used as `foreign_pre_chain` (stdlib records) and inside
# structlog.configure() (structlog-native records). Each record runs it once.
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
        "django.db.backends": {"level": "WARNING"},
        "django.request": {"level": "WARNING"},
        "urllib3": {"level": "WARNING"},
        "botocore": {"level": "WARNING"},
        "celery": {"level": "INFO"},
    },
}

structlog.configure(
    processors=[*PRE_CHAIN, structlog.stdlib.ProcessorFormatter.wrap_for_formatter],
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)
```

## Per-request context

```python
# config/middleware/logging.py
import uuid
import structlog

# Skip user-id binding for paths that must not block on the DB. Reading
# `request.user.id` triggers AuthenticationMiddleware's lazy lookup, so
# /healthz and /readyz would otherwise become contingent on auth-DB
# health — defeating the point of a liveness probe.
_NO_USER_PATHS = ("/healthz", "/readyz")


class RequestContextMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        structlog.contextvars.clear_contextvars()
        ctx = {"request_id": request.headers.get("X-Request-ID") or uuid.uuid4().hex}
        if not request.path.startswith(_NO_USER_PATHS):
            ctx["user_id"] = getattr(getattr(request, "user", None), "id", None)
        structlog.contextvars.bind_contextvars(**ctx)
        try:
            return self.get_response(request)
        finally:
            structlog.contextvars.clear_contextvars()
```

```python
# Insert AFTER AuthenticationMiddleware. request.user only exists once
# AuthenticationMiddleware has run; binding earlier always sets user_id=None.
auth_idx = MIDDLEWARE.index("django.contrib.auth.middleware.AuthenticationMiddleware")
MIDDLEWARE.insert(auth_idx + 1, "config.middleware.logging.RequestContextMiddleware")
```

Always-on. `LOGGING` belongs at module scope in `base.py` — never inside an `if DEBUG:` block, or production runs with bare Django defaults (no console handler at the root level).

For Celery tasks:

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

## Sentry / GlitchTip / Bugsink

If `error-reporting.md` is in use, sentry-sdk's `LoggingIntegration` already routes `WARNING+` to breadcrumbs and `ERROR+` to events. Override per-logger via `LoggingIntegration(level=…, event_level=…)`.

## Use

```python
import structlog

log = structlog.get_logger(__name__)

log.info("user_signed_up", user_id=user.id, plan="free")
log.warning("payment_retry", invoice_id=inv.id, attempt=3)

log = log.bind(order_id=order.id)
log.info("order_paid")
log.info("invoice_sent")

try:
    do_thing()
except ValueError:
    log.exception("thing_failed", thing_id=thing.id)
```

## Tests

```python
from structlog.testing import capture_logs

def test_signup_logs_event():
    with capture_logs() as cap:
        client.post("/signup/", {...})
    assert any(e["event"] == "user_signed_up" for e in cap)
```

## Pitfalls

- Call `structlog.configure()` only from settings (loaded once, before any logger).
- Keep `cache_logger_on_first_use=True`.
- No `ConsoleRenderer` in prod — ANSI codes break JSON parsers.
- `log.exception(...)` already implies `exc_info=True`; don't pass it again.
