# CircleCI reference pipeline — Flask/Postgres image, published to Vercel

A small Flask + SQLAlchemy API, tested against a real Postgres sidecar,
packaged into a custom Docker image that is itself smoke-tested in the
pipeline, then deployed to **Vercel** — but only when a change lands on
`main`, and only using credentials from a restricted CircleCI context.

**Repo:** https://github.com/salmanawanpro/CircleCli-Python-Pipeline  
**Passing build:** _paste your green CircleCI pipeline URL here after the first successful run_

---

## Architecture

The pipeline is split across two configs so conditional work is explicit:

1. **Setup** ([`.circleci/config.yml`](.circleci/config.yml)) — the `path-filtering` orb diffs against `main`. Irrelevant changes (docs-only, etc.) never continue into a build.
2. **Continuation** ([`.circleci/continue-config.yml`](.circleci/continue-config.yml)) — when `run-build` is true:
   - `lint-shell`, `unit-test`, and `build-image` run in **parallel**
   - `image-test` loads the pipeline-built image, starts Postgres as a sibling container on remote Docker, and runs HTTP smoke tests against that image
   - `publish` deploys to Vercel production **only on `main`**, using the `vercel-deploy` context — and only when pipeline parameter `deploy` is `true` (default `false` so CI can go green before Vercel is wired up)

```
push/PR
  └─ setup (path-filtering)
        └─ continuation (when app/tests/scripts/Dockerfile/vercel/circleci change)
              ├─ lint-shell ────────┐
              ├─ unit-test ─────────┼─► image-test ─► publish (main only → Vercel)
              └─ build-image ───────┘
```

| Challenge requirement | How this pipeline meets it |
|---|---|
| Public VCS + CircleCI | This GitHub repo connected to CircleCI |
| Custom Docker image built in pipeline | `build-image` + multi-stage `Dockerfile` |
| Image used during the pipeline | `image-test` loads `image.tar` and smoke-tests it |
| Collectible test results | pytest JUnit → `store_test_results` |
| Database + sidecar | `cimg/postgres` sidecar in `unit-test`; sibling Postgres on remote Docker in `image-test` |
| Conditional work | Path-filtering + `requires` + `main`-only publish |
| Shell + non-scripting language | `scripts/*.sh` + Flask/Python |
| Publish artifact to PaaS on default branch | Vercel production via `publish` job |
| Credentials only on approved builds | Restricted `vercel-deploy` context, attached only to the `main` publish job |

---

## Unique value / CircleCI features

- **Dynamic config + path-filtering** — skip the entire expensive pipeline when only unrelated files change.
- **The artifact under test is the artifact you ship** — unit tests stay fast on `cimg/python`; `image-test` proves the built image boots and talks to Postgres before any deploy.
- **Layered conditionals** — path filter → job `requires` (failed unit/build skips smoke/publish) → branch filter on `publish`.
- **Docker Layer Caching** on image build/test remote Docker environments.
- **Pip cache** on `unit-test` keyed by dependency lock files.
- **Restricted context** — `VERCEL_TOKEN` never appears on PR/fork jobs.

### OIDC note

Vercel does not accept CircleCI as an OIDC identity provider for CLI deploys (official guidance uses a scoped access token). This reference pipeline therefore stores a short-scoped `VERCEL_TOKEN` in a **restricted CircleCI context** and only attaches that context to the `main`-only publish job. If your org requires keyless cloud auth end-to-end, the same pattern swaps cleanly to Cloud Run / ECR with Workload Identity Federation.

---

## Operator setup

### 1. CircleCI (already connected)

Confirm **Project Settings → Advanced → Enable dynamic config** is on (needed for setup/continuation).

### 2. Vercel project

1. Create a project at [vercel.com](https://vercel.com) for this repo (or run `vercel link` locally once).
2. Create an access token (Account Settings → Tokens), scoped as narrowly as your plan allows.
3. From `.vercel/project.json` after linking, note `orgId` and `projectId`.
4. Set production `DATABASE_URL` in the **Vercel** project environment (not in CircleCI) so deploy credentials and DB credentials stay separated.
5. Optional: disable Vercel Git auto-deploy for production so CircleCI owns the gated release path.

### 3. CircleCI context `vercel-deploy`

**Org Settings → Contexts → Create Context** named `vercel-deploy`:

| Variable | Value |
|---|---|
| `VERCEL_TOKEN` | your Vercel access token |
| `VERCEL_ORG_ID` | org id from `.vercel/project.json` |
| `VERCEL_PROJECT_ID` | project id from `.vercel/project.json` |

Restrict the context to this project (security group / project restriction) so only approved builds can read it.

### 4. First green run (no Vercel yet)

Push to `main` / open a PR. With `deploy: false` (the default), the pipeline runs `lint-shell` → `unit-test` / `build-image` → `image-test` and **skips** Vercel. Paste that green CircleCI pipeline URL into the header of this README.

### 5. Enable Vercel publish

After steps 2–3 above, either trigger a pipeline with parameter `deploy=true`, or change the `deploy` default in [`.circleci/continue-config.yml`](.circleci/continue-config.yml) to `true`. On `main`, `publish` will then deploy and print a Vercel production URL.

---

## Trade-offs / future optimizations

- **Preview deploys on PRs** — a non-prod `vercel deploy` (no `--prod`) behind a separate, still-restricted context would give reviewers live URLs without touching production.
- **Managed Postgres in CI** — today’s sidecar is hermetic and free; a shared Neon/Vercel Postgres branch strategy would closer match production at the cost of external coupling.
- **True OIDC** — replace Vercel publish with Cloud Run + WIF (or ECR) if keyless cloud auth is a hard requirement.
- **Canary / traffic splitting** — Vercel instant rollback is the current safety net; progressive exposure would need an additional edge/CDN strategy.
- **Finer path maps** — in a monorepo, map services independently so one app’s change does not rebuild another.

---

## Local development

```bash
# Start Postgres (example)
docker run --rm -d -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=app \
  --name local-pg cimg/postgres:16.2

export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/app
pip install -r requirements.txt -r tests/requirements-test.txt
pytest tests/test_app.py
python -m app.app
```
