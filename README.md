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

The workflow follows `month.erdmko.de`: build a Linux image locally, save it as `image.tar`, copy it to the server with Ansible, load it with Docker, and bring up Compose. The image runs a Phoenix release; database migrations run automatically on release startup.

1. Set the SSH host in the ignored `ansible/inventory.yaml` (or copy `ansible/inventory.example.yaml`). Set `APP_PORT` to an unused host port if `4001` is taken.
2. Build on an amd64 Docker engine and deploy:

```sh
DOCKER_CONTEXT=shared-expenses-builder ./scripts/build-image.sh
ansible-playbook -i ansible/inventory.yaml ansible/push.yaml --private-key ~/.ssh/id_rsa_legacy
```

Or use `./scripts/publish.sh --private-key ~/.ssh/your_key` to build and run the playbook together. `INVENTORY` overrides its default inventory path. By default the build targets `linux/amd64`, matching the month deployment; set `PLATFORM=linux/arm64` for an ARM server. Each build gets a timestamped image tag in the ignored `image.tag` file; `image.platform` records its architecture so Ansible refuses a mismatched host.

An ARM Docker engine must support amd64 builds to target an amd64 server. If it does not (for example, this Mac's Colima builder), use a native amd64 Docker context: `docker context create shared-expenses-builder --docker host=ssh://user@your-server.example.com`, then `DOCKER_CONTEXT=shared-expenses-builder ./scripts/build-image.sh`. The build runs on that Docker engine and saves the archive locally; `BUILDER` can override the Buildx builder name if it differs from the context name. The script checks platform support before building.

If the Docker context points to the **same** server that Ansible deploys to, avoid downloading and re-uploading the image archive: `DOCKER_CONTEXT=shared-expenses-builder SKIP_IMAGE_SAVE=true ./scripts/build-image.sh` followed by `SHARED_EXPENSES_IMAGE_ALREADY_LOADED=true ansible-playbook -i ansible/inventory.yaml ansible/push.yaml --private-key ~/.ssh/id_rsa_legacy`. The build script removes any stale `image.tar` in this mode; `scripts/publish.sh` sets the matching Ansible variable automatically.

The playbook generates a production signing secret on the server once, keeps it in `/opt/shared-expenses/secret_key_base` and reuses it on later deployments. It writes `/opt/shared-expenses/.env` and keeps the database, its WAL files, and uploaded covers in `/opt/shared-expenses/data` across image replacements. Compose publishes **only** `127.0.0.1:4001` by default. The separate `ansible/https.yaml` playbook configures Nginx to serve `https://erdmko.dev:4004` with the existing certificate and proxy to that loopback port, including LiveView WebSocket upgrades. Set `PHX_HOST=erdmko.dev PHX_SCHEME=https PHX_PORT=4004` when running `ansible/push.yaml` for this endpoint, then run `ansible/https.yaml`. The existing site on ports 80/443 is unchanged. For server-only access, the SSH tunnel `ssh -L 4001:127.0.0.1:4001 -i ~/.ssh/id_rsa_legacy root@erdmko.dev` remains available.

For local Compose use, copy `.env.example` to `.env`, replace the sample hostname and secret, and set `SHARED_EXPENSES_IMAGE` to the tag in `image.tag` before running `docker compose up --detach --wait`. The Compose `./data` mount is separate from the development database in the project root; copying an existing database requires a SQLite-safe backup and suitable ownership for container UID `10001`.
