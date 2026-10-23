#!/usr/bin/env bash
set -euo pipefail

umask 077

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
template_file="$script_dir/example.env"
env_file="${1:-$script_dir/.env}"

if [[ ! -f "$template_file" ]]; then
    printf 'Template not found: %s\n' "$template_file" >&2
    exit 1
fi

if [[ -e "$env_file" && ! -f "$env_file" ]]; then
    printf 'Environment path is not a regular file: %s\n' "$env_file" >&2
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    printf 'openssl is required to generate secrets.\n' >&2
    exit 1
fi

source_file="$env_file"
if [[ ! -f "$source_file" ]]; then
    source_file="$template_file"
fi

runner_auth="$(openssl rand -hex 32)"
api_key="$(openssl rand -hex 32)"
runner_registration_token="$(openssl rand -hex 32)"
runner_api_key="$(openssl rand -hex 32)"
searxng_secret="$(openssl rand -hex 32)"

tmp_file="$(mktemp "${env_file}.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

awk \
    -v runner_auth="$runner_auth" \
    -v api_key="$api_key" \
    -v runner_registration_token="$runner_registration_token" \
    -v runner_api_key="$runner_api_key" \
    -v searxng_secret="$searxng_secret" '
    BEGIN {
        values["N8N_RUNNERS_AUTH_TOKEN"] = runner_auth
        values["SANDBOX_API_KEYS"] = api_key
        values["N8N_SANDBOX_SERVICE_API_KEY"] = api_key
        values["SANDBOX_API_RUNNER_REGISTRATION_TOKEN"] = runner_registration_token
        values["SANDBOX_API_RUNNER_API_KEY"] = runner_api_key
        values["SEARXNG_SECRET"] = searxng_secret
    }
    {
        equals = index($0, "=")
        if (equals > 0) {
            key = substr($0, 1, equals - 1)
            if (key in values) {
                print key "=" values[key]
                seen[key] = 1
                next
            }
        }
        print
    }
    END {
        for (key in values) {
            if (!(key in seen)) {
                print key "=" values[key]
            }
        }
    }
' "$source_file" > "$tmp_file"

chmod 600 "$tmp_file"
mv -- "$tmp_file" "$env_file"
printf 'Generated secrets in %s\n' "$env_file"