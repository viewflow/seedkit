# Cookiecutter test cases

End-to-end checks for the `cookiecutter` skill. Each test case is a single self-contained prompt that fully specifies every answer the skill would otherwise ask for, so the AI can run it without stopping for clarification. After execution, the AI appends a **check report** to the same file describing what worked, what didn't, and which manual fixes were applied to make it work.

The point is to catch drift between the skill's references and reality (Django version bumps, uv flags, Docker quirks, package renames) by running real builds.

## How a test case is structured

Each test case is one `.md` file:

```
# <Title>

## Prompt
<Single fully-specified instruction for `/cookiecutter`. No open questions.>

## Expected outcome
- Project boots (runserver or `docker compose up`)
- `/admin/` login works after `createsuperuser`
- <any add-on-specific check, e.g. "celery worker picks up a task">

## Run
<commands the AI should execute end-to-end>

## Check report
Run `claude -p` from the project dir with `--model claude-opus-4-7`,
restricted to read-only tools so the reviewer can't trigger the
cookiecutter skill and rebuild the project. Tell the reviewer the
project is a freshly generated *starter / scaffold* with no business
logic on purpose, so it focuses on config / security / deployment
correctness rather than flagging the missing feature code. Word the
prompt as "audit the existing code", not "review the Django project" —
the latter pattern-matches the skill description and starts a build.
Pipe the output to `REVIEW.md` inside the project (`| tee REVIEW.md`)
so the report is persisted next to the code. Paste a digest below.

- What worked out of the box: …
- What broke: …
- Fixes applied: …
- Suggested skill changes: …

## Cleanup
<commands to drop external resources: host DBs, docker volumes, built
images, deployed remote artifacts. Run *after* the review so the
reviewer can still inspect a live stack. Leave the project code in
place — the report references it.>
```

## Requirements for the test set

Coverage rules. Use these to regenerate the suite when the skill changes.

1. **Test case 1 is the minimal example.** SQLite, single-file settings, uv-on-host, no lint, no add-ons, no production. This is the smallest path that boots a working project. If this fails, nothing else matters.

2. **Group orthogonal answers into the smallest number of test projects** that still touches every option at least once. Do not enumerate the full Cartesian product. Pairwise coverage across the variation dimensions below is the target.

3. **Variation dimensions to cover** (every value of each must appear in at least one test case):

   **Foundation**
   - Settings layout: `single` / `split`
   - Database: `sqlite` / `postgres`
   - Local dev mode: `uv-host` / `docker-compose`
   - Postgres location (only when `postgres` + `uv-host`): `host` / `docker-db-only`
   - Custom user model (`AUTH_USER_MODEL`): `yes` / `no`
   - Lint (Ruff): `yes` / `no`

   **Add-ons** (each at least once across the suite, but not in the minimal case)
   - Auth: `django-allauth` / `django-mail-auth` / `none`
   - Debug: `django-orbit` / `django-silk` / `none`
   - Redis: `yes` / `no`
   - Storage: `whitenoise` / `s3` / `none`
   - Tasks: `celery` / `django-tasks-db` / `django-tasks-rq` / `none`
   - Email: `console` / `smtp` / `mailpit` / `none`
   - Analytics: `goatcounter` / `umami` / `shynet` / `ga4` / `none`

   **Production** (separate test cases focused on deploy)
   - Security settings: applied / not applied
   - Error reporting: `bugsink` / `sentry` / `glitchtip` / `none`
   - GDPR: `yes` / `no`
   - CI: `yes` / `no`
   - Deploy target: `vps` / `managed` / `github-ssh`
   - Production Dockerfile: `single-stage` / `multi-stage`

4. **Respect dependencies between options.** If the skill requires Redis for Celery, the test case must enable Redis. Don't write impossible combinations.

5. **Each prompt must be self-contained.** The AI should never need to ask follow-up questions. Phrase the prompt as a complete spec: project name, purpose, every choice listed explicitly.

6. **Each test case must run end-to-end** in the chosen dev mode, including `migrate`, `createsuperuser`, and the boot check (admin login). Add-on-specific checks (e.g. "enqueue and consume a Celery task") belong in the test case.

7. **Check report is mandatory and produced by an independent reviewer.** After running, invoke `claude -p "..." --model claude-opus-4-7` from a fresh session against the generated project; do not let the same model that built the project grade its own output. Paste the reviewer's response into the report and add the human-curated bullets (what worked, what broke, fixes applied, suggested skill changes). The report drives skill improvements.

8. **Keep the suite small.** Aim for ~6–10 test cases total. Beyond that, maintenance cost outweighs coverage value. Drop a case before adding a redundant one.

## Running a test case

The harness is the AI itself. Open a fresh working directory, paste the prompt, let `/cookiecutter` run end-to-end, and append the check report. No automated runner — the value is in seeing whether the skill produces a working project unattended, not in shell-level assertions.

## When to regenerate

Regenerate the suite (delete current test files and rewrite from this README) whenever:

- A new variation dimension is added to the skill.
- A reference file is split or merged in a way that changes the question flow.
- Multiple test cases end up reporting the same fix — that's a signal the suite is redundant.
