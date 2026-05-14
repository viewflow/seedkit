# django-tailwind-cli

Uses the standalone Tailwind binary — no Node, no npm. DaisyUI ships as `.mjs` files copied into the source tree; the binary loads them via `@plugin`.

```toml
# pyproject.toml
dependencies = [
    "django-tailwind-cli",
]
```

```python
# config/settings/base.py
INSTALLED_APPS = [
    # ...
    "django_tailwind_cli",
]

STATICFILES_DIRS = [BASE_DIR / "assets"]  # build output lands here
TAILWIND_CLI_VERSION = "4.1.13"
TAILWIND_CLI_SRC_CSS = "tailwind-src/css/source.css"  # outside STATICFILES_DIRS so the raw source isn't served
```

Do not set `TAILWIND_CLI_USE_DAISY_UI` — the project vendors DaisyUI directly via `@plugin` so the binary picks it up without the package's npm-shim path.

Layout:

```
tailwind-src/css/source.css
tailwind-src/css/daisyui.mjs        # download from https://github.com/saadeghi/daisyui/releases (full daisyui.js)
tailwind-src/css/daisyui-theme.mjs  # same release, theme file
assets/                              # build output (gitignored)
templates/base.html
```

```css
/* tailwind-src/css/source.css */
@import "tailwindcss";
@source not "./tailwindcss";       /* skip scanning the vendored TS sources */
@source not "./daisyui{,*}.mjs";   /* skip scanning the plugin's own bundles */
@plugin "./daisyui.mjs";
```

```django
{# templates/base.html #}
{% load tailwind_cli %}
<!doctype html>
<html data-theme="light">
<head>
  {% tailwind_css %}
</head>
<body>{% block content %}{% endblock %}</body>
</html>
```

Build:

```sh
uv run manage.py tailwind build  # writes to assets/css/tailwind.css
```

Run `tailwind build` once after templates exist — the v4 binary tree-shakes by scanning template content, so building before templates produces an empty stylesheet.

## Error templates

`templates/500.html` must not extend `base.html` — when Django renders the 500 page the request context is unsafe, and a base template that touches the DB or user can mask the original error. Keep `500.html` self-contained inline HTML. `403.html` and `404.html` can extend `base.html` normally.
