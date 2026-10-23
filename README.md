# rtb-n8n

A self-hosted [n8n](https://n8n.io) stack running on Docker Compose. It is based on n8n's official Docker Compose setup and includes:

| Service | Purpose |
| --- | --- |
| `n8n` | The n8n app and editor, at <http://localhost:5678> |
| `runners` | External task runners that run the code from Code nodes |
| `sandbox-certs` | One-off setup step that creates the mTLS certificates the sandbox services use |
| `sandbox-api` | Sandbox service API that n8n talks to |
| `sandbox-runner-1` | Docker-in-Docker runner that starts sandbox containers |
| `searxng` | Private SearXNG search engine, used for web search by n8n's AI features |

Only `n8n` publishes a port to the host. All other services can be reached only by name inside the Compose network.

## Prerequisites

- Docker Engine with the Compose plugin (`docker compose`, not `docker-compose`)
- `bash` and `openssl`, to generate secrets
- Permission to run privileged containers (needed by `sandbox-runner-1`)

## Setup

### 1. Get the repository

```bash
git clone <repo-url> rtb-n8n
cd rtb-n8n
```

### 2. Create your `.env`

```bash
cp example.env .env
```

`.env` holds secrets and is excluded by `.gitignore`. Never commit it.

### 3. Set the versions

Open `.env` and set both version numbers:

| Variable | Where to find the version |
| --- | --- |
| `N8N_VERSION` | The latest stable release at <https://github.com/n8n-io/n8n/releases> |
| `N8N_SANDBOX_VERSION` | The latest stable **service** release at <https://github.com/n8n-io/n8n-sandbox-service/releases>. Skip staging prereleases. |

`N8N_VERSION` sets the version of both `n8n` and `runners`. `N8N_SANDBOX_VERSION` sets the version of all three sandbox images, which are only supported when they run the same version.

### 4. Generate secrets

```bash
./generate-secrets.sh
```

This replaces every `change-me-*` secret in `.env` with a random value and sets the file's permissions to `600`. It leaves all other lines, including the versions, unchanged.

> **Warning:** Running the script again creates new values for **all** secrets. If you do this on a running stack, restart it afterwards with `docker compose up -d --force-recreate` so every service gets the new values.

To write to a different file, pass its path: `./generate-secrets.sh /path/to/other.env`.

### 5. Start the stack

```bash
docker compose up -d
docker compose ps
```

The services start in this order:

1. `sandbox-certs` creates the certificates, then exits. Its status shows as `Exited (0)`, which is expected.
2. `sandbox-api` starts and waits until its health check passes.
3. `sandbox-runner-1` and `n8n` start.
4. `runners` starts.

### 6. Verify

```bash
# n8n is up
curl -sf http://localhost:5678/healthz && echo " n8n OK"

# n8n can reach the sandbox API
docker compose exec n8n wget -qO- http://sandbox-api:8080/healthz

# the sandbox runner registered with the API
docker compose logs sandbox-api | grep -i runner
```

### 7. First login

Open <http://localhost:5678>. On the first visit, n8n takes you through these steps:

1. **Create the owner account.** Enter an email address, name and password. The owner is the instance's administrator, and the account is stored in the `n8n-data` volume. There is no default login, so the first person to open the page becomes the owner. Do this right after starting the stack.
2. **Tell n8n about your company.** A short questionnaire asks about your company, your role and how you plan to use n8n. n8n uses the answers to tailor its suggestions.
3. **Get a free license key.** n8n offers to email you a free license key for the Community Edition, which unlocks some extra features. Enter your email address, then copy the key from the email. To activate it, go to **Settings → Usage and plan → Enter activation key**. You can also request the key later from the same page.

Your instance is still installed locally if you register for the key, but this step does send your email address to n8n.

## Day-to-day operations

```bash
docker compose logs -f n8n          # follow the logs of one service
docker compose restart n8n          # restart one service
docker compose down                 # stop everything (data is kept)
docker compose config               # check compose.yml together with .env
```

### Upgrading

1. Read the release notes for the new n8n and sandbox versions.
2. Back up the `n8n-data` volume (see [Data and backups](#data-and-backups)).
3. Update `N8N_VERSION` and/or `N8N_SANDBOX_VERSION` in `.env`.
4. Pull the new images and restart:

   ```bash
   docker compose pull
   docker compose up -d
   ```

`searxng` uses the `latest` tag, so `docker compose pull` also updates it.

### Data and backups

| Volume | Contents |
| --- | --- |
| `n8n-data` | Workflows, credentials, execution history, and n8n's encryption key |
| `sandbox-tls` | The sandbox mTLS certificates. These are recreated on startup, so you don't need to back them up. |

Compose prefixes volume names with the project name, which is the directory name by default, for example `rtb-n8n_n8n-data`. Run `docker volume ls` to see the exact names.

> **Warning:** The encryption key for saved credentials is stored inside `n8n-data`. If you lose the volume, you lose every stored credential. Never run `docker compose down -v` unless you mean to delete all your data.

## Security notes

- **Only port 5678 should face the internet.** Never publish ports for `sandbox-api` (8080/9090), `sandbox-runner-1` (it runs privileged Docker-in-Docker), `runners` (it runs user code), or `searxng`.
- **Use HTTPS in production.** n8n serves plain HTTP on port 5678. On a public server, put a reverse proxy with TLS in front of it, such as Caddy, Traefik or nginx.
- **Don't reuse the example values.** Always run `generate-secrets.sh`. `N8N_SANDBOX_SERVICE_API_KEY` must match one of the values in `SANDBOX_API_KEYS`; the script sets both to the same value.

## Configuration files

| File | Purpose |
| --- | --- |
| `compose.yml` | Service definitions |
| `example.env` | Template for `.env`, with comments for each variable |
| `generate-secrets.sh` | Generates the secrets in `.env` |
| `searxng-settings.yml` | SearXNG settings. The `json` format must stay enabled, because n8n requests search results as JSON. |

To add n8n settings, add them to `.env`: the n8n container loads the whole file. See the [n8n environment variable reference](https://docs.n8n.io/hosting/configuration/environment-variables/).

## Troubleshooting

- **`sandbox-api` never becomes healthy.** Check `docker compose logs sandbox-certs sandbox-api`. A common cause is `N8N_SANDBOX_VERSION` still being set to `change-me-…` or to a version that doesn't exist.
- **The runner doesn't register.** Check `docker compose logs sandbox-runner-1`. The runner needs privileged mode. Also check that `SANDBOX_API_RUNNER_REGISTRATION_TOKEN` and `SANDBOX_API_RUNNER_API_KEY` are set in `.env`.
- **Code nodes fail.** Check `docker compose logs runners`. `N8N_RUNNERS_AUTH_TOKEN` must be the same for n8n and the runners, which is the case when both read it from `.env`.

## References

- n8n Docker Compose install guide: <https://docs.n8n.io/deploy/host-n8n/install-options/install-using-docker-compose>. These instructions may change, so check the guide when something doesn't match.
- Upstream compose file history: <https://github.com/n8n-io/n8n/commits/master/docker/get-n8n-compose.yml>
