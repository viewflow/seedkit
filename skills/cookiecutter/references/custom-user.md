# Custom User Model

Set `AUTH_USER_MODEL` **before the first `migrate`**. Adding it later requires data migrations and breaks foreign keys to `auth.User`.

A `pk=BigAutoField` empty subclass is enough — extending it later (extra fields, email-as-username, etc.) doesn't require schema changes to existing rows.

## Create the app

```sh
mkdir users
uv run django-admin startapp users users
```

(`startapp <name> <path>` lets you place the app at the repo root. If you prefer `apps/users/` or similar, adjust the path and the dotted reference accordingly.)

## users/models.py

If the project keeps username-based login, plain `AbstractUser` is enough:

```python
from django.contrib.auth.models import AbstractUser


class User(AbstractUser):
    pass
```

If the project uses email-only login (`django-allauth` with `ACCOUNT_LOGIN_METHODS = {"email"}`, or `django-mail-auth`), drop the `username` field, make `email` the `USERNAME_FIELD`, and enforce uniqueness — `AbstractUser`'s `email` column is **not unique** by default, which breaks email-based login lookups:

```python
from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    username = None
    email = models.EmailField(unique=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []
```

## users/admin.py

```python
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User

admin.site.register(User, UserAdmin)
```

## Settings

In `config/settings.py` (or `config/settings/base.py` for split):

```python
INSTALLED_APPS = [
    ...
    "users",
]

AUTH_USER_MODEL = "users.User"
```

## Migrate

Now run the boot check (`migrate`, `createsuperuser`). The `users_user` table replaces `auth_user`; `createsuperuser` will use the new model.
