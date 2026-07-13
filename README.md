# CircleCI reference pipeline — Flask/Postgres, OIDC-published to Cloud Run

A small Flask + SQLAlchemy API, tested against a real Postgres sidecar,
packaged into a custom Docker image built inside the pipeline, and deployed
to Google Cloud Run — but only when a change lands on `main`, and only using
short-lived credentials obtained via OIDC (no service account key ever
stored in CircleCI).

## Repo layout
```
.circleci/
  config.yml            # setup workflow: decides whether to run anything at all
  continue-config.yml   # real pipeline: lint, build, test, publish
app/
  app.py                # Flask + SQLAlchemy service (non-scripting language)
  requirements.txt
tests/
  test_app.py            # pytest suite, emits JUnit XML
scripts/
  wait_for_postgres.sh   # shell scripting component, used by the test job
  publish_image.sh       # shell scripting component, used by the publish job
Dockerfile                # multi-stage build -> the "custom image"
```

---

## Part 1 — get the code on GitHub

You don't need any DevOps tooling for this part, just git.

1. Go to github.com, create a new **public** repository (empty, no README).
2. In this project folder, run:
   ```
   git init
   git add .
   git commit -m "Initial pipeline"
   git branch -M main
   git remote add origin https://github.com/<you>/<repo>.git
   git push -u origin main
   ```

## Part 2 — connect the repo to CircleCI

1. Go to [circleci.com](https://circleci.com), sign up/log in with GitHub.
2. In the CircleCI web app, go to **Projects**, find your repo, click **Set Up Project**.
3. When it asks about a config file, tell it you already have one at
   `.circleci/config.yml` — it'll detect it automatically once you push.
4. Go to **Project Settings → Advanced** and make sure **"Only build pull
   requests"** and dynamic config are on defaults (dynamic config is on by
   default for new projects — this is what makes the setup/continuation
   split work).

At this point, pushing to `main` will trigger the setup workflow. It'll run
and skip the real pipeline (because nothing under `app/`, `tests/`,
`scripts/`, `Dockerfile`, or `.circleci/` has "changed" relative to itself
yet — don't worry about this, once you push a real code change it'll behave
correctly). You don't need Google Cloud connected yet to see this part work.

## Part 3 — create a Google Cloud project (free, no charge for this scale)

