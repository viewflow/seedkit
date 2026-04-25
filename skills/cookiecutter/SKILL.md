---
name: cookiecutter
description: Set up a new Django project with only the components you need.
---

## Prerequisites

```sh
uv --version
```

## Reference files

### Project foundation

- `references/uv.md` — uv installation and commands
- `references/new-project.md` — new project (Two Scoops layout, django-environ, uv)
- `references/docker.md` — Docker + local docker-compose

### Add-ons

- `references/redis.md` — Redis cache (django-redis)
- `references/storage-whitenoise.md` — static files (WhiteNoise) + media volume on VPS
- `references/storage-s3.md` — static and media on S3-compatible storage
- `references/tasks-celery.md` — background tasks with Celery + Redis
- `references/tasks-django.md` — background tasks with Django Tasks (DB or RQ backend)

### Going to production

- `references/security.md` — Django security settings
- `references/ci.md` — GitHub Actions test workflow
- `references/deploy-vps.md` — VPS deploy with Docker + Caddy
- `references/deploy-managed.md` — Fly.io / Railway / Render
- `references/deploy-github-ssh.md` — GitHub Actions deploy via SSH

## Instructions

Start by asking the project name and what it's for. Then set up the foundation.

After the foundation is in place, ask which add-ons the user wants before moving on to production setup.

Ask one question at a time. Never bundle multiple questions in a single message.

When the user wants production deployment, ask which target (VPS / managed service / GitHub SSH) before loading the deploy reference.

After any setup step, update `README.md` with the key decisions made (stack, selected add-ons, deployment target) and the main commands to run (install, test, migrate, run, deploy).
