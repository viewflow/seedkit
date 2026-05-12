# Deploy — GitHub Actions via SSH

Docs: <https://docs.github.com/en/actions> · <https://github.com/appleboy/ssh-action>

This pattern is built on top of `references/deploy-vps.md`. Read that first
— this file only adds the GitHub Actions wrapper. In particular, it inherits
`docker-compose.prod.yml`, the Caddy reverse proxy, and the `/healthz`
container healthcheck.

## Secrets

Set in repo settings:
- `SSH_HOST`
- `SSH_USER`
- `SSH_KEY`
- `GHCR_TOKEN` — a PAT with `read:packages`, used by the **server** to pull
  private images. `${{ secrets.GITHUB_TOKEN }}` is only valid inside Actions;
  the VPS needs its own credential.

## deploy/.env.prod.example — ship this in the repo

Lives next to `deploy/docker-compose.prod.yml`. `docker-compose.prod.yml`
references many vars; without a checked-in template the first deploy fails
with cryptic compose errors. Provide every var:

```sh
# Django
DJANGO_SETTINGS_MODULE=config.settings.production   # the rqworker / db_worker
                                                    # commands inherit this.
                                                    # manage.py defaults to
                                                    # config.settings.local —
                                                    # without this, prod runs
                                                    # with NO security hardening.
DJANGO_SECRET_KEY=
DJANGO_DEBUG=False
DJANGO_ALLOWED_HOSTS=example.com,localhost,127.0.0.1   # localhost/127.0.0.1 for the in-container healthcheck
DJANGO_CSRF_TRUSTED_ORIGINS=https://example.com
DJANGO_BEHIND_PROXY=True            # Caddy terminates TLS; required for
                                    # SECURE_SSL_REDIRECT to work right.
DATABASE_URL=postgres://postgres:CHANGE_ME@db:5432/postgres
REDIS_URL=redis://redis:6379

# Postgres
POSTGRES_PASSWORD=CHANGE_ME

# Image
GITHUB_REPOSITORY=owner/repo        # the GHCR image path
```

## .github/workflows/deploy.yml

```yaml
name: deploy

on:
  push:
    branches: [main]

# Two pushes in quick succession must serialize, not race on the same host.
concurrency:
  group: deploy
  cancel-in-progress: false

permissions:
  contents: read
  packages: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v5
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}:latest
          target: prod                              # only when references/docker.md `override` (multi-stage) layout is used

      # Pin third-party deploy actions to a SHA, not a major tag — this step
      # runs arbitrary shell on prod. Replace <SHA> with a recent commit.
      - uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_KEY }}
          script: |
            set -euo pipefail
            cd /srv/{project_slug}
            # Compose interpolates `${GITHUB_REPOSITORY}` from the host's
            # shell env (or a root `.env` file in the deploy dir) — it does
            # NOT pick it up from `env_file:` (that only sets container env).
            # Without an explicit export, the image line resolves to
            # `ghcr.io/:latest` and `compose pull` aborts.
            # `--env-file deploy/.env.prod` is required on every compose call
            # because compose's auto `.env` discovery only looks in the same
            # dir as the compose file — `deploy/.env.prod` lives there but the
            # filename isn't the one auto-loaded. Without the flag, every
            # `${VAR}` in compose.prod.yml resolves to empty.
            export GITHUB_REPOSITORY="${{ github.repository }}"
            # Authenticate the *server's* docker against ghcr.io. Without
            # this, `compose pull` against a private package silently fails
            # and `up -d` keeps running the previous image.
            echo "${{ secrets.GHCR_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
            docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml pull
            docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml run --rm web uv run manage.py migrate
            docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml up -d
            # Wait for the container healthcheck (defined in deploy-vps.md)
            # to flip to "healthy" — don't sleep-and-curl on plain HTTP if
            # SECURE_SSL_REDIRECT is on, that returns 301 and `curl` without
            # `-L` reads success regardless of the upstream actually being up.
            for i in $(seq 1 30); do
              status=$(docker inspect -f '{{ '{{' }}.State.Health.Status{{ '}}' }}' \
                $(docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml ps -q web) 2>/dev/null || echo starting)
              [ "$status" = "healthy" ] && exit 0
              sleep 2
            done
            echo "web never became healthy"; exit 1
```

## Test workflow — also pin `DJANGO_SETTINGS_MODULE`

`pyproject.toml`'s `[tool.pytest.ini_options]` typically defaults to
`config.settings.local`. With `DJANGO_DEBUG=False` in CI the local module
re-exports base, which requires a real `SECRET_KEY` — fragile chain.
Set `DJANGO_SETTINGS_MODULE` explicitly in the test job env, and add a
`manage.py check --deploy` step against `config.settings.production` so
regressions in security settings (SSL_REDIRECT without proxy, missing
HSTS, etc.) fail CI rather than first-deploy.
