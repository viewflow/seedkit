# Deploy — GitHub Actions via SSH

Docs: <https://docs.github.com/en/actions> · <https://github.com/appleboy/ssh-action>

This pattern is built on top of `references/deploy-vps.md`. Read that first
— this file only adds the GitHub Actions wrapper. In particular, it inherits
`docker-compose.prod.yml`, the Caddy reverse proxy, and the `/healthz`
container healthcheck.

One change to the inherited `docker-compose.prod.yml`: the application image is
built and pushed by CI, and the owner isn't known at scaffold time. Point it at
the exported env vars, not a hardcoded `{owner}/{project_slug}`:

```yaml
    image: ghcr.io/${GITHUB_REPOSITORY}:${IMAGE_TAG:-latest}
```

The deploy workflow exports `IMAGE_TAG` as the commit SHA, so every deploy is
addressable and `## Rollback` below can pin any previous one; manual compose
calls without the var fall back to `:latest`.

## Secrets

Set in repo settings:
- `SSH_HOST`
- `SSH_USER`
- `SSH_KEY`
- `GHCR_TOKEN` — a PAT with `read:packages`, used by the **server** to pull
  private images. `${{ secrets.GITHUB_TOKEN }}` is only valid inside Actions;
  the VPS needs its own credential.

## deploy/.env.prod.example — ship this in the repo

`references/deploy-vps.md` defines the base template. Append one section for
the GHCR image path:

```sh
# On upgrades retain the current Compose project name.
COMPOSE_PROJECT_NAME={project_slug}
GITHUB_REPOSITORY=owner/repo        # the GHCR image path
```

`IMAGE_TAG` is not listed — the deploy workflow exports it as the commit SHA and
the compose file falls back to `:latest`.

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
  # The gate: red tests never reach the server. Requires the `workflow_call`
  # trigger on test.yml (references/ci.md). If CI wasn't applied, drop this
  # job and the `needs: test` line.
  test:
    uses: ./.github/workflows/test.yml

  deploy:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7

      - uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v7
        with:
          push: true
          # :latest for humans, :<sha> so every deploy stays pullable for rollback.
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ github.sha }}
          target: prod                              # matches the `prod` stage in references/docker.md
          build-args: |
            GIT_SHA=${{ github.sha }}

      # Pin third-party deploy actions to a commit SHA, not a tag — this step
      # runs arbitrary shell on prod. Resolve the SHA of the latest release:
      #   gh api repos/appleboy/ssh-action/git/ref/tags/<latest-tag> --jq .object.sha
      - uses: appleboy/ssh-action@<SHA>  # v1.2.5
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_KEY }}
          script: |
            set -euo pipefail
            cd /srv/{project_slug}
            git fetch origin main
            git checkout --no-overwrite-ignore --detach "${{ github.sha }}"
            export GITHUB_REPOSITORY="${{ github.repository }}"
            echo "${{ secrets.GHCR_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
            sh deploy/release.sh deploy
            docker image prune -f
```

When this reference is applied together with `references/ci.md`, remove the
`push:` trigger from `test.yml` — the deploy workflow already runs it on every
main push via `workflow_call`, and both triggers firing doubles every CI run.

## VPS checkout and release script

On the VPS, give the deploy user read access to the project repository and clone it once into `/srv/{project_slug}`. Use a dedicated checkout and a unique Compose project name for this application. Set `COMPOSE_PROJECT_NAME` in the server env file. On an existing installation, use the current name from `docker compose ls` so the same volumes are selected. Copy `deploy/.env.prod.example` to the gitignored `deploy/.env.prod`, fill in the server credentials and set `GITHUB_REPOSITORY` to the GHCR repository path there. Preserve the server-owned env file when moving an existing deployment into the checkout.

Save as `deploy/release.sh`. Use the same SHA-tagged image for web, workers, beat and other application processes. Keep the container liveness probe on `/healthz`. For SQLite with Litestream omit the migration command (the web entrypoint owns it). With static files on S3 run `compose run --rm web python manage.py collectstatic --noinput` during deployment.

```sh
#!/bin/sh
set -eu
mode=${1:?use deploy or rollback}
case "$mode" in deploy|rollback) ;; *) exit 2 ;; esac
git diff --quiet HEAD -- deploy || { echo "Tracked deployment files have local changes" >&2; exit 1; }
IMAGE_TAG=$(git rev-parse --verify HEAD)
export IMAGE_TAG
compose() {
    docker compose --env-file deploy/.env.prod -f deploy/docker-compose.prod.yml "$@"
}

compose pull
if [ "$mode" = deploy ]; then
    compose run --rm web python manage.py migrate --noinput
fi
compose up -d --remove-orphans
# Git checkout replaces the bind-mounted Caddyfile inode.
compose up -d --no-deps --force-recreate caddy
for attempt in $(seq 1 30); do
    if compose exec -T web python -c 'import http.client, sys; c = http.client.HTTPConnection("localhost", 8000, timeout=2); c.request("GET", "/readyz"); sys.exit(c.getresponse().status != 200)'; then
        exit 0
    fi
    sleep 2
done
echo "Release $IMAGE_TAG failed /readyz" >&2
exit 1
```

## Rollback

Use a known-good full commit SHA whose image is still in GHCR and whose schema is compatible with the current database:

```sh
cd /srv/{project_slug}
git fetch origin main
git checkout --no-overwrite-ignore --detach "${KNOWN_GOOD_SHA:?set a known-good commit SHA}" &&
    sh deploy/release.sh rollback
```

## Test workflow — also pin `DJANGO_SETTINGS_MODULE`

`references/pytest.md` pins `DJANGO_SETTINGS_MODULE = config.settings.test`
in the pytest config — CI inherits it, no test-job override needed. Keep the
`manage.py check --deploy` step against `config.settings.production`
(`references/ci.md`) so regressions in security settings (SSL_REDIRECT
without proxy, missing HSTS, etc.) fail CI rather than first-deploy.
