# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A self-hosted n8n deployment via Docker Compose, derived from n8n's official `get-n8n-compose.yml` (see https://docs.n8n.io/deploy/host-n8n/install-options/install-using-docker-compose). There is no application code, build, lint, or test suite — the repo is configuration: [compose.yml](compose.yml), [example.env](example.env), [generate-secrets.sh](generate-secrets.sh), and [searxng-settings.yml](searxng-settings.yml).

## Commands

```bash
cp example.env .env              # then set N8N_VERSION and N8N_SANDBOX_VERSION by hand
./generate-secrets.sh            # fills in all secrets in .env (optional arg: target env file path)
docker compose up -d
docker compose ps
docker compose config            # validate compose.yml + .env interpolation

# Verification
docker compose exec n8n wget -qO- http://sandbox-api:8080/healthz
docker compose logs sandbox-api | grep -i runner
curl -sf http://localhost:5678/healthz
```

## Architecture

Services in [compose.yml](compose.yml), all on the default Compose network and addressed by service name:

- **n8n** — main app; the only service with a published port (5678). Persists to the `n8n-data` volume.
- **runners** — external task runners executing Code-node user code. Connects to n8n's task broker at `n8n:5679`, authenticated with `N8N_RUNNERS_AUTH_TOKEN`. Uses the same `N8N_VERSION` tag as n8n.
- **Sandbox service** (three images sharing one `N8N_SANDBOX_VERSION`; they are only supported at matching versions):
  - **sandbox-certs** — one-shot init container that bootstraps mTLS certs into the `sandbox-tls` volume. `NUM_RUNNERS` and `--control-san-prefix sandbox-runner` determine which runner hostnames get certs.
  - **sandbox-api** — HTTP on 8080 (n8n talks to it, authenticated by `N8N_SANDBOX_SERVICE_API_KEY`, which must be one of `SANDBOX_API_KEYS`), gRPC on 9090 for runner registration.
  - **sandbox-runner-1** — privileged Docker-in-Docker runner that registers with sandbox-api over mTLS gRPC and spawns sandbox containers. Adding runners means a new `sandbox-runner-N` service *and* bumping `NUM_RUNNERS` in sandbox-certs.
- **searxng** — internal web-search backend for n8n's instance AI (`N8N_INSTANCE_AI_SEARXNG_URL`). Config mounted from [searxng-settings.yml](searxng-settings.yml); the `json` format must stay enabled for n8n to query it.

Startup order is enforced via `depends_on`: sandbox-certs (completed) → sandbox-api (healthy) → sandbox-runner-1 and n8n → runners.

Security invariants called out in compose comments: never publish ports for sandbox-api (8080/9090), sandbox-runner (privileged DinD), runners, or searxng.

## Env / secrets

- `.env` is gitignored; `example.env` is the committed template. Most services load `.env` wholesale via `env_file`, so new variables generally only need adding to `example.env` (and to `generate-secrets.sh` if they are secrets).
- `generate-secrets.sh` reads the existing `.env` if present (else `example.env`), replaces only the known secret keys with fresh `openssl rand -hex 32` values, and writes atomically with mode 600. Re-running it **rotates** every secret; it sets `SANDBOX_API_KEYS` and `N8N_SANDBOX_SERVICE_API_KEY` to the same value. To manage a new secret, add it to the `awk` `values` map.
