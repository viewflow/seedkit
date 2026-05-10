# Security
# https://docs.djangoproject.com/en/6.0/topics/security/

## config/settings/production.py

```python
# HTTPS
SECURE_SSL_REDIRECT = True
# Exempt healthcheck endpoints — managed-platform internal probes (Fly,
# Railway, k8s) hit the container directly without traversing the TLS
# proxy, so they arrive as plain HTTP and would be 301-redirected,
# making the probe never see 200.
SECURE_REDIRECT_EXEMPT = [r"^healthz$", r"^readyz$"]

# X-Forwarded-Proto trust. ONLY enable when there's a TLS-terminating proxy
# (Caddy / nginx / managed load balancer) in front of gunicorn. Without one,
# any client on the open port can spoof X-Forwarded-Proto: https and Django
# will treat the request as secure — bypassing SECURE_SSL_REDIRECT and
# CSRF cookie protections.
if env.bool("DJANGO_BEHIND_PROXY", default=False):
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# Cookies
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True

# HSTS
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = False   # opt in only after every subdomain serves HTTPS
SECURE_HSTS_PRELOAD = False              # opt in only after manual review of the consequences

# Other browser hardening
SECURE_REFERRER_POLICY = "same-origin"
SECURE_CONTENT_TYPE_NOSNIFF = True       # Django default but worth being explicit

# Required behind a TLS-terminating proxy whenever Django sees the request
# as HTTP. Without it, admin / allauth POSTs return 403 with "Origin
# checking failed".
CSRF_TRUSTED_ORIGINS = env.list("DJANGO_CSRF_TRUSTED_ORIGINS", default=[])
```
