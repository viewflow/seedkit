# Deploy — GitHub Actions via SSH

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

## .env.prod.example — ship this in the repo

`docker-compose.prod.yml` references many vars; without a checked-in template
the first deploy fails with cryptic compose errors. Provide every var:

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
DJANGO_ALLOWED_HOSTS=example.com
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
            # Authenticate the *server's* docker against ghcr.io. Without
            # this, `compose pull` against a private package silently fails
            # and `up -d` keeps running the previous image.
            echo "${{ secrets.GHCR_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
            docker compose -f deploy/docker-compose.prod.yml pull
            docker compose -f deploy/docker-compose.prod.yml run --rm web uv run manage.py migrate
            docker compose -f deploy/docker-compose.prod.yml up -d
            # Wait for the container healthcheck (defined in deploy-vps.md)
            # to flip to "healthy" — don't sleep-and-curl on plain HTTP if
            # SECURE_SSL_REDIRECT is on, that returns 301 and `curl` without
            # `-L` reads success regardless of the upstream actually being up.
            for i in $(seq 1 30); do
              status=$(docker inspect -f '{{ '{{' }}.State.Health.Status{{ '}}' }}' \
                $(docker compose -f deploy/docker-compose.prod.yml ps -q web) 2>/dev/null || echo starting)
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