1. Go to [console.cloud.google.com](https://console.cloud.google.com),
   sign up (Google gives new accounts free trial credit; Cloud Run also has
   an always-free monthly tier that easily covers this).
2. Create a new project — note its **Project ID** (not the display name)
   and its **Project number**, both shown on the project dashboard. You'll
   need both later.
3. In the console search bar, enable these APIs:
   - **Artifact Registry API**
   - **Cloud Run Admin API**
   - **IAM Service Account Credentials API**

4. Create an Artifact Registry Docker repo:
   **Artifact Registry → Repositories → Create Repository**
   - Format: Docker
   - Name: e.g. `app-images`
   - Region: pick one close to you, e.g. `us-central1`

## Part 4 — set up OIDC trust between CircleCI and GCP

This is the one genuinely "new" DevOps concept here: instead of generating a
GCP key file and pasting it into CircleCI as a secret, you tell GCP to trust
tokens that CircleCI issues, and let a CircleCI job trade its token for
temporary GCP access on the fly. Nothing long-lived ever leaves GCP.

1. **Find your CircleCI organization ID.** In the CircleCI web app,
   click **Org** in the sidebar → copy the Organization ID from the
   overview page.

2. **Create a service account** for CircleCI to act as:
   `IAM & Admin → Service Accounts → Create Service Account`
   - Name: `circleci-deployer`
   - Grant it these roles: `Artifact Registry Writer`, `Cloud Run Admin`,
     `Service Account User`

3. **Create a Workload Identity Pool + Provider:**
   `IAM & Admin → Workload Identity Federation → Create Pool`
   - Pool name: `circleci-oidc`
   - Add a provider, type **OpenID Connect (OIDC)**
     - Issuer: `https://oidc.circleci.com/org/<your-circleci-org-id>`
     - Audiences: select "Allowed audiences" and enter your CircleCI org ID
   - Attribute mapping:
     ```
     google.subject      = assertion.sub
     attribute.org_id     = assertion.aud
     attribute.project    = assertion['oidc.circleci.com/project-id']
     ```
   - Save, then click **Grant Access**, select the `circleci-deployer`
     service account you made above. This is what lets a CircleCI-issued
     token impersonate that service account.

4. Note down, from what you just created:
   - Your GCP **project number**
   - The **Workload Identity Pool ID** (e.g. `circleci-oidc`)
   - The **Provider ID** (e.g. `circleci`)
   - The service account email (e.g.
     `circleci-deployer@<project-id>.iam.gserviceaccount.com`)

## Part 5 — give CircleCI the connection details (not credentials)

In CircleCI: **Org Settings → Contexts → Create Context**, name it
`gcp-oidc-deploy`. Add these environment variables:

| Variable | Value |
|---|---|
| `GCP_PROJECT_ID` | your project **number** (not the text project ID) |
| `GCP_WIP_ID` | `circleci-oidc` |
| `GCP_WIP_PROVIDER_ID` | `circleci` |
| `GCP_SERVICE_ACCOUNT_EMAIL` | `circleci-deployer@<project-id>.iam.gserviceaccount.com` |
| `GCP_REGION` | e.g. `us-central1` |
| `AR_REPO` | `app-images` (the Artifact Registry repo name from Part 3) |

Then restrict this context: on the context page, add a **security group /
restriction** so it's only usable by this project — this is what satisfies
"credentials not accessible outside approved builds." Even without that
restriction, note that the `publish` job itself only runs `filters: branches:
only: main`, so a PR build never reaches this context at all.

## Part 6 — push and watch it go green

Make any small change under `app/`, `tests/`, or `scripts/` and push to
`main` (or open a PR first if you want to see the test job run without
publishing — publishing is gated to `main` only). Watch the pipeline in the
CircleCI web app:

1. `setup-workflow` runs, sees relevant files changed, triggers continuation
2. `lint-shell` → `build-image` → `test` (Postgres sidecar spins up
   automatically as part of the job, no separate setup needed)
3. On `main` only: `publish` authenticates via OIDC and deploys to Cloud Run

If something goes red, check in this order:
- **`gcloud iam workload-identity-pools create-cred-config` fails** → your
  `GCP_PROJECT_ID`/`GCP_WIP_ID`/`GCP_WIP_PROVIDER_ID` values don't match
  what you created in Part 4 exactly.
- **Auth succeeds but push/deploy is denied** → the service account is
  missing a role from Part 4 step 2, or the Workload Identity Federation
  "Grant Access" step wasn't completed.
- **Test job hangs before tests run** → the Postgres sidecar didn't come up
  in time; check `wait_for_postgres.sh` output, bump the timeout if needed.
- **Setup workflow doesn't trigger continuation** → double check dynamic
  config is enabled for the project (Part 2, step 4).

## How each requirement is met
| Requirement | Where |
|---|---|
| Public VCS repo connected to CircleCI | Part 1 & 2 |
| Custom Docker image built in pipeline | `build-image` job, multi-stage `Dockerfile` |
| Testing with collectible results | `test` job, `store_test_results` on `test-results/junit.xml` |
| Database via sidecar | `cimg/postgres:16.2` as a secondary container in `test` |
| Conditional work | `path-filtering` orb in the setup workflow skips the whole pipeline for irrelevant changes |
| Shell + non-scripting language | `scripts/*.sh` (bash) + `app/app.py` (Python/Flask) |
| Artifact published to cloud, main-only | `publish` job, `filters: branches: only: main` |
| Credentials restricted to approved builds | `context: gcp-oidc-deploy`, restricted, only attached to the main-only job |
| OIDC | Workload Identity Federation, no service account key stored anywhere |

---

## Writeup template (fill in after you have a green build)

**Repo:** `[link to your public repo]`
**Passing build:** `[link to the green CircleCI pipeline]`

### Architecture
This pipeline is split into two configs to make the conditional-work
requirement explicit: a lightweight **setup workflow** evaluates which files
changed and decides whether the **continuation pipeline** runs at all. When
it does, the continuation runs four jobs — lint the shell scripts, build a
custom multi-stage Docker image, run the test suite against a live Postgres
sidecar with results surfaced in CircleCI's Tests tab, and — only on merge
to `main` — authenticate to GCP via OIDC/Workload Identity Federation, push
the image to Artifact Registry, and deploy it to Cloud Run.

### Unique value / CircleCI features leveraged
- **Dynamic config + path-filtering** avoids burning compute on doc-only or
  unrelated changes.
- **`docker_layer_caching`** on the remote Docker environment for fast
  repeat builds.
- **OIDC via Workload Identity Federation** instead of a GCP service account
  key — nothing sensitive is stored in CircleCI, only identifiers.
- **Context restriction** scoped to the `main`-only job, so a PR from a fork
  can never reach GCP credentials.
- **Sidecar pattern** for Postgres keeps the test job hermetic and fast.

### Trade-offs / future optimizations
- Path-filtering diffs against `main`; a more granular mapping would let
  unrelated services in a monorepo skip each other's pipelines.
- One pinned Postgres version — a matrix build across supported versions
  would catch compatibility issues earlier.
- Cloud Run's `gcloud run deploy` here is a straight rollout; a canary
  rollout via traffic splitting (`--no-traffic` + gradual `update-traffic`)
  would reduce blast radius on a bad image.
- Build and test currently run sequentially; overlapping them would shorten
  total pipeline time at the cost of some config clarity.
