#!/bin/bash
# cn-observability/setup.sh — same shape as cn-home/setup.sh.
#   1. Interactive .env generation from .env.example.
#   2. Fetch step-ca root CA over plain HTTP.
#   3. Render Alertmanager + Promtail templates with envsubst.

set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  > .env
  while IFS= read -r line; do
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# || ! "$line" =~ = ]]; then
      echo "$line" >> .env
      continue
    fi
    varname="${line%%=*}"
    default="${line#*=}"
    if [[ "$varname" == *PASSWORD* || "$varname" == *TOKEN* || "$varname" == *SECRET* ]]; then
      read -rsp "${varname}: " value
      echo
      echo "${varname}=${value}" >> .env
    elif [[ -n "$default" ]]; then
      read -r -p "${varname} [${default}]: " value
      echo "${varname}=${value:-$default}" >> .env
    else
      read -r -p "${varname}: " value
      echo "${varname}=${value}" >> .env
    fi
  done < .env.example
  echo ""
fi

set -o allexport
# shellcheck disable=SC1091
source .env
set +o allexport

mkdir -p certs config/alertmanager config/promtail

echo "Fetching step-ca root CA from http://${PKI_IP}/cert/ca.crt ..."
if curl -sfL -o certs/root_ca.crt "http://${PKI_IP}/cert/ca.crt"; then
  echo "  → certs/root_ca.crt ($(wc -c < certs/root_ca.crt) bytes)"
else
  echo "  WARNING: could not fetch root CA — observability stack will still"
  echo "  start, but you'll need certs/root_ca.crt if you ever add an"
  echo "  external scrape target served by step-ca."
fi

if command -v envsubst >/dev/null; then
  envsubst '${SMTP_HOST} ${SMTP_PORT} ${SMTP_FROM} ${SMTP_USERNAME} ${SMTP_PASSWORD} ${ALERT_EMAIL}' \
    < config/alertmanager/alertmanager.yml.tmpl > config/alertmanager/alertmanager.yml
  echo "  → config/alertmanager/alertmanager.yml rendered"

  envsubst '${LAN_DOMAIN}' \
    < config/promtail/promtail.yml.tmpl > config/promtail/promtail.yml
  echo "  → config/promtail/promtail.yml rendered"
else
  echo "  WARNING: envsubst not found; install gettext."
fi

echo ""
echo "Setup complete. Bring it up with:"
echo "  docker compose -p cn-observability up -d"
echo "Or let cn-home/deploy --with-observability handle it."
