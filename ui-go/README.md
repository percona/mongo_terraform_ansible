# MongoDB Deploy UI (Go)

A portable, zero-dependency web frontend for **mongo_terraform_ansible** written in Go.
It is a complete rewrite of `../ui/` (Python/Flask) with the same feature set and no
Python runtime requirement.

---

## Requirements

- **Go 1.22+** (for `net/http` pattern-based routing with `{name}` params)

Optional (needed to actually run deployments):

- [Terraform](https://developer.hashicorp.com/terraform/downloads) ≥ 1.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) (for AWS / GCP / Azure deployments)
- [Docker](https://docs.docker.com/get-docker/) (for local Docker environments)
- Cloud CLI credentials configured in your environment (AWS CLI, `gcloud`, `az`, etc.)

---

## Quick Start

```bash
# From the repository root
cd ui-go
go run .
```

Or build a binary and run it from anywhere:

```bash
cd ui-go
go build -o mongodeploy .
./mongodeploy
```

Then open **http://127.0.0.1:5001** in your browser.

### Environment variables

| Variable     | Default            | Description                                  |
|--------------|--------------------|----------------------------------------------|
| `PORT`       | `5001`             | TCP port to listen on                        |
| `UI_HOST`    | `127.0.0.1`        | Bind address (use `0.0.0.0` for all interfaces) |
| `UI_BASE_DIR`| current directory  | Override the base directory (must contain `templates/` and `static/`) |

---

## What's new vs the Python version

| Feature | Python `ui/` | Go `ui-go/` |
|---------|-------------|------------|
| **Per-component instance types & disk sizes** | PMM only | All components (shard server, config server, mongos, arbiter, replica-set node) |
| **PMM disk type** | Not configurable in UI | Configurable |
| **Minio server configuration** | No UI form | Full form (image, ports, credentials, bucket, retention) |
| **LDAP server configuration** | No UI form | Full form (image, port, domain, admin password) |
| **Docker replica set images** | Name/counts only | Also psmdb/pbm/pmm-client images + flags |
| **Runtime** | Python 3.10 + pip | Single compiled binary, no runtime dependencies |
| **Port** | 5000 | 5001 |

---

## How it works

1. **Platform selection** – choose AWS, GCP, Azure, or Docker.
2. **Configuration wizard** – fill in cluster topology, images/packages, credentials,
   networking, and (for cloud platforms) per-component instance types and disk sizes.
   - Image tags are fetched live from Docker Hub on startup and cached for 5 minutes.
   - Percona package release identifiers (`psmdb-80`, …) are fetched from the Percona
     repository listing on startup.
3. **Save** – writes `<env_id>.tfvars` inside the corresponding `../terraform/<platform>/`
   directory and records the environment in `environments.json`.
4. **Deploy** – runs `terraform init && terraform apply` (and Ansible for cloud platforms)
   in a background goroutine. Output is streamed live via Server-Sent Events.
5. **Stop / Restart** – for Docker environments, uses `docker stop` / `docker restart`
   filtered by the environment prefix; for cloud environments, runs the Ansible
   `stop.yml` / `restart.yml` playbooks.
6. **Destroy** – runs `terraform destroy`. On success the environment is automatically
   removed from the inventory and the browser redirects to the environments list.

---

## File structure

```
ui-go/
├── main.go            Complete Go application (server, types, handlers, jobs, tfvars)
├── exec_helper.go     os/exec wrapper
├── go.mod             Go module (standard library only)
├── environments.json  Runtime state (auto-created)
├── jobs/              Background job logs (auto-created)
├── templates/
│   ├── layout.html         Base HTML layout
│   ├── index.html          Environment list
│   ├── new_environment.html Platform picker
│   ├── configure.html      Configuration wizard
│   └── environment.html    Environment detail & actions
└── static/
    ├── style.css
    └── app.js
```

---

## Security note

This tool is intended for **local use only** (it binds to `127.0.0.1:5001` by default).
Do not expose it to the public internet without adding proper authentication.
