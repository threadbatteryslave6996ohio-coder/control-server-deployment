# control-server-deployment

This repository contains the control-server side of the deployment.

## What this sets up

- Tailscale on the control-server host
- Prometheus in Docker for node exporter scraping
- Loki in Docker for log ingestion
- Optional Grafana in Docker for dashboards
- Splunk Enterprise in Docker for log search and HEC ingestion
- Nginx reverse proxy with structured access logging

Managed hosts are configured separately with the client-side playbook. This repo only provides the central services that run on the control server.

## Layout

- `Makefile` - convenience commands for the control-server stack
- `docker-compose.yml` - Prometheus, Loki, Splunk, and optional Grafana
- `prometheus/prometheus.yml` - Prometheus scrape configuration
- `prometheus/targets/managed-hosts.yml.example` - example scrape targets for managed hosts
- `loki/loki-config.yaml` - Loki single-node config
- `grafana/provisioning/datasources/datasources.yml` - Grafana datasource provisioning
- `nginx/nginx.conf` - path routing and JSON access-log configuration
- `.env.example` - optional environment overrides for Grafana and Splunk

## Prerequisites

- Docker Engine and Docker Compose plugin on the control-server host
- A working Tailscale installation on the control-server host
- Managed hosts already running `node_exporter` on port `9100`
- A Splunk admin password and HEC token for the local container

## Recommended settings

- Keep the control-server services reachable only over Tailscale or a locked-down host firewall.
- Use `15d` Prometheus retention unless you have a clear storage target that justifies more or less history.
- Use `30d` Loki retention for a small control-server deployment, then adjust once you know your log volume.
- Leave Grafana disabled unless you actually need dashboards; it is optional for the core monitoring stack.
- Keep Loki unauthenticated only when it is private to the tailnet or otherwise access-controlled.
- Keep Splunk reachable only through the proxy. Neither its web UI nor its HEC publishes a host port; see "Single ingress".

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

   The `.env.example` file covers Grafana and Splunk credentials. Adjust `prometheus/prometheus.yml` or `loki/loki-config.yaml` directly if you want to change retention or scrape behavior.

## Single ingress

**The proxy is the only container that publishes a host port.** Every HTTP
service behind it is addressed by a service name in the path and routed by
nginx. Prometheus, Loki, Grafana, and Splunk are reachable only on the
internal Compose network — none of them publish ports of their own.

- Prometheus: `http://<proxy-host>/prometheus/`
- Loki API: `http://<proxy-host>/loki/api/v1/...`
- Loki readiness: `http://<proxy-host>/loki/ready`
- Grafana: `http://<proxy-host>/grafana/` when enabled
- Splunk Web: `http://<proxy-host>/splunk/`
- Splunk HEC: `http://<proxy-host>/services/collector`

Adding a service means adding a container with no `ports:` entry, a `location`
block, and an entry in the `$service_name` map. It does not mean opening
another host port.

### Why the HEC route is not under /splunk/

`/services/collector` sits at the root rather than under `/splunk/` because
Fluent Bit's `out_splunk` plugin hardcodes that request path and offers no
option to prefix it. Routing on Splunk's own API path is what keeps ingest on
the single ingress port. The alternative — the generic `http` output plugin,
which does accept a `uri` — would mean hand-building the HEC event envelope in
a Lua filter, which is more to maintain than one oddly-shaped location block.

### No TLS between services

The stack runs inside a private Tailscale network, so nothing here terminates
TLS or verifies certificates. Splunk's HEC ships with SSL enabled by default;
`SPLUNK_HEC_SSL=False` in the Compose file turns it off, because that listener
is only ever reached from nginx over the internal Compose network. Agents talk
plain HTTP to the proxy, and Tailscale provides transport encryption.

If this stack is ever exposed beyond a trusted network, that assumption breaks
and TLS has to be terminated at the proxy.

### Splunk index provisioning

Indexes are declared in `splunk/default.yml`, which is mounted at
`/tmp/defaults/default.yml` and applied by the image's entrypoint on every
start. Do not create indexes by hand with `splunk add index` — that state is
not reproducible and will not survive a rebuild.

This matters because the two halves of an index live in different places:

| | Path | Persistence |
| --- | --- | --- |
| Index data | `/opt/splunk/var` | `splunk-data` named volume — survives |
| Index definitions | `/opt/splunk/etc` | anonymous volume — **can be dropped** |

A HEC push to an index that does not exist still returns
`{"text":"Success","code":0}` while the event is silently discarded. So a lost
definition looks exactly like a working pipeline until you go looking for the
data. Declaring indexes in `default.yml` makes them reappear on every container
start regardless of what happened to `/opt/splunk/etc`.

Adding an index means adding an entry to `splunk/default.yml` and restarting
the container.

### Bind address

The proxy binds to `0.0.0.0:80` by default, which is intentional on a private
tailnet. To restrict it to Tailscale only, set `PROXY_BIND_ADDRESS` in `.env`
to the control server's Tailscale IPv4 address and set `GRAFANA_ROOT_URL` to
match:

```dotenv
PROXY_BIND_ADDRESS=100.64.0.10
PROXY_PORT=80
GRAFANA_ROOT_URL=http://100.64.0.10/grafana/
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
- Confirm Splunk Web loads at `/splunk/` and HEC accepts a POST at `/services/collector`, both on the proxy port.
- Confirm Tailscale is active on the control-server host.
- Confirm Prometheus retention and Loki retention match the storage policy you want before putting the box into service.

## Notes

- Splunk is deployed as a local container in this stack.
- This repo does not install `tailscale`, `auditd`, `osquery`, `fluent-bit`, or `docker` on managed hosts.
- The Prometheus and Loki data directories are persisted in Docker volumes.
