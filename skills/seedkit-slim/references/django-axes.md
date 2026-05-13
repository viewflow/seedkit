# django-axes

Brute-force lockout. Wire in `base.py`:

```python
INSTALLED_APPS += ['axes']

# AxesMiddleware must be the LAST middleware — wraps every other middleware's auth attempts.
MIDDLEWARE += ['axes.middleware.AxesMiddleware']

# AxesBackend must be FIRST — wrong order silently disables lockout.
AUTHENTICATION_BACKENDS = [
    'axes.backends.AxesBackend',
    'django.contrib.auth.backends.ModelBackend',
]

AXES_FAILURE_LIMIT = 5
AXES_COOLOFF_TIME = 1  # hours
AXES_LOCKOUT_PARAMETERS = ['ip_address', 'username']
AXES_RESET_ON_SUCCESS = True
```

Don't set `AXES_LOCKOUT_CALLABLE` — `axes.helpers.lockout_response` was removed in v8. The default lockout response is correct.

In `production.py`, when Redis is in scope:

```python
AXES_HANDLER = 'axes.handlers.cache.AxesCacheHandler'
```

`axes` ships its own models — run `migrate` after install.
