# uv

## Install

**macOS / Linux**
```sh
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Windows**
```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**Homebrew**
```sh
brew install uv
```

## Project

```sh
uv init {project_name}
uv add django
uv add --dev pytest ruff
uv remove django
uv sync
uv run manage.py runserver
uv run pytest
```

## Python

```sh
uv python install 3.12
uv python pin 3.12
```

## Tools

```sh
uvx ruff check .
uv self update
```
