# together.

A small shared-expense app for trips and events, built with **Elixir, Phoenix LiveView, Ecto and SQLite**.

## Run locally

Requires Elixir and Erlang, plus the Phoenix installer (`mix archive.install hex phx_new`).

```sh
mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000). `mix setup` installs dependencies, creates/migrates the SQLite database and builds the assets. Run `mix test` to check the app.

## How it works

1. Create an event with a name and currency (EUR, USD or RUB). Bookmark its private link.
2. Open **People & families** from the event to add people, create families or couples, and assign people to them.
3. Return to **Expenses** to record what was purchased, the amount and who paid. Everyone is selected by default; uncheck anyone who should not share the expense. Costs are split equally between participating families and people without a family, regardless of family size. Selecting any member includes that family's one share. Any leftover cents are allocated deterministically.
   To remove a mistake, choose **Delete** in the expense history and confirm. Balances update immediately; any recorded payments remain in the ledger.
4. View balances and suggested transfers. Each family settles as one group, with no debts between its members. Two participating families split a cost **50/50**, even if one has more people. Current family assignments apply to all expense balances, including existing expenses; changing or deleting a family recalculates the split automatically.

Anyone holding an event link can see and edit that event. There are no accounts or payment confirmations. The landing page does not list events: keep the link to revisit one. One event uses one currency; amounts are stored as integer minor units without floating point math. Suggested transfers are recomputed from the ledger. The payment-entry UI is currently unavailable; previously recorded payments remain included in balances and can be viewed in **Previous payments**.

SQLite databases (`shared_expenses_dev.db` and `shared_expenses_test.db`) and local covers (`data/covers/`) are ignored by Git. Back up **both** the database and covers when retaining data. Use SQLite's `.backup` command or stop the app before copying a database that may be using WAL. Run the app from its project directory for the default cover location. SQLite suits a single running instance with persistent local storage.

## Docker Compose deployment

Production runs a Phoenix release in Docker Compose; database migrations run automatically on release startup. There are two build methods: compile directly on the VPS with Ansible (recommended), or build through a local/remote Docker context and transfer an image archive.

### Remote compilation with Ansible

Requirements: Ansible on your computer; Python, Docker with Buildx, Docker Compose and outbound HTTPS access on the VPS. No local Docker engine or Git installation on the VPS is needed. The source repository [ErDmKo/shared-expenses](https://github.com/ErDmKo/shared-expenses) must be public, and the commit to build must already be pushed to GitHub.

Set the host and SSH user in the ignored `ansible/inventory.yaml`, using `ansible/inventory.example.yaml` as a template. Configure SSH access separately. Run from the project root:

```sh
mix precommit
git push origin main
export SOURCE_REV="$(git rev-parse HEAD)"

# Build the exact published commit on the VPS without restarting the app.
ansible-playbook -i ansible/inventory.yaml ansible/build.yaml

# The image is already on the deployment host: no archive upload is needed.
SHARED_EXPENSES_IMAGE_ALREADY_LOADED=true \
PHX_HOST=expenses.example.com PHX_SCHEME=https PHX_PORT=443 APP_PORT=4001 \
ansible-playbook -i ansible/inventory.yaml ansible/push.yaml

