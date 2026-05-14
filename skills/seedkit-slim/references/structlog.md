# structlog + django-structlog

```sh
uv add structlog django-structlog
```

`django_structlog` belongs in `INSTALLED_APPS`. Add `django_structlog.middlewares.RequestMiddleware` to `MIDDLEWARE` directly after `AuthenticationMiddleware` so log records carry `request_id` + the authenticated user.

## LOGGING — module scope in `base.py`

`ProcessorFormatter` is a **formatter**, not a handler. Putting it in `handlers[*]["class"]` raises `TypeError: Either processor or processors must be passed`. The handler uses stdlib `StreamHandler` and references the formatter by name.

```python
# config/settings/base.py
import structlog

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {
            "()": "structlog.stdlib.ProcessorFormatter",
            "processor": structlog.processors.JSONRenderer(),
        },
        "console": {
            "()": "structlog.stdlib.ProcessorFormatter",
            "processor": structlog.dev.ConsoleRenderer(colors=True),
        },
    },
    "handlers": {
        "default": {
            "class": "logging.StreamHandler",
            "formatter": "console" if DEBUG else "json",
        },
    },
    "root": {"handlers": ["default"], "level": "INFO"},
    "loggers": {
        "django_structlog": {"handlers": ["default"], "level": "INFO", "propagate": False},
    },
}

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.stdlib.ProcessorFormatter.wrap_for_formatter,  # MUST be last — hands off to LOGGING's formatter
    ],
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)
```

Define `LOGGING` at module scope (not inside `if DEBUG:`) so production picks it up. Pick the formatter via `DEBUG`, not by branching the whole dict.
