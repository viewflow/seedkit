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

## Expected outcome

- `uv run manage.py runserver` boots; `/admin/` login works.
- `psycopg[binary]` in dependencies; `DATABASE_URL=postgres://...@localhost:5432/shop_db` in `.env`.
- `config/settings/{base,local,production}.py` present; `manage.py` points at `config.settings.local`, `wsgi.py` at `config.settings.production`.
- Ruff config in `pyproject.toml`; `uv run ruff check .` exits 0.
- WhiteNoise middleware listed in production settings only.
- Email backend `django.core.mail.backends.console.EmailBackend` in local; SMTP wired via env in production.
- `users/` app with `AbstractUser` subclass and admin registration; `AUTH_USER_MODEL = "users.User"` set **before** the initial migration; `users_user` table exists (no `auth_user`).
- `django-allauth` installed; `allauth`, `allauth.account`, `django.contrib.sites` in `INSTALLED_APPS`; `AccountMiddleware` in `MIDDLEWARE`; `accounts/` URL include; `ACCOUNT_EMAIL_VERIFICATION = "mandatory"`; `/accounts/login/` and `/accounts/signup/` render.
- `django-tailwind-cli` in dependencies; `django_tailwind_cli` in `INSTALLED_APPS`. `STATICFILES_DIRS = [BASE_DIR / "assets"]` and the `assets/` directory exists on disk (Django raises at startup if missing). `TAILWIND_CLI_VERSION = "4.1.3"` pinned.
- `templates/base.html` loads `{% load tailwind_cli %}` and calls `{% tailwind_css %}` inside `<head>`. `templates/index.html` extends `base.html` and uses Tailwind utility classes including `text-blue-600` and `text-4xl`.
- `pages/` Django app exists with `IndexView(TemplateView)` and is wired as the root URL.
- `python manage.py tailwind build` succeeds and produces a CSS file under `assets/` (default `assets/css/tailwind.css`) that contains rules for the classes used in `index.html`. The downloaded CLI lives in `<BASE_DIR>/.django_tailwind_cli/`.
- DaisyUI vendored: `assets/css/daisyui.mjs` and `assets/css/daisyui-theme.mjs` exist in the repo (committed, not gitignored). `assets/css/source.css` exists, contains `@import "tailwindcss";`, `@source not "./tailwindcss";`, `@source not "./daisyui{,*}.mjs";`, and `@plugin "./daisyui.mjs";`. `TAILWIND_CLI_SRC_CSS = "assets/css/source.css"` is set in `base.py`. `TAILWIND_CLI_USE_DAISY_UI` is **not** set (the upstream `@plugin` path is used, not the cli-extra fork).
- Built CSS contains DaisyUI's `.btn` and `.btn-primary` rules (in addition to the utility classes from the previous bullet).
- `<html data-theme="light">` is present in `templates/base.html`.
- `curl http://127.0.0.1:8000/` returns 200, the response body contains the literal `text-blue-600`, and the `<link>` element rendered by `{% tailwind_css %}` resolves to a 200 response whose body contains a rule matching `.text-blue-600`.
- `templates/404.html`, `403.html`, `500.html` exist and load `tailwind_cli`. With `DEBUG=False` and `ALLOWED_HOSTS` set, `curl /this-route-does-not-exist` returns 404 and the body contains a Tailwind utility class (e.g. `text-6xl`). `500.html` does NOT extend `base.html`.
- `django-axes` in dependencies; `axes` in `INSTALLED_APPS`; `axes.middleware.AxesMiddleware` is the **last** entry in `MIDDLEWARE`; `axes.backends.AxesBackend` is **first** in `AUTHENTICATION_BACKENDS`. After 5 wrong logins from the same IP+username, the 6th login attempt to `/accounts/login/` is locked out (axes returns its lockout response, not allauth's "wrong password").
- `pages` app exposes `liveness` and `readiness` views; `urlpatterns` includes `path('healthz', ...)` and `path('readyz', ...)` (no trailing slash). `curl /healthz` returns 200 with body `ok`; `curl /readyz` returns 200 with body `ready`.
- `pages` app exposes a `robots_txt` view; `path('robots.txt', ...)` is wired. `curl /robots.txt` returns 200 with `Content-Type: text/plain` and body containing `User-agent: *` and `Disallow: /admin/` (when `DEBUG=False`).
- `stripe` in runtime dependencies (not dev-only). `STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` present in `.env.example` with placeholder values. `_stripe.api_key = STRIPE_SECRET_KEY` set in `base.py`.
- `users.User` has a `stripe_customer_id` field; `users/migrations/` contains a migration adding it.
- `billing/` app exists with `create_checkout_session`, `customer_portal`, `stripe_webhook` views. Webhook view is decorated with `@csrf_exempt` and `@require_POST`. Webhook view calls `stripe.Webhook.construct_event(request.body, sig_header, settings.STRIPE_WEBHOOK_SECRET)` and returns 400 on invalid signature, 200 on success. `billing/` URLs wired in `config/urls.py`.

## Run

```sh
# Run from a scratch parent dir; the skill creates `02-shop/` via `uv init`.
createdb shop_db || true
# AI executes the skill here, then:
cd 02-shop
# One-shot CSS build so the asset exists before the smoke test (watch mode is optional in dev)
uv run manage.py tailwind build
uv run manage.py runserver &
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
# Index page returns 200 and contains a Tailwind utility class from the template
curl -sf http://127.0.0.1:8000/ | grep -q 'text-blue-600'
# The CSS link injected by {% tailwind_css %} actually resolves and ships the rule
CSS_URL=$(curl -sf http://127.0.0.1:8000/ | grep -oE 'href="[^"]*tailwind[^"]*\.css[^"]*"' | head -1 | sed 's/href="//;s/"//')
test -n "$CSS_URL"
curl -sf "http://127.0.0.1:8000${CSS_URL}" | grep -q '\.text-blue-600'
# DaisyUI integration: vendored bundle present, @plugin directive wired, .btn rule shipped in served CSS, theme attribute on root
test -f assets/css/daisyui.mjs
test -f assets/css/daisyui-theme.mjs
grep -q '@plugin "./daisyui.mjs"' assets/css/source.css
curl -sf "http://127.0.0.1:8000${CSS_URL}" | grep -q '\.btn'
curl -sf http://127.0.0.1:8000/ | grep -q 'data-theme='
# Healthcheck endpoints
test "$(curl -sf http://127.0.0.1:8000/healthz)" = "ok"
test "$(curl -sf http://127.0.0.1:8000/readyz)" = "ready"
# robots.txt
curl -sf http://127.0.0.1:8000/robots.txt | grep -q 'User-agent: \*'
uv run ruff check .
# billing: stripe package installed, env vars in .env.example, billing app wired
python -c "import stripe"
grep -q 'STRIPE_PUBLISHABLE_KEY' .env.example
grep -q 'STRIPE_WEBHOOK_SECRET' .env.example
grep -rq 'stripe_customer_id' users/
grep -rq 'csrf_exempt' billing/
grep -rq 'construct_event' billing/
```

## Check report

**Execute this command yourself before stopping. Do not present it as a "next step" for the user — the testcase isn't done until the review file exists.** It runs an independent review (the model that built the project shouldn't grade its own output) and writes the result to `REVIEW.md` in the project dir.

