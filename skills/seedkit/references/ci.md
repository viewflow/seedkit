# GitHub Actions — Tests

The workflow below runs `uv run pytest`. If pytest wasn't picked at foundation time, swap `uv run pytest` for `uv run manage.py test` (the workflow itself stays the same). Test runner setup — `pytest`, `pytest-django`, `pytest.ini` — lives in `references/pytest.md`.

## .github/workflows/test.yml

```yaml
name: test

on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 5s
          --health-timeout 5s
          --health-retries 5

    env:
      DATABASE_URL: postgres://postgres:postgres@localhost:5432/postgres
      DJANGO_SECRET_KEY: test-key
      DJANGO_DEBUG: "False"
      DJANGO_ALLOWED_HOSTS: "*"
      # `DEBUG=False` triggers the gated `env.NOTSET` branch on every
      # required env var. Provide safe placeholders so settings load:
      EMAIL_URL: consolemail://
      DEFAULT_FROM_EMAIL: test@example.com
      SERVER_EMAIL: test@example.com

    steps:
      - uses: actions/checkout@v4

      - uses: astral-sh/setup-uv@v3
        with:
          enable-cache: true

      - run: uv sync --frozen

      - run: uv run pytest        # or `uv run manage.py test` if pytest wasn't chosen
```

Don't add a `manage.py migrate` step before tests. `pytest-django` and Django's own test runner each build a `test_<dbname>` database from migrations on every run — a pre-step migrate touches the service DB, doesn't affect the test DB at all, and pollutes state for any later step that reuses the same connection.
