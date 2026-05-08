# Authentication

Stock Django ships barebones login/logout views and a `User` model. Pick one add-on:

- **`django-allauth`** — full account flows: signup, email verification, password reset, optional social providers (Google / GitHub), 2FA. The most-used auth library in the Django ecosystem.
- **`django-mail-auth`** — passwordless magic-link. Single tiny dependency, no passwords, no social providers.

If "no auth add-on", skip this reference.

Email backend (`references/email.md`) must be configured first — both options send mail.

---

## Option A — `django-allauth`

### Install

```sh
uv add django-allauth
```

### Settings

```python
INSTALLED_APPS = [
    ...
    "django.contrib.sites",
    "allauth",
    "allauth.account",
    # "allauth.socialaccount",   # uncomment for social providers
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
ACCOUNT_EMAIL_VERIFICATION = "optional"   # tightened in production
```

In `production.py` (or gate on `not DEBUG`):

```python
ACCOUNT_EMAIL_VERIFICATION = "mandatory"
```

Mandatory + console email = verification link only in `runserver` stdout — fine in prod with real SMTP, painful for local signup.

### URLs

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

`django.contrib.sites` ships a default Site row (`pk=1`, `domain="example.com"`) used for absolute URLs in verification / password-reset emails. Update it per environment via admin (`/admin/sites/site/1/`) or a data migration reading `DJANGO_SITE_DOMAIN` from env. Forgetting it sends links pointing at `example.com`.

Allauth ships its own templates; override only for branding.

### With a custom user model

If `references/custom-user.md` is applied, use the email-as-`USERNAME_FIELD` variant — `AbstractUser` requires a username, so plain subclassing fails email-only signup. Also add:

```python
ACCOUNT_USER_MODEL_USERNAME_FIELD = None
```

Without it, allauth's `get_username_max_length()` calls `User._meta.get_field("username")` and `/accounts/signup/` raises `FieldDoesNotExist`.

---

## Option B — `django-mail-auth`

User enters email → gets a one-time link → clicks → logged in.

### Install

```sh
uv add django-mail-auth
```

### Settings

```python
INSTALLED_APPS = [
    ...
    "mailauth",
    "mailauth.contrib.user",   # optional: User model with no password field
]

AUTHENTICATION_BACKENDS = [
    "mailauth.backends.MailAuthBackend",
    "django.contrib.auth.backends.ModelBackend",
]

LOGIN_URL = "mailauth:login"
LOGIN_REDIRECT_URL = "/"
```

If `references/custom-user.md` is applied, skip `mailauth.contrib.user` and keep the project's `users.User`.

### URLs

```python
urlpatterns = [
    ...
    path("accounts/", include("mailauth.urls", namespace="mailauth")),
]
```

### Templates (required)

`django-mail-auth` ships no default templates — `/accounts/login/` 500s without them.

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

Add `BASE_DIR / "templates"` to `TEMPLATES[0]["DIRS"]` if missing.

### Migrate

```sh
uv run manage.py migrate
```

Test with the console backend or Mailpit — the magic link is printed/captured there.
