# 09 — Production: GitHub Actions SSH deploy, Bugsink, Umami, Django Tasks (RQ)

Covers the GitHub-Actions-over-SSH deploy path, self-hosted Bugsink for error reporting, Umami analytics, Django Tasks with the Redis Queue backend, GDPR scaffolding, and CI.

## Prompt

```
/cookiecutter

Project name: 09-ssh-deploy
Purpose: production app deployed to a remote host over SSH from GitHub Actions, using self-hosted services.

Settings layout: split.
Database: PostgreSQL.
Local dev mode: docker-compose (web + db + redis).
Lint with Ruff: yes.
Custom user model: no.
Auth add-on: none.
Add-ons:
  - redis
  - tasks: Django Tasks with the Redis Queue backend (`django-tasks-rq`)
  - analytics: Umami (self-hosted, env-driven website ID and host)
Production setup:
  - apply Django security settings
  - error reporting: Bugsink (self-hosted, sentry-sdk DSN)
  - GDPR: PII scrubbing in error reports, retention defaults, user data export/delete
  - CI: GitHub Actions test workflow
  - deploy: GitHub Actions deploy via SSH (rsync + remote `docker compose pull && up -d`)
  - production Dockerfile: single-stage (small enough; multi-stage not needed)

Run the foundation + boot check locally. Generate `Dockerfile`, `docker-compose.prod.yml`, `.github/workflows/test.yml`, `.github/workflows/deploy.yml`. Do not actually deploy — verify all artifacts are present, `docker build .` succeeds, and the deploy workflow references `secrets.SSH_HOST`, `secrets.SSH_USER`, `secrets.SSH_KEY`.
```

## Expected outcome

- Local `docker compose up -d` starts web + db + redis + worker; `/admin/` login works.
- `worker` runs `manage.py rqworker default` and processes a queued task.
- Bugsink wired via `sentry-sdk` in `production.py`, DSN from env.
- Umami snippet in base template (website ID + host from env).
- GDPR scaffolding present (PII scrubber, export/delete views or commands).
- `.github/workflows/test.yml` runs migrations + pytest.
- `.github/workflows/deploy.yml` uses SSH secrets, rsyncs source, runs `docker compose pull && up -d` on the remote.
- Security settings applied only in `production.py`.

## Run

```sh
# Run from a scratch parent dir; the skill creates `09-ssh-deploy/`.
# AI executes the skill here, then:
cd 09-ssh-deploy
docker compose up -d
docker compose exec web uv run manage.py migrate
curl -sf http://127.0.0.1:8000/admin/login/ > /dev/null
docker build -t 09-ssh-deploy:test .
grep -E 'SSH_(HOST|USER|KEY)' .github/workflows/deploy.yml
```

## Check report

**Execute this command yourself before stopping. Do not present it as a "next step" for the user — the testcase isn't done until the review file exists.** It runs an independent review (the model that built the project shouldn't grade its own output) and writes the result to `REVIEW.md` in the project dir.

```sh
claude -p \
  --model claude-opus-4-7 \
  --allowedTools "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*)" \
  "Audit the existing code in this directory. This is a freshly generated Django *project starter / scaffold* — there is intentionally no business logic, no app code, no real content. Focus on configuration correctness, security, deployment readiness, and adherence to Django best practices for a starter. Do NOT flag the absence of feature code, app modules, or domain models. Do NOT create, generate, or modify any files — read-only review only. Do NOT invoke any skill (especially cookiecutter). List bugs, inconsistencies, and concrete fixes. Be brief, top issues first." \
  | tee REVIEW.md
```

Paste the output below.

- What worked out of the box:
- What broke:
- Fixes applied:
- Suggested skill changes:

## Cleanup

Leave the code. Tear down local containers and the built image. If you actually ran the deploy workflow, SSH into the remote and `docker compose down -v` there, then revoke the deploy SSH key from `~/.ssh/authorized_keys` and the GitHub repo secrets.

```sh
docker compose down -v
docker rmi 09-ssh-deploy:test
```
