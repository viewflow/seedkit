# pyright + django-stubs

`djangoSettingsModule` is a `django-stubs` plugin option, not a pyright option — putting it under `[tool.pyright]` triggers "unknown config" warnings.

```toml
[tool.pyright]
include = ["."]
exclude = [".venv", "**/migrations"]
venvPath = "."
venv = ".venv"

[tool.django-stubs]
django_settings_module = "config.settings.local"
```

Install: `uv add --dev pyright django-stubs django-stubs-ext`. In `settings/base.py`:

```python
import django_stubs_ext
django_stubs_ext.monkeypatch()
```

When `path()` complains about `Consumer.as_asgi()`:

```python
path("ws/echo/", EchoConsumer.as_asgi()),  # type: ignore[arg-type]  # channels returns ASGIApp, path() expects view callable
```
