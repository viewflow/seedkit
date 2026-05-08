# Linting — Ruff

Ruff replaces flake8, isort, pyupgrade, and most of pylint in one fast tool. The `DJ` ruleset covers Django-specific issues.

## Install

```sh
uv add --dev ruff
```

## pyproject.toml

```toml
[tool.ruff]
# target-version is auto-detected from `requires-python` in pyproject.toml
line-length = 100
extend-exclude = ["migrations", "*/migrations/*"]

[tool.ruff.lint]
select = [
    "E", "W",   # pycodestyle
    "F",        # pyflakes
    "I",        # isort
    "UP",       # pyupgrade
    "B",        # flake8-bugbear
    "DJ",       # flake8-django
    "S",        # flake8-bandit
    "SIM",      # flake8-simplify
    "RUF",      # ruff-specific
]
ignore = [
    "E501",     # line length — handled by formatter
    "S101",     # assert — fine in tests
]

[tool.ruff.lint.per-file-ignores]
"**/tests/**" = ["S"]
"**/test_*.py" = ["S"]
"**/settings/*.py" = ["F405", "F403"]   # star imports across settings layers

[tool.ruff.lint.isort]
known-first-party = ["{project_slug}"]

[tool.ruff.format]
quote-style = "double"
```

After installing and configuring Ruff, run once to normalize the just-generated codebase (`startproject` writes single quotes by default):

```sh
uv run ruff format .
uv run ruff check . --fix
```

## Poe tasks

Add to `[tool.poe.tasks]`:

```toml
lint   = "ruff check ."
fmt    = "ruff format ."
fix    = "ruff check . --fix"
```

Run:

```sh
uv run poe lint
uv run poe fmt
uv run poe fix
```

## Optional — pre-commit hook

Lightweight git hook (no `pre-commit` framework).

**.githooks/pre-commit**

```sh
#!/bin/sh
set -e
uv run ruff check .
uv run ruff format --check .
```

```sh
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

The `core.hooksPath` line is per-clone — document it in `README.md` so contributors enable it after cloning.

## CI

Add to `.github/workflows/test.yml` before `pytest`:

```yaml
      - run: uv run ruff check .
      - run: uv run ruff format --check .
```
