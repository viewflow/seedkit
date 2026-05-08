# Custom User Model

Set `AUTH_USER_MODEL` **before the first `migrate`**. Adding it later requires data migrations and breaks foreign keys to `auth.User`.

A `pk=BigAutoField` empty subclass is enough — extending it later (extra fields, email-as-username, etc.) doesn't require schema changes to existing rows.

## Create the app

```sh
uv run django-admin startapp users
```

(Creates `./users/`. If you prefer a nested layout like `apps/users/`, run `mkdir -p apps/users && uv run django-admin startapp users apps/users` and adjust the dotted reference.)

## users/models.py

If the project keeps username-based login, plain `AbstractUser` is enough:

```python
from django.contrib.auth.models import AbstractUser


class User(AbstractUser):
    pass
```

If the project uses email-only login (`django-allauth` with `ACCOUNT_LOGIN_METHODS = {"email"}`, or `django-mail-auth`), drop the `username` field, make `email` the `USERNAME_FIELD`, and enforce uniqueness — `AbstractUser`'s `email` column is **not unique** by default, which breaks email-based login lookups. With `USERNAME_FIELD = "email"` you also need a custom manager that uses email instead of username for `create_user` / `create_superuser`:

```python
from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models


class UserManager(BaseUserManager):
    use_in_migrations = True

    def _create_user(self, email, password, **extra_fields):
        if not email:
            raise ValueError("Email is required")
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        if extra_fields.get("is_staff") is not True:
            raise ValueError("Superuser must have is_staff=True.")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True.")
        return self._create_user(email, password, **extra_fields)


class User(AbstractUser):
    username = None
    email = models.EmailField(unique=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    objects = UserManager()
```

## users/admin.py

For the plain `AbstractUser` variant, the default `UserAdmin` works as-is:

```python
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User

admin.site.register(User, UserAdmin)
```

For the email-as-`USERNAME_FIELD` variant, override the add/change forms so the admin's "Add user" page collects email (default `UserCreationForm` expects a `username` field that no longer exists):

```python
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.forms import UserChangeForm, UserCreationForm

from .models import User


class UserCreationFormEmail(UserCreationForm):
    class Meta(UserCreationForm.Meta):
        model = User
        fields = ("email",)


class UserChangeFormEmail(UserChangeForm):
    class Meta(UserChangeForm.Meta):
        model = User
        # Don't inherit Meta.field_classes from the parent — it pins
        # `{"username": UsernameField}`, and `username` no longer exists.
        field_classes = {}  # type: ignore[assignment]


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    add_form = UserCreationFormEmail
    form = UserChangeFormEmail
    list_display = ("email", "is_staff", "is_superuser")
    ordering = ("email",)
    search_fields = ("email",)
    readonly_fields = ("last_login", "date_joined")
    fieldsets = (
        (None, {"fields": ("email", "password")}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Important dates", {"fields": ("last_login", "date_joined")}),
    )
    add_fieldsets = (
        (None, {"classes": ("wide",), "fields": ("email", "password1", "password2")}),
    )
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
