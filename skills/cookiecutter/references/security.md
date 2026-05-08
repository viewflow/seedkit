# Security
# https://docs.djangoproject.com/en/6.0/topics/security/

## config/settings/production.py

```python
# HTTPS
SECURE_SSL_REDIRECT = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# Cookies
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True

# HSTS
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

# Required behind a TLS-terminating proxy (Caddy / nginx / load balancer)
# whenever Django sees the request as HTTP. Without it, admin / allauth
# POSTs return 403 with "Origin checking failed".
CSRF_TRUSTED_ORIGINS = env.list("DJANGO_CSRF_TRUSTED_ORIGINS", default=[])
```
