#!/usr/bin/env bash
# GitHub-hosted-only disposable ERPNext v16 smoke test. Never run against
# CCPC DEVELOPMENT or PRODUCTION, local Docker, or business data.
set -Eeuo pipefail

if [[ "${GITHUB_ACTIONS:-}" != "true" || "${RUNNER_ENVIRONMENT:-}" != "github-hosted" || -z "${GITHUB_RUN_ID:-}" ]]; then
  echo "Refusing to run outside a GitHub-hosted Actions runner" >&2
  exit 2
fi

cd "$(dirname "$0")/.."
project="ccpc-public-${GITHUB_RUN_ID}"
compose=(docker compose --project-name "$project" --file ci/frappe-smoke.compose.yaml)

cleanup() {
  status=$?
  trap - EXIT
  if (( status != 0 )); then
    echo "::error::Disposable Frappe/ERPNext smoke failed (exit $status)"
    "${compose[@]}" ps || true
    "${compose[@]}" logs --tail 35 db redis-cache redis-queue || true
  fi
  if ! "${compose[@]}" down --volumes --remove-orphans; then
    echo "::error::Disposable CI stack cleanup failed"
    if (( status == 0 )); then status=1; fi
  fi
  exit "$status"
}
trap cleanup EXIT

echo "Validating isolated public-only Docker Compose configuration"
"${compose[@]}" config --quiet

available_kib=$(df -Pk . | awk 'NR==2 {print $4}')
if [[ ! "$available_kib" =~ ^[0-9]+$ ]] || (( available_kib < 6 * 1024 * 1024 )); then
  echo "::error::Fewer than 6 GiB of runner disk space available; no destructive runner pruning attempted" >&2
  exit 1
fi
echo "Runner disk headroom: $((available_kib / 1024 / 1024)) GiB"

echo "Pulling public pinned ERPNext v16 and supporting images"
"${compose[@]}" pull db redis-cache redis-queue configurator backend

echo "Starting disposable MariaDB and Redis services"
"${compose[@]}" up --detach --wait db redis-cache redis-queue

echo "Generating Frappe bench shared configuration"
"${compose[@]}" run --rm --no-deps configurator

echo "Installing a synthetic ERPNext v16 site in disposable volumes"
"${compose[@]}" run --rm --no-deps backend bash -c '
  set -euo pipefail
  bench new-site ci.localhost \
    --mariadb-user-host-login-scope="%" \
    --admin-password="public-ci-only-not-a-secret" \
    --db-root-username=root \
    --db-root-password="public-ci-only-not-a-secret" \
    --install-app erpnext \
    --set-default ci.localhost
'

echo "Checking installed public Frappe and ERPNext applications"
apps_output=$("${compose[@]}" run --rm --no-deps backend bench --site ci.localhost list-apps --format text)
printf '%s\n' "$apps_output"
grep -Eq '(^|[[:space:]])frappe([[:space:]]|$)' <<< "$apps_output"
grep -Eq '(^|[[:space:]])erpnext([[:space:]]|$)' <<< "$apps_output"

echo "Reading only the disposable database name from synthetic site configuration"
db_name=$("${compose[@]}" run --rm --no-deps backend python3 -c '
import json
with open("sites/ci.localhost/site_config.json", encoding="utf-8") as f:
    print(json.load(f)["db_name"])
')
if [[ ! "$db_name" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "::error::Unexpected CI database name" >&2
  exit 1
fi

echo "Checking real ERPNext DocType tables through disposable MariaDB"
sql_result=$("${compose[@]}" exec -T db mariadb \
  --user=root \
  --password=public-ci-only-not-a-secret \
  --database="$db_name" \
  --batch --skip-column-names \
  --execute="SELECT name FROM tabDocType WHERE name IN ('Stock Entry', 'Sales Invoice') ORDER BY name;")
printf '%s\n' "$sql_result"
if [[ "$sql_result" != $'Sales Invoice\nStock Entry' ]]; then
  echo "::error::ERPNext Stock Entry / Sales Invoice DocTypes missing or SQL result unexpected" >&2
  exit 1
fi

echo "PASS: public ERPNext v16 site and real MariaDB DocTypes verified"
