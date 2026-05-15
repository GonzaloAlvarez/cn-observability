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

```sh
./setup.sh                                 # interactive .env + fetch root CA + render templates
docker compose -p cn-observability up -d   # or let cn-home/deploy --with-observability handle it
```

Or, from the workstation, deploy both with one command:

```sh
cd ../cn-home
./deploy --with-observability
```

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

## License

GNU GPL v3 © 2026 Gonzalo Alvarez