curl --fail https://expenses.example.com/healthz
```

Replace the example hostname and ports with your deployment settings. Configure HTTPS separately before checking the public endpoint.

**What happens during the build:**

1. `ansible/build.yaml` validates the full 40-character `SOURCE_REV` and the VPS CPU architecture, then downloads that commit's source archive directly from GitHub into an isolated directory under `/opt/shared-expenses`. Branch names and local uncommitted changes are not used.
2. Docker executes the multi-stage `Dockerfile` on the VPS. The build stage installs dependencies, compiles Elixir in production mode, builds/minifies the JS and Tailwind CSS, and creates a Phoenix release. The smaller runtime image contains the release, not the source tree or build tools. Production secrets are supplied at deployment time, not baked into the image.
3. Buildx loads `shared-expenses:<first 12 characters of SOURCE_REV>` into the VPS's Docker engine. Set `IMAGE_TAG` to override the tag. `PLATFORM` defaults to `linux/amd64`; use `PLATFORM=linux/arm64` on an ARM VPS. This playbook requires a single, native-architecture target.
4. Only after a successful build, Ansible writes the ignored local `image.tag` and `image.platform` files used by `ansible/push.yaml`. The temporary source directory is removed even if compilation fails; Docker's build cache remains for faster rebuilds. The running service and its data are untouched by the build.
5. `ansible/push.yaml` verifies the image, updates Compose configuration, replaces the container, and waits up to 120 seconds for it to become healthy. `SHARED_EXPENSES_IMAGE_ALREADY_LOADED=true` skips copying/loading `image.tar` because compilation happened on the same host.

If a build fails, fix the problem and rerun it; do not deploy stale metadata from a previous build. If the image built successfully but deployment was interrupted, rerun just `ansible/push.yaml` with the same environment settings. `/healthz` should return `ok` with HTTP 200 after deployment.

### Docker-context build and image archive (alternative)

Build a Linux image through Docker, save it as `image.tar`, copy it to the server with Ansible, load it, and bring up Compose.

1. Set the SSH host in the ignored `ansible/inventory.yaml` (or copy `ansible/inventory.example.yaml`). Set `APP_PORT` to an unused host port if `4001` is taken.
2. Build on an amd64 Docker engine and deploy:

```sh
DOCKER_CONTEXT=shared-expenses-builder ./scripts/build-image.sh
ansible-playbook -i ansible/inventory.yaml ansible/push.yaml
```

Or use `./scripts/publish.sh` to build and run the playbook together. `INVENTORY` overrides its default inventory path. By default the build targets `linux/amd64`; set `PLATFORM=linux/arm64` for an ARM server. Each build gets a timestamped image tag in the ignored `image.tag` file; `image.platform` records its architecture so Ansible refuses a mismatched host.

An ARM Docker engine must support amd64 builds to target an amd64 server. If it does not, use a native amd64 Docker context: `docker context create shared-expenses-builder --docker host=ssh://user@your-server.example.com`, then `DOCKER_CONTEXT=shared-expenses-builder ./scripts/build-image.sh`. The build runs on that Docker engine and saves the archive locally; `BUILDER` can override the Buildx builder name if it differs from the context name. The script checks platform support before building.

If the Docker context points to the **same** server that Ansible deploys to, avoid downloading and re-uploading the image archive: `DOCKER_CONTEXT=shared-expenses-builder SKIP_IMAGE_SAVE=true ./scripts/build-image.sh` followed by `SHARED_EXPENSES_IMAGE_ALREADY_LOADED=true ansible-playbook -i ansible/inventory.yaml ansible/push.yaml`. The build script removes any stale `image.tar` in this mode; `scripts/publish.sh` sets the matching Ansible variable automatically.

Ansible and Docker SSH contexts use separate connection settings. Use `ansible/build.yaml` above to avoid configuring a Docker SSH context.

### Persistent data and HTTPS

The deployment playbook creates a production signing secret once and reuses it on later deployments. The database, WAL files, and uploaded covers remain in persistent storage across image replacements. Compose binds the application to loopback by default; use a reverse proxy for public HTTPS access and LiveView WebSocket upgrades. `ansible/https.yaml` and `ansible/nginx-shared-expenses.conf` provide an example setup; customize the hostname, ports, and certificate paths before using them.

For local Compose use, copy `.env.example` to `.env`, replace the sample hostname and secret, and set `SHARED_EXPENSES_IMAGE` to the tag in `image.tag` before running `docker compose up --detach --wait`. The Compose `./data` mount is separate from the development database in the project root; copying an existing database requires a SQLite-safe backup and suitable ownership for container UID `10001`.
