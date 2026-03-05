# MongoDB Deploy UI

A lightweight web-based frontend for **mongo_terraform_ansible** that lets you:

- Select a target platform (AWS, GCP, Azure, or local Docker)
- Configure MongoDB environments via a guided form (sharded clusters, replica sets, PMM, PBM)
- Pick available Docker image versions and Percona package releases from live lookups
- Deploy, stop, restart, and destroy environments with real-time terminal output

---

## Requirements

- Python 3.10+
- `pip` (Python package manager)

Optional (needed to actually run deployments):

- [Terraform](https://developer.hashicorp.com/terraform/downloads) ≥ 1.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) (for AWS / GCP / Azure deployments)
- Cloud CLI credentials configured in your environment (AWS CLI, `gcloud`, `az`, etc.)

---

## Quick Start

```bash
# From the repository root
cd ui
pip install -r requirements.txt
python app.py
```

To enable debug/hot-reload mode (development only):

```bash
FLASK_DEBUG=1 python app.py
```

Then open **http://127.0.0.1:5000** in your browser.

---

## How it works

1. **Platform selection** – choose AWS, GCP, Azure, or Docker.
2. **Configuration wizard** – fill in cluster topology, images/packages, credentials, and networking.
   - Image tags are fetched live from Docker Hub for `percona/percona-server-mongodb`,
     `percona/percona-backup-mongodb`, `percona/pmm-server`, and `percona/pmm-client`.
   - Percona package release identifiers (e.g. `psmdb-80`) are listed for Ansible-based deployments.
3. **Save** – the UI writes a `<env_id>.tfvars` file inside the corresponding `terraform/<platform>/`
   directory and records the environment in `ui/environments.json`.
4. **Deploy** – runs `terraform init && terraform apply` (and Ansible for cloud platforms)
   in a background thread. Output is streamed live to the browser.
5. **Stop / Restart / Destroy** – available via action buttons on the environment detail page.

---

## File structure

```
ui/
├── app.py               Flask application
├── requirements.txt     Python dependencies
├── environments.json    Runtime state (auto-created)
├── jobs/                Background job logs (auto-created)
├── templates/
│   ├── base.html
│   ├── index.html           Environment list
│   ├── new_environment.html Platform picker
│   ├── configure.html       Configuration wizard
│   └── environment.html     Environment detail & actions
└── static/
    ├── style.css
    └── app.js
```

---

## Security note

This tool is intended for **local use only** (it binds to `127.0.0.1:5000` by default).
Do not expose it to the public internet without adding proper authentication.
