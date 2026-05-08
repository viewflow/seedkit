# Authentication

Pick **one** of the two options below. Both replace `django.contrib.auth`'s bare login views with something usable; they don't compose. If the user said "no auth add-on", skip this whole reference and stay on `django.contrib.auth` defaults.

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
ACCOUNT_EMAIL_VERIFICATION = "mandatory"
```

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

Allauth ships its own templates; override only when the user wants custom branding.

If a custom user model from `references/custom-user.md` is in use, drop the `username` field and use the email-as-`USERNAME_FIELD` variant — otherwise email-only signup will fail because `AbstractUser` requires a username.

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

### Migrate

```sh
uv run manage.py migrate
```

Test the flow locally with the console email backend or Mailpit — the magic link is printed/captured there.
