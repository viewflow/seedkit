# Auth hardening — django-axes + 2FA

Two follow-up questions to Auth. Fire **only when** `auth ≠ none` (without an auth flow there's nothing to harden).

- `axes`: brute-force / lockout protection. Default **yes** when auth is selected.
- `2fa`: TOTP via built-in `allauth.mfa` (paired with `django-allauth`) or `django-otp` (paired with `django-mail-auth` or stock auth). Default **no** — opt-in.

## django-axes (lockout / brute-force)

Wraps the login path. Records every authentication attempt; locks an IP / username after N failures for a cool-off window.

### Install

```sh
uv add django-axes
```

### `base.py`

```python
INSTALLED_APPS = [
    # ...
    'axes',
]

MIDDLEWARE = [
    # ...
    # MUST be the last entry — wraps every other middleware's auth attempts.
    'axes.middleware.AxesMiddleware',
]

AUTHENTICATION_BACKENDS = [
    'axes.backends.AxesBackend',
    # then the project's existing backends, e.g.:
    'django.contrib.auth.backends.ModelBackend',
    # 'allauth.account.auth_backends.AuthenticationBackend',
    # 'mailauth.backends.MailAuthBackend',
]

# Sane defaults — adjust per project tolerance.
AXES_FAILURE_LIMIT = 5
AXES_COOLOFF_TIME = 1          # hours
AXES_LOCKOUT_PARAMETERS = ['ip_address', 'username']
AXES_RESET_ON_SUCCESS = True
```

`AxesBackend` must be **first** in `AUTHENTICATION_BACKENDS`. Wrong order silently disables lockout.

### Migrate

`axes` ships its own models:

```sh
uv run manage.py migrate
```

### Pitfalls

- Behind a reverse proxy the `IP_address` lockout dimension only works if `IPWARE` (or the equivalent) is reading `X-Forwarded-For`. With WhiteNoise / Caddy / nginx wired correctly this is fine; check by hitting the login form from a known IP and reading `axes_accessattempt`.
- `axes` writes one DB row per failed attempt. On heavy public-facing forms, switch the cache backend (`AXES_HANDLER = 'axes.handlers.cache.AxesCacheHandler'`) — requires Redis (`references/redis.md`).

## 2FA

Pick the matching package for the chosen Auth flow:

- **`django-allauth`** → use the built-in **`allauth.mfa`** (`uv add 'django-allauth[mfa]'`). MFA is shipped inside django-allauth itself since 0.56; the third-party `allauth-2fa` package is unmaintained and incompatible with django-allauth ≥ 0.58 — do **not** install it. Add `allauth.mfa` to `INSTALLED_APPS`, include `allauth.mfa.urls` in the `accounts/` include, and run migrations. Users opt in from the account page; templates ship with allauth.
- **`django-mail-auth` or stock auth** → use **`django-otp`** + `django-otp-totp` (`uv add 'django-otp[qrcode]'`). Adds `django_otp`, `django_otp.plugins.otp_totp` to `INSTALLED_APPS`, `django_otp.middleware.OTPMiddleware` to `MIDDLEWARE` (after `AuthenticationMiddleware`). Wire admin login through `django_otp.admin.OTPAdminSite` if 2FA on `/admin/` is wanted.

For both: run migrations, then ship a UI flow for the user to enrol a TOTP secret (`allauth.mfa` includes templates; `django-otp` does not — wire your own).

### Settings — `production.py` only when allauth.mfa is used

```python
# Only force 2FA in prod; leave it optional in dev so seeded superusers can log in.
# `allauth.mfa` setting; replaces the old `ACCOUNT_LOGIN_BY_2FA_REQUIRED` from
# the deprecated allauth-2fa package.
MFA_TOTP_ISSUER = env("DJANGO_SITE_DOMAIN", default="example.com")
ACCOUNT_LOGIN_METHODS = {"email"}      # already set by Auth — re-stating intent
MFA_SUPPORTED_TYPES = ["totp", "recovery_codes"]
ACCOUNT_REAUTHENTICATION_REQUIRED = True
```

### Pitfalls

- 2FA + axes together: failed 2FA codes count as auth failures in axes. That's usually correct — verify the `AXES_LOCKOUT_PARAMETERS` aren't so aggressive that legitimate users get locked out for one mistyped code.
- Pin `django-allauth >= 0.58` so `allauth.mfa` is available; never co-install `allauth-2fa`.
- `MFA_TOTP_ISSUER` should be the human-readable site name / domain, not the project slug — that string is what shows up in the user's authenticator app.
- TOTP requires accurate server time. Clock skew > 30s on the host = users fail to authenticate. Document NTP requirement in `README.md`.
