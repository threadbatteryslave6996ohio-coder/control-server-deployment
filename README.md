# control-server-deployment

This repository contains the control-server side of the deployment.

## What this sets up

- Tailscale on the control-server host
- Prometheus in Docker for node exporter scraping
- Loki in Docker for log ingestion
- Optional Grafana in Docker for dashboards
- Nginx reverse proxy with structured access logging

Managed hosts are configured separately with the client-side playbook. This repo only provides the central services that run on the control server.

## Layout

- `Makefile` - convenience commands for the control-server stack
- `docker-compose.yml` - Prometheus, Loki, and optional Grafana
- `prometheus/prometheus.yml` - Prometheus scrape configuration
- `prometheus/targets/managed-hosts.yml.example` - example scrape targets for managed hosts
- `loki/loki-config.yaml` - Loki single-node config
- `grafana/provisioning/datasources/datasources.yml` - Grafana datasource provisioning
- `nginx/nginx.conf` - path routing and JSON access-log configuration
- `.env.example` - optional environment overrides for Grafana

## Prerequisites

- Docker Engine and Docker Compose plugin on the control-server host
- A working Tailscale installation on the control-server host
- Managed hosts already running `node_exporter` on port `9100`
- Optional: a pre-existing Splunk HEC endpoint for security logs

## Recommended settings

- Keep the control-server services reachable only over Tailscale or a locked-down host firewall.
- Use `15d` Prometheus retention unless you have a clear storage target that justifies more or less history.
- Use `30d` Loki retention for a small control-server deployment, then adjust once you know your log volume.
- Leave Grafana disabled unless you actually need dashboards; it is optional for the core monitoring stack.
- Keep Loki unauthenticated only when it is private to the tailnet or otherwise access-controlled.

## Quick start

1. Install Docker on the control-server host.

   ```bash
   sudo apt install docker.io docker-compose-plugin
   sudo systemctl enable --now docker
   ```

2. Install and join Tailscale on the host.

   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up --authkey=YOUR_KEY --hostname=control-server
   ```

3. Add managed-host scrape targets.

   Copy `prometheus/targets/managed-hosts.yml.example` to a new `*.yml` file and replace the example hostnames with your managed-host Tailscale DNS names or tailnet IPs.

4. Start the stack.

   ```bash
   make up
   ```

5. Optional: start Grafana.

   ```bash
   make up-grafana
   ```

   If you want to override the default Grafana credentials, copy `.env.example` to `.env` and change the values before starting the stack. Set `GRAFANA_ROOT_URL` to the public proxy URL when accessing Grafana from another host.

   The `.env.example` file only covers Grafana credentials. Adjust `prometheus/prometheus.yml` or `loki/loki-config.yaml` directly if you want to change retention or scrape behavior.

## Reverse proxy and service endpoints

Only the reverse proxy publishes a host port. Prometheus, Loki, and Grafana are reachable only on the internal Compose network.

- Prometheus: `http://<proxy-host>:8080/prometheus/`
- Loki API: `http://<proxy-host>:8080/loki/api/v1/...`
- Loki readiness: `http://<proxy-host>:8080/loki/ready`
- Grafana: `http://<proxy-host>:8080/grafana/` when enabled

The proxy binds to `127.0.0.1:8080` by default. To expose it only on Tailscale, set `PROXY_BIND_ADDRESS` in `.env` to the control server's Tailscale IPv4 address, set `GRAFANA_ROOT_URL` to the corresponding URL, and restart the stack. Do not set the bind address to `0.0.0.0` unless the host firewall restricts access appropriately.

Example:

```dotenv
PROXY_BIND_ADDRESS=100.64.0.10
PROXY_PORT=8080
GRAFANA_ROOT_URL=http://100.64.0.10:8080/grafana/
```

## Access logs

Every proxy request is logged as JSON with its timestamp, client IP, destination service, method, path, status, response size, latency, upstream latency, and user agent. Query strings are intentionally omitted to avoid recording tokens or other secrets.

Follow the logs through Docker:

```bash
make access-logs
```

Docker retains and rotates the proxy logs at 10 MB per file with five files retained, preventing an unbounded access-log file.

## Prometheus target format

Use one file per group of targets under `prometheus/targets/`:

```yaml
- targets:
    - host1.tailnet.example:9100
    - host2.tailnet.example:9100
  labels:
    env: managed
    role: node-exporter
```

Prometheus watches the target directory automatically, so adding or editing target files does not require a container restart.

## Makefile

Use `make init` on a fresh checkout to create a local `.env` file and seed `prometheus/targets/managed-hosts.yml` from the example file.

Common commands:

- `make init`
- `make up`
- `make up-grafana`
- `make down`
- `make restart`
- `make logs`
- `make access-logs`
- `make ps`
- `make validate`
- `make targets`

## Validation

- Confirm the Prometheus target list in the UI shows each managed host as `UP`.
- Confirm `/prometheus/` and `/loki/ready` are reachable through the proxy.
- Confirm Grafana can reach both Prometheus and Loki when the optional profile is enabled.
- Confirm Tailscale is active on the control-server host.
- Confirm Prometheus retention and Loki retention match the storage policy you want before putting the box into service.

## Notes

- Splunk HEC is external to this repo.
- This repo does not install `tailscale`, `auditd`, `osquery`, `fluent-bit`, or `docker` on managed hosts.
- The Prometheus and Loki data directories are persisted in Docker volumes.
