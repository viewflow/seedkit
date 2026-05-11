# Robusta Seedkit 🌱

An agent skill to start new Django projects or extend existing ones.

```
/seedkit SaaS landing + waitlist, GDPR-friendly stack (mail, analytics, error reporting), VPS deploy
```

```
/seedkit add proper auth — magic link, lockout on brute force, optional 2FA
```

```
/seedkit look at our repo and tell us what's worth adding next
```

[![View Outputs](https://img.shields.io/badge/View%20Outputs-00C853?style=for-the-badge)](https://github.com/RobustaRush/seedkit-examples)

Helps you with: [Python deps & venvs](https://docs.astral.sh/uv/), [settings for dev vs prod](https://django-environ.readthedocs.io/), [custom user model](https://docs.djangoproject.com/en/stable/topics/auth/customizing/#substituting-a-custom-user-model), [social & password login](https://docs.allauth.org/), [passwordless magic-link login](https://django-mail-auth.readthedocs.io/), [brute-force protection](https://django-axes.readthedocs.io/), [background jobs](https://docs.celeryq.dev/), [Redis caching](https://github.com/jazzband/django-redis), [S3 for static & media](https://django-storages.readthedocs.io/), [outbound email](https://anymail.dev/), [Tailwind without Node](https://django-tailwind-cli.readthedocs.io/), [GDPR-safe analytics](https://www.goatcounter.com/help/start), [security headers](https://docs.djangoproject.com/en/stable/topics/security/), [CSP headers](https://django-csp.readthedocs.io/), [production error tracking](https://docs.sentry.io/platforms/python/integrations/django/), [structured logs](https://www.structlog.org/), [N+1 query detection](https://github.com/PedroBern/django-zeal), [safe migrations](https://github.com/3YOURMIND/django-migration-linter), [linting & formatting](https://docs.astral.sh/ruff/), [type checking](https://microsoft.github.io/pyright/), [scheduled DB backups](https://django-dbbackup.readthedocs.io/), [Docker for local dev](https://docs.docker.com/compose/), [auto-HTTPS reverse proxy](https://caddyserver.com/docs/), [CI pipeline](https://docs.github.com/en/actions) — and more.

## Install

### Claude Code (plugin)

```sh
/plugin marketplace add RobustaRush/seedkit
/plugin install seedkit@robusta
```

### Other agents (Cursor, Codex, OpenCode, Gemini CLI, …)

Via the [skills](https://github.com/vercel-labs/skills) CLI — installs into whichever agent dirs it detects:

```sh
npx skills add RobustaRush/seedkit            # project scope
npx skills add RobustaRush/seedkit -g         # global (all your projects)
npx skills add RobustaRush/seedkit -a cursor  # pin to one agent
```

Then, in whatever empty directory you'd like to populate:

```
/seedkit
```

## What you get

- Ready-to-run Django project.
- Pick your stack — real alternatives at every step.
- Smart additions: `/seedkit add [feature]` safely appends code without overwriting.
- No unused boilerplate.
- Sane defaults out of the box.
- Low token footprint.

## Contributing

Please [open an issue](https://github.com/RobustaRush/seedkit/issues/new) before sending a pull request — even a one-liner. The skill is opinionated and a quick chat usually saves both sides from a wasted PR.

## License

[MIT](./LICENSE) — © 2026 Mikhail Podgurskiy.

<br>

<sub><i>$ Sorry, you're right. I probably shouldn't have deleted the production database.<br>&nbsp;&nbsp;Want me to at least write the restore script?</i></sub>
