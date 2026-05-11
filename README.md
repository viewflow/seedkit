# Robusta Seedkit 🌱
  
An agent skill to start new Django projects or enhance old ones
  
```
/seedkit SaaS landing + waitlist, GDPR-friendly stack (mail, analytics, error reporting), VPS deploy
 ```
  
```
/seedkit add proper auth — magic link, lockout on brute force, optional 2FA
```
  
```
/seedkit look at our repo and tell us what's worth adding next
```

[![View Outputs](https://img.shields.io/badge/View%20Outputs-00C853)](https://github.com/RobustaRush/seedkit-examples)

Helps you with: [Settings split](https://docs.djangoproject.com/en/stable/topics/settings/), [DATABASES](https://docs.djangoproject.com/en/stable/ref/settings/#databases), [AUTH_USER_MODEL](https://docs.djangoproject.com/en/stable/topics/auth/customizing/#substituting-a-custom-user-model), [Static files](https://docs.djangoproject.com/en/stable/howto/static-files/), [Media files](https://docs.djangoproject.com/en/stable/topics/files/), [Security settings](https://docs.djangoproject.com/en/stable/topics/security/), [LOGGING](https://docs.djangoproject.com/en/stable/topics/logging/), [CACHES](https://docs.djangoproject.com/en/stable/topics/cache/), [Email](https://docs.djangoproject.com/en/stable/topics/email/), [i18n](https://docs.djangoproject.com/en/stable/topics/i18n/translation/), [Admin](https://docs.djangoproject.com/en/stable/ref/contrib/admin/), [uv](https://docs.astral.sh/uv/), [django-environ](https://django-environ.readthedocs.io/), [django-allauth](https://docs.allauth.org/), [django-mail-auth](https://django-mail-auth.readthedocs.io/), [django-axes](https://django-axes.readthedocs.io/), [allauth.mfa](https://docs.allauth.org/en/latest/mfa/introduction.html), [django-otp](https://django-otp-official.readthedocs.io/), [Celery](https://docs.celeryq.dev/), [django.tasks](https://docs.djangoproject.com/en/dev/topics/tasks/), [django-tasks-db](https://github.com/RealOrangeOne/django-tasks-database), [django-tasks-rq](https://github.com/RealOrangeOne/django-tasks-rq), [python-rq](https://python-rq.org/), [django-redis](https://github.com/jazzband/django-redis), [WhiteNoise](https://whitenoise.evans.io/), [django-storages](https://django-storages.readthedocs.io/), [MinIO](https://min.io/docs/minio/linux/), [Litestream](https://litestream.io/), [django-anymail](https://anymail.dev/), [Mailpit](https://mailpit.axllent.org/), [django-tailwind-cli](https://django-tailwind-cli.readthedocs.io/), [DaisyUI](https://daisyui.com/), [django-cors-headers](https://github.com/adamchainz/django-cors-headers), [django-modern-rest](https://django-modern-rest.readthedocs.io/), [django-bolt](https://django-bolt.readthedocs.io/), [Stripe](https://docs.stripe.com/api?lang=python), [dj-stripe](https://dj-stripe.dev/), [GoatCounter](https://www.goatcounter.com/help/start), [Umami](https://umami.is/docs), [Shynet](https://shynet.r1ke.io/), [GA4](https://developers.google.com/analytics/devguides/collection/ga4), [django-csp](https://django-csp.readthedocs.io/), [Sentry](https://docs.sentry.io/platforms/python/integrations/django/), [Bugsink](https://www.bugsink.com/docs/), [GlitchTip](https://glitchtip.com/documentation), [django-zeal](https://github.com/PedroBern/django-zeal), [django-migration-linter](https://github.com/3YOURMIND/django-migration-linter), [django-test-migrations](https://django-test-migrations.readthedocs.io/), [django-silk](https://github.com/jazzband/django-silk), [django-orbit](https://github.com/kmmbvnr/django-orbit), [django-extensions](https://django-extensions.readthedocs.io/), [Ruff](https://docs.astral.sh/ruff/), [pyright](https://microsoft.github.io/pyright/), [django-stubs](https://github.com/typeddjango/django-stubs), [pre-commit](https://pre-commit.com/), [pytest-django](https://pytest-django.readthedocs.io/), [structlog](https://www.structlog.org/), [django-dbbackup](https://django-dbbackup.readthedocs.io/), [Docker](https://docs.docker.com/compose/), [Caddy](https://caddyserver.com/docs/), [Fly.io](https://fly.io/docs/django/), [Railway](https://docs.railway.com/), [Render](https://render.com/docs), [GitHub Actions](https://docs.github.com/en/actions), [Dev Containers](https://containers.dev/)

## The problem

Setting up a real Django project — the kind that survives contact with users, lawyers, and the occasional auditor — is harder than it has any right to be. You have to pick a database; a way to run it locally without committing it to git by accident; a static-file story (which is also a deployment story, whether you wanted one or not); email, because eventually somebody will need a password reset; a task queue, because eventually somebody will need a slow thing to happen later; logging, because eventually it will all stop working in a way you cannot reproduce; analytics that don't anger the GDPR; error reporting that doesn't anger your wallet; and finally deployment, which is a whole second job.

The standard answer is a cookiecutter — a templated project that ships with all of the above pre-installed. This works, in roughly the same sense that wearing all your clothes at once works: you are definitely prepared for every season, and you also cannot move.

## The hypothesis

A classic cookiecutter runs once, at the start, and hands you a hundred files you didn't ask for. A skill — Markdown instructions an AI agent reads and follows — can do something a template cannot: it can come back later and read what's already in your repo before deciding what to do next.

So:

- ask what you actually want, one question at a time
- generate only the files for the things you said yes to
- run again, six months later, after reading the current state of the project, to add Celery without rewriting your settings
- explain each line as it writes it, while you read along

This repo is the experiment. The question is whether an opinionated bundle of Markdown, plus a competent agent, can replace `cookiecutter-django` for new projects and `copier update` for evolving ones.

It is, at the moment, well... well tested. Nine end-to-end cases run the skill through `claude -p`, each generating a real Django project, each audited by a second agent that knows nothing of the first one's intentions. The audits surface false positives (which we silence by hand) and real bugs (which we file as commits). It is honest work.

## A short demo

What invoking the skill in an empty directory looks like (transcript trimmed):

```text
$ /seedkit

This skill sets up a Django project incrementally. Foundation first
(uv, settings, DB, dev mode, custom user, lint), then add-ons (auth,
debug, redis, storage, tasks, email, logging, analytics), then
production (security, errors, GDPR, CI, deploy). You pick what you
want, one question at a time. Ready?

> yes

What's the project name and a one-line purpose?
> blog — personal blog with markdown posts

Settings layout: single config/settings.py, or split base/local/production?
> split

Database: SQLite (zero-setup) or PostgreSQL?
> sqlite

Local dev mode: uv on host, or docker-compose?
> uv on host

Custom user model? Adds a users app with AUTH_USER_MODEL.
Easier to set now than later. (yes / no)
> no

Lint with Ruff?
> yes

Generating the foundation...

  blog/
  ├─ pyproject.toml
  ├─ uv.lock
  ├─ manage.py
  ├─ .env  .env.example  .gitignore
  ├─ db.sqlite3
  └─ config/
     ├─ __init__.py
     ├─ settings/{base,local,production}.py
     ├─ urls.py  wsgi.py  asgi.py

Boot check: run `uv run manage.py migrate`, then `createsuperuser`,
then `runserver`. Confirm /admin/ login works before continuing.

> works

Add-ons. Auth: django-allauth (passwords, social, verification),
django-mail-auth (passwordless magic links), or stock Django?
```

Three months later, in the same directory:

```text
$ /seedkit add tasks

Reading the current project... split settings, SQLite, no Redis yet.

Tasks backend: Celery, django-tasks (Django 6 builtin) + DB backend,
or django-tasks-rq (Redis Queue)? RQ adds Redis to the stack.
> django-tasks-db

Adding tasks support to the existing project...

  +  jobs/                    new app for @task functions
  +  config/settings/base.py  TASKS = {...}, INSTALLED_APPS += ["jobs"]
  +  README.md                section: "Background tasks"

No new env vars; no new services. Run `uv run manage.py migrate` to
create the task storage table.
```

Or on a project that was never started with seedkit at all:

```text
$ /seedkit auth hardened

Reading the current project... django-allauth installed, stock
configuration, no rate limiting, no 2FA.

Hardening auth:
  +  config/settings/base.py   ACCOUNT_LOGIN_ATTEMPTS_LIMIT,
                                ACCOUNT_LOGIN_ATTEMPTS_TIMEOUT,
                                SESSION_COOKIE_AGE, SECURE_* headers
  +  requirements.txt           django-axes
  +  config/settings/base.py   axes middleware, AXES_* settings
  ~  templates/account/         login page with lockout message

Run `uv run manage.py migrate` to create the axes tables.
```

The skill reads what's already there before touching anything. It won't reinstall allauth; it won't reset settings you've already tuned. It adds what's missing and moves on.

Files only get touched if the user said yes. The skill never rewrites your project from a template, because there is no template — the rules are Markdown the agent reads, and the project is whatever you have on disk.

## What's different

|                              | `cookiecutter-django` | `copier`                       | this skill                          |
| ---------------------------- | --------------------- | ------------------------------ | ----------------------------------- |
| When does it run?            | once, at `init`       | `init` + `copier update`       | any time, in a fresh conversation   |
| Does it read your repo?      | no                    | only the answers file          | yes — the actual files              |
| Updating after init          | not really            | replays the template; conflicts on customization | no template; the agent decides what to add to what's already there |
| Adding a new option          | edit a Jinja template | edit a Jinja template + `copier.yml` | edit one Markdown reference         |
| Output is reproducible?      | yes (deterministic)   | yes                            | no (model + phrasing affect output) |
| Whose taste are you wearing? | the template author's | the template author's          | yours, with the agent's help        |

The honest trade is in the last two rows. `copier` and friends give you reproducibility; you pay for it by living inside the template author's mental model forever, and any deviation costs you a merge conflict on the next `update`. This skill gives up determinism in exchange for *reading what you actually have* before doing anything. Each run is a consultation, not a re-stamp.

Three goals, in order of how often they come up:

1. **Spend fewer tokens.** References are split so the agent loads roughly 30–95 lines per choice instead of 250–290. Local 8B models can run this without hating you.
2. **Push best practices that survive review.** Gated `default=... if DEBUG else None`, `BASE_DIR`-anchored SQLite, the `STORAGES` dict, allauth wired against a custom user model that doesn't pretend usernames matter.
3. **Surface good open-source Django add-ons.** `django-environ`, `django-allauth`, `django-mail-auth`, `structlog`, `django-rq`, `django-tasks`, GoatCounter, Bugsink. Each chosen because it exists, works, and stays out of the way.

## What it can set up

Grouped roughly by when you'd add it.

**Foundation** — the bits a Django project can't really go without:

- `uv` — replaces pip, venv, and pip-tools, and is no longer the new thing
- project layout: single `settings.py` *or* split `base/local/production`
- `django-environ` — one `DATABASE_URL`, one `EMAIL_URL`, etc.
- SQLite or PostgreSQL (with WAL + Litestream for the SQLite-in-prod heretics)
- custom user model — plain, or email-as-username wired correctly for allauth
- local dev via `uv` on host *or* fully through docker-compose
- Ruff, with Django-aware rules and the obvious `RUF012` exception

**Add-ons** — the bits you add when you actually need them:

- auth: `django-allauth` (passwords, social) or `django-mail-auth` (passwordless magic links)
- debug: `django-debug-toolbar` plus `orbit` or `silk`
- Redis cache via `django-redis`
- static + media on WhiteNoise *or* S3-compatible storage
- task queue: Celery; or Django 6's built-in `django-tasks` with a DB or RQ backend; periodic jobs through `django-tasks-cron`
- email: console / SMTP / Mailpit, all behind one `EMAIL_URL`
- logging: `structlog`, JSON in prod and pretty in dev, with a request-id middleware so you can grep for one user's afternoon
- analytics: GoatCounter, Umami, Shynet, or Google Analytics 4 (the last against our better judgement, but it is your project)

**Production** — the bits you add when somebody other than you is going to use this:

- security headers, HSTS, CSRF trusted origins
- error reporting: Bugsink (self-host), GlitchTip (self-host), or Sentry SaaS
- GDPR: PII scrubbing, data export/delete, retention rules
- CI on GitHub Actions
- deploy: VPS + Caddy, managed (Fly.io / Railway / Render), or GitHub Actions over SSH

You don't have to pick all of them. You don't have to pick most of them. The skill asks; you answer.

## Install

### Claude Code (plugin)

```sh
/plugin marketplace add RobustaRush/seedkit
/plugin install seedkit@robusta
```

Then, in whatever empty directory you'd like to populate:

```
/seedkit
```

The skill takes over from there.

### Anything else

There is no npm package. The skill is plain Markdown. Clone the repo and point your agent at `skills/seedkit/SKILL.md`:

```sh
git clone https://github.com/RobustaRush/seedkit.git
```

Cursor, Aider, Codex, OpenCode — they can all read a file. Tell yours to follow `SKILL.md` and apply the references it names. Results vary with the model: the better ones do this without supervision; the cheaper ones need to be told twice.

## Known failure modes

The skill is a piece of paper; whether it works depends on the model holding it. From running the testcase suite repeatedly:

- **Smaller models drift back to the old API even when told not to.** Haiku, in particular, will write `STATICFILES_STORAGE = "..."` instead of the `STORAGES = {...}` dict the skill explicitly demands, because that's what the bulk of its training data shows. Sonnet does it about half as often. Opus rarely.
- **Smaller models don't enumerate the menu.** The skill says "ask the user about each add-on, one at a time, with a 1–2 sentence brief on what it does." Weaker models skip the brief, skip whole categories, and present truncated menus that quietly hide options the user might have wanted.
- **Split-settings is a recurring trap.** Even with explicit "deltas only, never restate `MIDDLEWARE` / `INSTALLED_APPS`" in `SKILL.md`, weaker models will copy entire lists from `base.py` into `local.py` because that's the shape of most "production-ready Django" tutorials they trained on. The skill catches some of this with a "Don't improvise" preamble; not all.
- **Reviewer agents flag intentional design as bugs.** Gated `default=... if DEBUG else None`, `globals().update(env.email_url(...))`, `wsgi.py` pointing at `production` — all of these come back as findings on every audit run. We carry a "reviewer-silence preamble" in `testcases/README.md` that lists the skill's intentional choices, and even then about a third of audits flag at least one of them.
- **The skill has no native re-run flow yet.** "Run later to add tasks" is what the design promises and the demo shows; in practice it works most of the time, but if your project has drifted (renamed apps, edited settings layout) the agent will read the drift, ask about it, and sometimes guess wrong. We're collecting cases where that happens and will tighten the rules.

These are not deal-breakers for daily use, but they are the kind of thing you should know before betting a deadline on this.

## Status

Experimental. The skill has no version worth printing, the testcases occasionally bicker about empty `REVIEW.md` files, and the install path for non-Claude agents is essentially "good luck." If you generate a project and something looks wrong, it probably is — file an issue with the testcase prompt and the file that misbehaved.

## License

MIT (per `.claude-plugin/plugin.json`). A `LICENSE` file will turn up eventually. Probably.
