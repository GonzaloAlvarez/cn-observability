#!/bin/bash
# cn-observability/setup.sh — same shape as cn-home/setup.sh.
#
# Flags:
#   --core   Harvest SMTP_HOST/PORT/FROM/USERNAME/PASSWORD/ALERT_EMAIL from
#            hs.gn.al:/opt/cloudnet/.env so kaiser Alertmanager emails the
#            same destination as the VPS one. Mirrors cn-fitness --core.
#
#   1. Interactive .env generation from .env.example.
#   2. (--core) harvest SMTP/ALERT_EMAIL from hs.gn.al.
#   3. Fetch step-ca root CA over plain HTTP.
#   4. Render Alertmanager + Promtail templates with envsubst.

set -euo pipefail
cd "$(dirname "$0")"

CORE_ONLY=0
case "${1:-}" in
  --core) CORE_ONLY=1 ;;
  -h|--help)
    sed -n '/^#!/d; /^[^#]/q; s/^# \{0,1\}//p' "$0"
    exit 0
    ;;
  "") ;;
  *)
    echo "unknown argument: $1 (try --help)" >&2
    exit 2
    ;;
esac

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

if (( CORE_ONLY == 1 )); then
  echo "Harvesting SMTP/ALERT_EMAIL from hs.gn.al:/opt/cloudnet/.env ..."
  SSH_OPTS=(-o BatchMode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -l gonzalo)
  for p in ~/.ssh/main_private_key.pem ~/.ssh/gonzalo_main_private_key.pem; do
    [[ -f "$p" ]] && { SSH_OPTS+=(-i "$p"); break; }
  done
  tmp=$(mktemp)
  trap "rm -f '$tmp'" EXIT
  if ! ssh "${SSH_OPTS[@]}" hs.gn.al \
       "grep -E '^(SMTP_HOST|SMTP_PORT|SMTP_FROM|SMTP_USERNAME|SMTP_PASSWORD|ALERT_EMAIL)=' /opt/cloudnet/.env" \
       > "$tmp"; then
    echo "  ERROR: ssh hs.gn.al failed — is the VPS up and your key authorized?" >&2
    exit 1
  fi
  [[ -s "$tmp" ]] || { echo "  ERROR: no matching keys found on hs.gn.al" >&2; exit 1; }
  while IFS='=' read -r k v; do
    [[ -z "$k" ]] && continue
    esc=$(printf '%s\n' "$v" | sed -e 's/[\/&]/\\&/g')
    if grep -qE "^${k}=" .env; then
      sed -i.bak "s/^${k}=.*/${k}=${esc}/" .env && rm -f .env.bak
    else
      printf '%s=%s\n' "$k" "$v" >> .env
    fi
    echo "  → ${k}"
  done < "$tmp"
fi

set -o allexport
# shellcheck disable=SC1091
source .env
set +o allexport

mkdir -p certs config/alertmanager config/promtail config/snmp-exporter

echo "Fetching step-ca root CA from http://${PKI_IP}/cert/ca.crt ..."
if curl -sfL -o certs/root_ca.crt "http://${PKI_IP}/cert/ca.crt"; then
  echo "  → certs/root_ca.crt ($(wc -c < certs/root_ca.crt) bytes)"
else
  echo "  WARNING: could not fetch root CA — observability stack will still"
  echo "  start, but you'll need certs/root_ca.crt if you ever add an"
  echo "  external scrape target served by step-ca."
fi

# Alertmanager template uses ${ALERT_EMAIL_BLOCK} — render the email block
# only when ALERT_EMAIL is non-empty. Otherwise leave it blank so the
# `email` receiver has zero email_configs and Alertmanager no-ops.
if [ -n "${ALERT_EMAIL:-}" ]; then
  export ALERT_EMAIL_BLOCK="      - to: '${ALERT_EMAIL}'
        send_resolved: true"
else
  export ALERT_EMAIL_BLOCK=""
fi

if command -v envsubst >/dev/null; then
  envsubst '${SMTP_HOST} ${SMTP_PORT} ${SMTP_FROM} ${SMTP_USERNAME} ${SMTP_PASSWORD} ${ALERT_EMAIL_BLOCK}' \
    < config/alertmanager/alertmanager.yml.tmpl > config/alertmanager/alertmanager.yml
  echo "  → config/alertmanager/alertmanager.yml rendered"

  envsubst '${LAN_DOMAIN}' \
    < config/promtail/promtail.yml.tmpl > config/promtail/promtail.yml
  echo "  → config/promtail/promtail.yml rendered"

  # snmp_exporter doesn't honor env var interpolation — bake both community
  # strings in. raidnas is required; pfsense is optional (auth block stays
  # in the rendered file but with an empty community → snmp_exporter just
  # returns auth errors for pfsense-snmp, which surfaces as DOWN in
  # Prometheus until the operator wires it up).
  if [ -n "${SNMP_RAIDNAS_COMMUNITY:-}" ]; then
    envsubst '${SNMP_RAIDNAS_COMMUNITY} ${SNMP_PFSENSE_COMMUNITY}' \
      < config/snmp-exporter/snmp.yml.tmpl > config/snmp-exporter/snmp.yml
    echo "  → config/snmp-exporter/snmp.yml rendered"
  fi
else
  echo "  WARNING: envsubst not found; install gettext."
fi

echo ""
echo "Setup complete. Bring it up with:"
echo "  docker compose -p cn-observability up -d"
echo "Or let cn-home/deploy --with-observability handle it."
