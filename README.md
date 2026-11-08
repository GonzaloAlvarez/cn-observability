# cn-observability

LAN-side observability stack for `kaiser.lan`. Mirrors the VPS-side stack in [cn-root-docker](https://github.com/GonzaloAlvarez/cn-root-docker) but without any tailnet wiring.

| Service | Host port | URL |
|---|---|---|
| `prometheus` | 127.0.0.1:9090 | `https://prometheus.kaiser.lan` |
| `grafana` | 127.0.0.1:3000 | `https://grafana.kaiser.lan` |
| `loki` | 127.0.0.1:3100 | `https://loki.kaiser.lan` |
| `alertmanager` | 127.0.0.1:9093 | `https://alertmanager.kaiser.lan` |
| `promtail` | — (docker.sock + journald) | — |
| `node-exporter` | 127.0.0.1:9100 (host net) | — |
| `portainer` | 127.0.0.1:9000 | `https://portainer.kaiser.lan` |

Routing + TLS is handled by [cn-home](https://github.com/GonzaloAlvarez/cn-home) on the same host. The contract is just the host port mapping above; this repo doesn't ship a Traefik.

## Deploy

kaiser's `.env` is Kauket-installed — secret `kaiser.cn_observability_env`, destination `/home/gonzalo/dev/cn-observability/.env` (0600). Nothing is hand-edited on the host and nothing is copied from a workstation checkout. From the workstation:

```sh
cd ../cn-home
./deploy --with-observability   # rsync tracked files; on kaiser: kauket get + ./setup.sh (render) + compose up
```

Standalone on the host (first install, or without cn-home): `kauket get kaiser.cn_observability_env`, `./setup.sh` (fetches the root CA, renders the Alertmanager/Promtail/SNMP templates), `docker compose -p cn-observability up -d`. On a brand-new host `kauket request kaiser.cn_observability_env` first and approve it from the Mac.

To change a value: `kauket get kaiser.cn_observability_env --stdout > <file outside git>` on the Mac, edit, `kauket add kaiser.cn_observability_env <file> --force`, redeploy. `kauket get` refuses a destination that was edited in place — fix the store, not the host. A refreshed `.env` recreates every service that reads it on the next `up -d` (today only Grafana reads the OIDC pair; the rest are rendered into files).

### Grafana SSO: "The client identifier (client_id) is missing or invalid"

Authentik shows this when the pair in `.env` (`AUTHENTIK_GRAFANA_CLIENT_ID` / `_SECRET`) is not the `grafana` provider's current pair. The same provider serves the VPS Grafana (`vps.cn_root_docker_env`), so the two secrets must carry identical values. Check without logging in:

```sh
u=$(curl -sk -o /dev/null -w '%{redirect_url}' https://grafana.kaiser.lan/login/generic_oauth)
curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' "$u"   # 302 → /flows/-/default/authentication/ is healthy; 400 is the drift
```

Fix: take the pair from the provider (`GET /api/v3/providers/oauth2/?name=grafana` on neptune) or from `vps.cn_root_docker_env`, update `kaiser.cn_observability_env` as above, redeploy. History: this recurred three times in 2026 because the deploy used to scp a stale workstation `.env` over the host copy; Kauket ownership (2026-11-07) removed that path.

## Layout

```
cn-observability/
├── docker-compose.yml
├── setup.sh
├── .env.example
├── certs/root_ca.crt              # fetched by setup.sh (gitignored)
└── config/
    ├── prometheus/{prometheus.yml,alerts.yml}
    ├── grafana/provisioning/{datasources/,dashboards/}
    ├── loki/loki.yml
    ├── promtail/promtail.yml.tmpl     # rendered → promtail.yml
    └── alertmanager/alertmanager.yml.tmpl
```

## What's NOT here (vs cn-root-docker)

Stripped because they're tailnet-specific or duplicated by other repos:

- `traefik-public` / `traefik-lab` — cn-home owns LAN ingress
- `ts-infra` + the `service:ts-infra` network mode — no tailscale on this host
- `headscale`, `coredns`, `consul` — tailnet plane
- `glance` — cn-home's Dashy is the homepage now
- `ts-infra-watchdog`, `watchtower` — revisit during the legacy-stack migration

## Grafana — adding a dashboard

UI-edit → export JSON → drop in `config/grafana/provisioning/dashboards/<name>.json` → commit + push → `ssh kaiser 'cd ~/dev/cn-observability && docker compose -p cn-observability restart grafana'`. The `dashboards.yml` provider auto-discovers any `*.json` on a 30-second loop.

Two dashboards are generated elsewhere and copied in: `cerberus-overview.json` and `frigate.json` come from `cn-nvr/grafana/build-dashboards.py` (`dist/cerberus-overview.json`, `dist/frigate-lan.json`). Their data arrives through cn-nvr's kaiser-only metrics entrypoint (`10.0.0.230:9100`, jobs `cerberus-node` + `frigate` in `prometheus.yml`); `CerberusLanScrapeDown` in `alerts.yml` watches that path, while the VPS plane owns the cn-nvr alerts themselves.

## License

GNU GPL v3 © 2026 Gonzalo Alvarez
