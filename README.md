# Viewflow Seedkit 🌱

An agent skill to start new Django projects or extend existing ones. One sentence in, a running project out: packages wired together, dev/prod settings split, CI included.

```
/seedkit SaaS landing + waitlist, GDPR-friendly stack (mail, analytics, error reporting), VPS deploy
```

```
/seedkit add proper auth — magic link, lockout on brute force, optional 2FA
```

```
/seedkit look at our repo and tell us what's worth adding next
```

[![View Outputs](https://img.shields.io/badge/View%20Outputs-00C853?style=for-the-badge)](https://github.com/viewflow/seedkit-examples)
[![Fable 5 Audited](https://img.shields.io/badge/Fable%205-Audited-6A0DAD?style=for-the-badge)](./REVIEW.md)

LLMs write Django from memory, and that memory is a year or two old: deprecated auth settings, last version's Stripe webhooks, database ports open to the local network. seedkit keeps the knowledge in reference files instead — built from package docs, tested end-to-end, fixed after every failure. The model just types.

What that buys you:

- **Current APIs, not model memory.** References come from package docs, with version pins re-resolved at generation time.
- **Tested output.** Nine end-to-end scenarios: generate, boot, smoke-check, audit by a second LLM ([see the outputs](https://github.com/viewflow/seedkit-examples)). Every failure gets fixed back into the skill.
- **100+ hours of AI work, already spent.** The references distill the accumulated generate–boot–fix cycles, so scaffolding runs clean on mid-tier Sonnet — the frontier-model hours from your subscription go to the code only you can write.
- **Fable 5 audited.** Claude Fable 5 reviewed every reference file as a senior Django / systems engineer and the findings were fixed: gunicorn sized to the box, durable Redis broker, log rotation, test-gated deploys with SHA rollback. The full review, including what's still open, is in [REVIEW.md](./REVIEW.md).
- **Your exact stack.** Real alternatives at every step (Celery or RQ, allauth or magic links, VPS or Fly), `/seedkit add [feature]` for existing repos, and only the code for options you picked.

Helps you with: [Python deps & venvs](https://docs.astral.sh/uv/), [settings for dev vs prod](https://django-environ.readthedocs.io/), [custom user model](https://docs.djangoproject.com/en/stable/topics/auth/customizing/#substituting-a-custom-user-model), [social & password login](https://docs.allauth.org/), [passwordless magic-link login](https://django-mail-auth.readthedocs.io/), [brute-force protection](https://django-axes.readthedocs.io/), [background jobs](https://docs.celeryq.dev/), [async views](https://docs.djangoproject.com/en/stable/topics/async/), [WebSockets](https://channels.readthedocs.io/), [Redis caching](https://github.com/jazzband/django-redis), [S3 for static & media](https://django-storages.readthedocs.io/), [outbound email](https://anymail.dev/), [Tailwind without Node](https://django-tailwind-cli.readthedocs.io/), [GDPR-safe analytics](https://www.goatcounter.com/help/start), [security headers](https://docs.djangoproject.com/en/stable/topics/security/), [CSP headers](https://django-csp.readthedocs.io/), [production error tracking](https://docs.sentry.io/platforms/python/integrations/django/), [structured logs](https://www.structlog.org/), [N+1 query detection](https://github.com/PedroBern/django-zeal), [safe migrations](https://github.com/3YOURMIND/django-migration-linter), [linting & formatting](https://docs.astral.sh/ruff/), [type checking](https://microsoft.github.io/pyright/), [scheduled DB backups](https://django-dbbackup.readthedocs.io/), [Docker for local dev](https://docs.docker.com/compose/), [auto-HTTPS reverse proxy](https://caddyserver.com/docs/), [CI pipeline](https://docs.github.com/en/actions) — and more.

## Install

### Claude Code (plugin)

```sh
/plugin marketplace add viewflow/seedkit
/plugin install seedkit@viewflow
```

### Other agents (Cursor, Codex, OpenCode, Gemini CLI, …)

Via the [skills](https://github.com/vercel-labs/skills) CLI — installs into whichever agent dirs it detects:

```sh
npx skills add viewflow/seedkit            # project scope
npx skills add viewflow/seedkit -g         # global (all your projects)
npx skills add viewflow/seedkit -a cursor  # pin to one agent
```

Then, in whatever empty directory you'd like to populate:

```
/seedkit
```

## Two variants

Two skills ship in this repo.

**`/seedkit`** started from the actual package docs — the reference files have exact package versions, config snippets, and known pitfalls.

**`/seedkit-slim`** relies only on what the model already knows — no reference files.

Both go through the same test cycle: generate code, boot it, check it. Failures get fixed in the skill text.

## Project Status

This is a fresh project under active development. While the skill is verified against the nine core scenarios in [seedkit-examples](https://github.com/viewflow/seedkit-examples), we are still mapping out how the agent behaves outside that set.

The testcase harness currently runs only against Claude Sonnet. Other models (Opus, Haiku, GPT, Gemini) are not yet covered — they may work, but skill quality on those models is not verified.

Production deployment scenarios (VPS, Fly, GitHub-SSH) still need verification — they are wired up in the skill but not yet exercised end-to-end against real targets.

If you run into issues, strange behavior, or have ideas for new integrations, please open an issue. Feedback is welcome.

## Contributing

This is AI-generated code, and any human attention is valuable — a person reading it catches what the harness can't.

- **Hit a bug or something odd?** [Open an issue](https://github.com/viewflow/seedkit/issues/new) — even a one-line "this broke" helps.
- **Run it on another model.** We only verify on Claude Sonnet. Point `train/run-tests.sh` at Opus, Haiku, GPT, or Gemini and share the logs; cross-model coverage is what we need most.
- **Read the output before you trust it.** It boots and passes smoke checks, but hasn't seen production — your review is part of the loop.

For anything bigger, open an issue first so we can talk it through. Full test cycles take a couple hours, so it's worth saving each other the wasted run.

## License

[MIT](./LICENSE) — © 2026 Mikhail Podgurskiy.

<br>

---
<sub><i>$ Sorry, you're right. I probably shouldn't have deleted the production database.<br>&nbsp;&nbsp;&nbsp;Want me to at least write the restore script?</i></sub>
