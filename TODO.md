# TODO

- [x] Add CI/CD tooling to this repo, for example:
  - Validate `compose.yml` with `docker compose config` (against `example.env`)
  - Lint YAML (`compose.yml`, `searxng-settings.yml`), e.g. with yamllint
  - Lint shell scripts (`generate-secrets.sh`), e.g. with shellcheck
