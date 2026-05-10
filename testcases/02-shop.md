# 02 — Split settings, Postgres on host, WhiteNoise + SMTP, Tailwind CSS + Stripe billing

Covers split settings layout, host Postgres, Ruff, WhiteNoise statics, SMTP email, `django-tailwind-cli` frontend integration, and Stripe billing (raw SDK — Checkout session, Customer Portal, webhook handler).

## Prompt

```
/seedkit

Project name: 02-shop
Purpose: small e-commerce site with admin and SMTP transactional email.

Settings layout: split (`config/settings/base.py`, `local.py`, `production.py`).
Database: PostgreSQL.
Local dev mode: uv on host. Postgres location: on the host (use `createdb` for the project DB).
Lint with Ruff: yes.
Test runner: pytest + pytest-django.
Type check (pyright + django-stubs): yes.
Pre-commit hooks: no.
Internationalisation (i18n): no.
Custom user model: yes (custom `users.User` extending `AbstractUser`).
Auth add-on: `django-allauth` (email login, mandatory email verification, no social providers).
Structured logging: no.
Add-ons:
  - storage: WhiteNoise for static files (no media volume yet)
  - email: SMTP (console backend in local, SMTP in production)
  - CORS: no.
  - REST API: none.
  - Frontend: `tailwind-cli` (custom 404/403/500 templates: yes; DaisyUI: yes). Also add a `pages` app with an `IndexView(TemplateView)` wired at `/`. Its `index.html` must include `text-blue-600` and `text-4xl` (utility check) and a `<button class="btn btn-primary">` (DaisyUI check) — concrete grep targets for the integration tests below.
  - Auth hardening: `django-axes` (yes), 2FA (no).
  - Billing: `stripe` raw SDK.
  - Health check endpoints: yes.
  - `robots.txt`: yes.
  - `django-extensions`: no.

Production setup: skip.

Assume Postgres is already running locally on port 5432 with user `postgres` / password `postgres`. Create database `shop_db` if missing (Postgres identifiers can't start with a digit, so use a clean name). Run the foundation + boot check, then run `python manage.py tailwind build` once so the CSS asset exists, and verify the index page returns the Tailwind-styled HTML.
```

## Boot check

```sh
createdb shop_db || true
cd 02-shop
uv run manage.py tailwind build
uv run manage.py runserver &
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
curl -sf http://127.0.0.1:8000/ | grep -q 'text-blue-600'
CSS_URL=$(curl -sf http://127.0.0.1:8000/ | grep -oE 'href="[^"]*tailwind[^"]*\.css[^"]*"' | head -1 | sed 's/href="//;s/"//')
test -n "$CSS_URL"
curl -sf "http://127.0.0.1:8000${CSS_URL}" | grep -q '\.text-blue-600'
curl -sf "http://127.0.0.1:8000${CSS_URL}" | grep -q '\.btn'
curl -sf http://127.0.0.1:8000/ | grep -q 'data-theme='
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
curl -sf http://127.0.0.1:8000/robots.txt | grep -q 'User-agent: \*'
uv run ruff check .
uv run pyright
kill $(jobs -p) 2>/dev/null; pkill -f 'manage.py' 2>/dev/null; wait
dropdb shop_db
```

## Review

Read-only audit of the project in the current directory. Quote the file path and the literal substring you read for every claim — do not infer state from training-data priors.

Verify these structural facts:

**Foundation**
- Files present: `pyproject.toml`, `uv.lock`, `manage.py`, `config/settings/{base,local,production}.py`, `.env`, `.gitignore`.
- `manage.py` defaults `DJANGO_SETTINGS_MODULE` to `config.settings.local`; `wsgi.py` to `config.settings.production`.
- `pyproject.toml` runtime deps include `psycopg[binary]`, `django-tailwind-cli`, `django-allauth`, `django-axes`, `stripe`, `whitenoise`. Dev deps include `ruff`, `pytest`, `pytest-django`, `pyright`, `django-stubs`, `django-stubs-ext`.
- `pyproject.toml` has a `[tool.ruff]` block and a `[tool.pyright]` block.

**Settings**
- `config/settings/base.py` uses `env.NOTSET` for the prod branch of `SECRET_KEY` and `DATABASES`.
- `whitenoise.middleware.WhiteNoiseMiddleware` is present in `config/settings/production.py`'s `MIDDLEWARE` and absent from `base.py`.
- `EMAIL_BACKEND` resolves to `django.core.mail.backends.console.EmailBackend` in `local.py` only; production reads SMTP settings from env.
- `_stripe.api_key = STRIPE_SECRET_KEY` is set at module scope in `base.py`.

**Custom user + auth**
- `users/models.py` defines a `User` extending `AbstractUser`. `AUTH_USER_MODEL = "users.User"` in `base.py`.
- `users/migrations/0001_initial.py` exists and creates the `users.User` table.
- `users.User` has a `stripe_customer_id` field (in the model OR a follow-up migration in `users/migrations/`).
- `INSTALLED_APPS` contains `allauth`, `allauth.account`, `django.contrib.sites`, `axes`. `MIDDLEWARE` ends with `axes.middleware.AxesMiddleware`. `AUTHENTICATION_BACKENDS` starts with `axes.backends.AxesBackend`.
- `accounts/` URL include in `config/urls.py`. `ACCOUNT_EMAIL_VERIFICATION = "mandatory"` in `production.py`.

**Tailwind + DaisyUI**
- `INSTALLED_APPS` contains `django_tailwind_cli`. `STATICFILES_DIRS = [BASE_DIR / "assets"]`. `TAILWIND_CLI_VERSION` pinned. `TAILWIND_CLI_SRC_CSS = "assets/css/source.css"` in `base.py`. `TAILWIND_CLI_USE_DAISY_UI` is **not** set.
- Files present: `assets/css/daisyui.mjs`, `assets/css/daisyui-theme.mjs`, `assets/css/source.css`.
- `assets/css/source.css` contains `@import "tailwindcss";`, `@source not "./tailwindcss";`, `@source not "./daisyui{,*}.mjs";`, `@plugin "./daisyui.mjs";`.
- `templates/base.html` loads `{% load tailwind_cli %}`, calls `{% tailwind_css %}` inside `<head>`, and contains `<html data-theme=`.
- `templates/index.html` extends `base.html` and contains the literals `text-blue-600`, `text-4xl`, and `btn-primary`.
- `templates/404.html`, `templates/403.html`, `templates/500.html` present. `500.html` does NOT extend `base.html`.

**Pages + billing**
- `pages/` app with `IndexView(TemplateView)` wired at `/`. `liveness` and `readiness` views, `path('healthz', ...)` and `path('readyz', ...)` (no trailing slash), `robots_txt` view at `path('robots.txt', ...)`.
- `billing/` app with `create_checkout_session`, `customer_portal`, `stripe_webhook` views. Webhook decorated with `@csrf_exempt` AND `@require_POST`. Webhook calls `stripe.Webhook.construct_event(request.body, sig_header, settings.STRIPE_WEBHOOK_SECRET)`.
- `STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` listed in `.env.example`. `billing/` URLs included in `config/urls.py`.

Report only issues that (i) prevent the scaffold from booting, (ii) violate one of the structural assertions above, or (iii) are an outright security hole. Skip nitpicks (docstrings, style, hypothetical scaling, "consider adding X"). Do not propose refactors, abstractions, retries, defensive checks, or hardening the prompt did not ask for. If unsure, omit it. Do NOT create, generate, or modify any files. Do NOT invoke any skill. Be brief; top issues first; "No issues found." is a valid report.
