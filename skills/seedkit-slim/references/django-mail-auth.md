# django-mail-auth

Passwordless email login. PyPI distribution is `django-mail-auth`; the import/app label is `mailauth`.

## Install + wire

```python
# config/settings.py
INSTALLED_APPS = [
    # ...
    "django.contrib.sites",
    "mailauth",
    "mailauth.contrib.admin",  # admin login via emailed magic link
]

SITE_ID = 1

AUTHENTICATION_BACKENDS = [
    "mailauth.backends.MailAuthBackend",
    "django.contrib.auth.backends.ModelBackend",
]

LOGIN_URL = "mailauth:login"
LOGIN_REDIRECT_URL = "/"
```

```python
# config/urls.py
urlpatterns = [
    path("accounts/", include("mailauth.urls", namespace="mailauth")),
    # ...
]
```

## Templates — required

`mailauth` ships no templates. Create both or `accounts/login/` returns 500:

```html
{# templates/registration/login.html #}
<form method="post">{% csrf_token %}{{ form.as_p }}
  <button type="submit">Send login link</button>
</form>
```

```html
{# templates/registration/login_requested.html #}
<p>Check your email for the login link.</p>
```

Ensure `TEMPLATES[0]["DIRS"]` includes `BASE_DIR / "templates"`.