```sh
claude -p \
  --model claude-opus-4-7 \
  --allowedTools "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*)" \
  "Audit the existing code in this directory. The following are INTENTIONAL design decisions of the seedkit skill — do NOT flag them as bugs even if they look unusual: (a) `default=... if DEBUG else None` gated defaults on SECRET_KEY / DATABASES (fail-fast in prod, zero-config in dev/build); (b) `globals().update(env.email_url(...))` is the documented django-environ idiom for spreading email settings; (c) `local.py` containing only `from .base import *` (deltas-only design; all dev defaults live in base via env vars); (d) WhiteNoise `STORAGES` configured only in `production.py`, never base (manifest storage requires collectstatic, breaks runserver); (e) `wsgi.py` / `asgi.py` defaulting to `config.settings.production` while `manage.py` defaults to `local` (intentional safety asymmetry); (f) custom user model with `username = None`, `email` as `USERNAME_FIELD`, and a custom `UserManager` when email-only auth is chosen; (g) `ACCOUNT_EMAIL_VERIFICATION = \"optional\"` in base, `\"mandatory\"` in production.py. (h) `stripe_customer_id` blank by default on `users.User` — populated on first checkout, not at signup; (i) `_stripe.api_key = STRIPE_SECRET_KEY` set at module level in `base.py` — intentional, this is the documented pattern for Django apps; (j) `@csrf_exempt` on the webhook view — Stripe cannot send CSRF tokens, this is required and correct; (k) empty placeholder values for `STRIPE_*` keys in `.env.example` — test keys go in `.env` which is gitignored. Skip these in the report. This is a freshly generated Django *project starter / scaffold* — there is intentionally no business logic, no app code, no real content, AND no production hardening (no security settings, error reporting, GDPR, CI, deploy config, or production Dockerfile). Focus on configuration correctness for the dev/foundation scope and adherence to Django best practices for a starter. Do NOT flag the absence of feature code, app modules, domain models, or production-only settings — those are out of scope for this case. Do NOT create, generate, or modify any files — read-only review only. Do NOT invoke any skill (especially seedkit). List bugs, inconsistencies, and concrete fixes. Be brief, top issues first." \
  | tee REVIEW.md
```

Paste the output below.

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:

## Cleanup

Leave the code. Drop the host Postgres database:

```sh
dropdb shop_db
```
