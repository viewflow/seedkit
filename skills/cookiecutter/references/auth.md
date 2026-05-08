# Authentication

Stock Django ships only barebones login/logout views and a `User` model. Pick one of the two add-ons:

- **`django-allauth`** — full account flows on top of Django: signup, email verification, password reset, optional social providers (Google / GitHub / etc.), 2FA support. The most-used auth library in the Django ecosystem.
- **`django-mail-auth`** — passwordless magic-link login. Single tiny dependency, no passwords stored, no social providers. Trade off feature breadth for simplicity.

If the user said "no auth add-on", skip this reference and stay on `django.contrib.auth` defaults.

Email backend (console / SMTP / Mailpit) must be configured first — both options send mail. See `references/email.md`.

---

## Option A — `django-allauth` (passwords, email verification, social login)

Use when the project needs traditional password login, email verification, password reset, or social providers (Google, GitHub, …).

### Install

```sh
uv add django-allauth
```

### Settings

In `config/settings.py` (or `config/settings/base.py` for split):

```python
INSTALLED_APPS = [
    ...
    "django.contrib.sites",
    "allauth",
    "allauth.account",
    # "allauth.socialaccount",  # uncomment if social providers are needed
]

MIDDLEWARE = [
    ...
    "allauth.account.middleware.AccountMiddleware",
]

AUTHENTICATION_BACKENDS = [
    "django.contrib.auth.backends.ModelBackend",
    "allauth.account.auth_backends.AuthenticationBackend",
]

SITE_ID = 1
LOGIN_REDIRECT_URL = "/"
LOGOUT_REDIRECT_URL = "/"

ACCOUNT_LOGIN_METHODS = {"email"}
ACCOUNT_SIGNUP_FIELDS = ["email*", "password1*", "password2*"]
ACCOUNT_EMAIL_VERIFICATION = "optional"   # dev default; tighten in production
```

In `config/settings/production.py` (split layout) — or gated on `not DEBUG` for single-file — require verified email:

```python
ACCOUNT_EMAIL_VERIFICATION = "mandatory"
```

(Mandatory verification with the console email backend means the verification link only appears in `runserver` stdout — fine for prod with real SMTP, painful for local signup.)

### URLs

In `config/urls.py`:

```python
urlpatterns = [
    ...
    path("accounts/", include("allauth.urls")),
]
```

### Migrate

```sh
uv run manage.py migrate
```

`django.contrib.sites` ships a default `Site` row at `pk=1` with `domain="example.com"` — allauth uses it for absolute URLs in verification / password-reset emails. Update it once per environment, either via Django admin (`/admin/sites/site/1/`) or a one-off data migration that reads `DJANGO_SITE_DOMAIN` / `DJANGO_SITE_NAME` from env. Forgetting this means email links point at `example.com`.

Allauth ships its own templates; override only when the user wants custom branding.

If a custom user model from `references/custom-user.md` is in use, drop the `username` field and use the email-as-`USERNAME_FIELD` variant — otherwise email-only signup will fail because `AbstractUser` requires a username. With `username = None` on the user model, also add to settings:

```python
ACCOUNT_USER_MODEL_USERNAME_FIELD = None
```

Without it, allauth's `get_username_max_length()` calls `User._meta.get_field("username")` and `/accounts/signup/` raises `FieldDoesNotExist`.

---

## Option B — `django-mail-auth` (passwordless / magic link)

Use when passwordless is acceptable and you want a single tiny dependency. Login flow: user enters email → gets a one-time link → clicks → logged in. No passwords stored, no social providers.

### Install

```sh
uv add django-mail-auth
```

### Settings

```python
INSTALLED_APPS = [
    ...
    "mailauth",
    "mailauth.contrib.user",   # optional: ships a User model with no password field
]

AUTHENTICATION_BACKENDS = [
    "mailauth.backends.MailAuthBackend",
    "django.contrib.auth.backends.ModelBackend",
]

LOGIN_URL = "mailauth:login"
LOGIN_REDIRECT_URL = "/"
```

If a custom user model from `references/custom-user.md` is in use, skip `mailauth.contrib.user` and keep the project's own `users.User`.

### URLs

```python
urlpatterns = [
    ...
    path("accounts/", include("mailauth.urls", namespace="mailauth")),
]
```

### Templates (required)

`django-mail-auth` does not ship default templates — `/accounts/login/` returns 500 without them. Create at minimum:

```html
{# templates/mailauth/login.html #}
{% extends "base.html" %}
{% block content %}
<form method="post">{% csrf_token %}{{ form }}<button>Send link</button></form>
{% endblock %}

{# templates/mailauth/login_email_sent.html #}
{% extends "base.html" %}
{% block content %}<p>Check your inbox.</p>{% endblock %}

{# templates/mailauth/email/login_email.html #}
<a href="{{ login_url }}">Sign in</a>

{# templates/mailauth/email/login_email_subject.txt #}
Sign in
```

Add `BASE_DIR / "templates"` to `TEMPLATES[0]["DIRS"]` if it isn't there already.

### Migrate

```sh
uv run manage.py migrate
```

Test the flow locally with the console email backend or Mailpit — the magic link is printed/captured there.
