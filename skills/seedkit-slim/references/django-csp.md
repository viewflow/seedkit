# django-csp

`django-csp >= 4.0` switched from flat `CSP_*` settings to a nested `CONTENT_SECURITY_POLICY` dict. The old keys raise `csp.E001` at startup.

```python
# config/settings.py (or base.py)
INSTALLED_APPS += ["csp"]
MIDDLEWARE += ["csp.middleware.CSPMiddleware"]  # after SecurityMiddleware

CONTENT_SECURITY_POLICY = {
    "DIRECTIVES": {
        "default-src": ("'self'",),
        "script-src": ("'self'",),
        "style-src": ("'self'", "'unsafe-inline'"),
        "img-src": ("'self'", "data:"),
        "connect-src": ("'self'",),
        "frame-ancestors": ("'none'",),
    },
}
```

Loosen per-environment by overriding `CONTENT_SECURITY_POLICY["DIRECTIVES"][...]` in `local.py`/`production.py` — never restate the whole dict.
