#!/usr/bin/env python3
"""
Web-based frontend for mongo_terraform_ansible.
Allows users to configure, deploy, and manage MongoDB environments
across AWS, GCP, Azure, and Docker platforms.
"""

import json
import os
import re
import shlex
import subprocess
import threading
import time
import uuid
from pathlib import Path

import requests
from flask import Flask, Response, jsonify, redirect, render_template, request, url_for

app = Flask(__name__)

# Paths
BASE_DIR = Path(__file__).parent.parent
TERRAFORM_DIR = BASE_DIR / "terraform"
ANSIBLE_DIR = BASE_DIR / "ansible"
STATE_FILE = Path(__file__).parent / "environments.json"
JOBS_DIR = Path(__file__).parent / "jobs"
JOBS_DIR.mkdir(exist_ok=True)

PLATFORMS = ["aws", "gcp", "azure", "docker"]

_ENV_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{1,40}$")


def validate_env_id(env_id: str) -> bool:
    """Return True if env_id contains only safe characters for use in file paths."""
    return bool(_ENV_ID_RE.match(env_id))

# ──────────────────────────────────────────────────────────────────────────────
# State helpers
# ──────────────────────────────────────────────────────────────────────────────

def load_state() -> dict:
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}


def save_state(state: dict):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


# ──────────────────────────────────────────────────────────────────────────────
# Version / image helpers
# ──────────────────────────────────────────────────────────────────────────────

_version_cache: dict = {}
_CACHE_TTL = 300  # seconds


def _cache_get(key: str):
    entry = _version_cache.get(key)
    if entry and (time.time() - entry["ts"]) < _CACHE_TTL:
        return entry["data"]
    return None


def _cache_set(key: str, data):
    _version_cache[key] = {"ts": time.time(), "data": data}


def get_dockerhub_tags(namespace: str, repo: str, limit: int = 20) -> list[str]:
    """Return a list of Docker Hub image tags (most recent first)."""
    key = f"dh:{namespace}/{repo}"
    cached = _cache_get(key)
    if cached is not None:
        return cached
    try:
        url = f"https://hub.docker.com/v2/repositories/{namespace}/{repo}/tags/?page_size={limit}&ordering=last_updated"
        resp = requests.get(url, timeout=8)
        resp.raise_for_status()
        tags = [t["name"] for t in resp.json().get("results", [])]
    except Exception:
        tags = []
    _cache_set(key, tags)
    return tags


def get_psmdb_versions() -> list[str]:
    """Return known Percona Server for MongoDB release identifiers."""
    key = "psmdb_versions"
    cached = _cache_get(key)
    if cached is not None:
        return cached
    # Try fetching from Percona repository listing
    known = [
        "psmdb-80",
        "psmdb-70",
        "psmdb-60",
        "psmdb-50",
        "psmdb-44",
        "psmdb-42",
        "psmdb-40",
        "psmdb-36",
    ]
    try:
        resp = requests.get("https://repo.percona.com/percona/yum/release/", timeout=6)
        if resp.ok:
            found = re.findall(r"psmdb-\d+", resp.text)
            if found:
                known = sorted(set(found), reverse=True)
    except Exception:
        pass
    _cache_set(key, known)
    return known


def get_pmm_server_images() -> list[str]:
    tags = get_dockerhub_tags("percona", "pmm-server", 30)
    if not tags:
        tags = ["latest", "3", "2.42.0", "2.41.0", "2.40.0"]
    return tags


def get_psmdb_images() -> list[str]:
    tags = get_dockerhub_tags("percona", "percona-server-mongodb", 30)
    if not tags:
        tags = ["latest", "8.0", "7.0", "6.0"]
    return tags


def get_pbm_images() -> list[str]:
    tags = get_dockerhub_tags("percona", "percona-backup-mongodb", 20)
    if not tags:
        tags = ["latest", "2.4.0", "2.3.0"]
    return tags


def get_pmm_client_images() -> list[str]:
    tags = get_dockerhub_tags("percona", "pmm-client", 20)
    if not tags:
        tags = ["latest", "3.0.0", "2.42.0"]
    return tags


# ──────────────────────────────────────────────────────────────────────────────
# Terraform helpers
# ──────────────────────────────────────────────────────────────────────────────

def tfvars_path(env_id: str, platform: str) -> Path:
    return TERRAFORM_DIR / platform / f"{env_id}.tfvars"


def write_tfvars(env_id: str, platform: str, config: dict):
    """Write a terraform.tfvars file from the config dict."""
    tf_dir = TERRAFORM_DIR / platform
    tf_dir.mkdir(parents=True, exist_ok=True)
    path = tfvars_path(env_id, platform)

    lines = []

    def _write_val(v):
        if isinstance(v, bool):
            return str(v).lower()
        if isinstance(v, (int, float)):
            return str(v)
        return f'"{v}"'

    # prefix
    if "prefix" in config:
        lines.append(f'prefix = "{config["prefix"]}"')

    # platform-specific simple variables
    simple_vars = [
        "project_id", "region", "location", "subnet_cidr", "source_ranges",
        "my_ssh_user", "ssh_public_key_path", "default_key_pair",
        "enable_ssh_gateway", "ssh_gateway_name", "port_to_forward",
        "pmm_type", "pmm_volume_size", "pmm_port", "pmm_disk_type",
        "default_bucket_name", "backup_retention",
        "use_spot_instances", "data_disk_type", "subnet_count",
        "network_name",
    ]
    for var in simple_vars:
        if var in config:
            lines.append(f"{var} = {_write_val(config[var])}")

    # clusters (cloud)
    if "clusters" in config and config["clusters"]:
        lines.append("")
        lines.append("clusters = {")
        for cname, cval in config["clusters"].items():
            lines.append(f'  "{cname}" = {{')
            for k, v in cval.items():
                lines.append(f"    {k} = {_write_val(v)}")
            lines.append("  }")
        lines.append("}")

    # replsets (cloud)
    if "replsets" in config and config["replsets"]:
        lines.append("")
        lines.append("replsets = {}")
        if config["replsets"]:
            lines[-1] = "replsets = {"
            for rname, rval in config["replsets"].items():
                lines.append(f'  "{rname}" = {{')
                for k, v in rval.items():
                    lines.append(f"    {k} = {_write_val(v)}")
                lines.append("  }")
            lines.append("}")

    # docker-specific: pmm_servers, minio_servers, ldap_servers
    for section in ("pmm_servers", "minio_servers", "ldap_servers"):
        if section in config and config[section]:
            lines.append("")
            lines.append(f"{section} = {{")
            for sname, sval in config[section].items():
                lines.append(f'  "{sname}" = {{')
                for k, v in sval.items():
                    lines.append(f"    {k} = {_write_val(v)}")
                lines.append("  }")
            lines.append("}")

    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


# ──────────────────────────────────────────────────────────────────────────────
# Job / background process helpers
# ──────────────────────────────────────────────────────────────────────────────

def job_log_path(job_id: str) -> Path:
    return JOBS_DIR / f"{job_id}.log"


def job_status_path(job_id: str) -> Path:
    return JOBS_DIR / f"{job_id}.status"


def _run_job(job_id: str, cmd: list[str], cwd: str, env: dict | None = None):
    """Run a command in a thread, writing output to a log file."""
    log = job_log_path(job_id)
    status = job_status_path(job_id)
    status.write_text("running")
    full_env = {**os.environ, **(env or {})}
    try:
        with open(log, "w") as f:
            proc = subprocess.Popen(
                cmd,
                cwd=cwd,
                stdout=f,
                stderr=subprocess.STDOUT,
                env=full_env,
                text=True,
            )
            proc.wait()
        rc = proc.returncode
        status.write_text("success" if rc == 0 else f"failed:{rc}")
    except Exception as exc:
        with open(log, "a") as f:
            f.write(f"\nError: {exc}\n")
        status.write_text("error")


def start_job(cmd: list[str], cwd: str, env: dict | None = None) -> str:
    job_id = str(uuid.uuid4())
    t = threading.Thread(target=_run_job, args=(job_id, cmd, cwd, env), daemon=True)
    t.start()
    return job_id


# ──────────────────────────────────────────────────────────────────────────────
# Routes – pages
# ──────────────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    state = load_state()
    return render_template("index.html", environments=state, platforms=PLATFORMS)


@app.route("/new")
def new_environment():
    return render_template("new_environment.html", platforms=PLATFORMS)


@app.route("/configure/<platform>")
def configure(platform: str):
    if platform not in PLATFORMS:
        return redirect(url_for("index"))
    env_id = request.args.get("env_id", "")
    state = load_state()
    existing = state.get(env_id, {}) if env_id else {}
    psmdb_versions = get_psmdb_versions()
    pmm_images = get_pmm_server_images()
    psmdb_images = get_psmdb_images()
    pbm_images = get_pbm_images()
    pmm_client_images = get_pmm_client_images()
    return render_template(
        "configure.html",
        platform=platform,
        env_id=env_id,
        existing=existing,
        psmdb_versions=psmdb_versions,
        pmm_images=pmm_images,
        psmdb_images=psmdb_images,
        pbm_images=pbm_images,
        pmm_client_images=pmm_client_images,
    )


@app.route("/environment/<env_id>")
def environment(env_id: str):
    state = load_state()
    env = state.get(env_id)
    if not env:
        return redirect(url_for("index"))
    return render_template("environment.html", env_id=env_id, env=env)


# ──────────────────────────────────────────────────────────────────────────────
# Routes – API
# ──────────────────────────────────────────────────────────────────────────────

@app.route("/api/versions")
def api_versions():
    return jsonify(
        {
            "psmdb_versions": get_psmdb_versions(),
            "pmm_server_images": get_pmm_server_images(),
            "psmdb_images": get_psmdb_images(),
            "pbm_images": get_pbm_images(),
            "pmm_client_images": get_pmm_client_images(),
        }
    )


@app.route("/api/environment", methods=["POST"])
def save_environment():
    data = request.get_json(force=True)
    env_id = data.get("env_id") or str(uuid.uuid4())[:8]
    # Sanitize env_id to prevent path traversal
    if not validate_env_id(env_id):
        return jsonify({"error": "Invalid env_id: use only letters, digits, hyphens, and underscores (max 40 chars)"}), 400
    platform = data.get("platform")
    if platform not in PLATFORMS:
        return jsonify({"error": "Invalid platform"}), 400

    state = load_state()
    state[env_id] = {
        "platform": platform,
        "config": data.get("config", {}),
        "status": state.get(env_id, {}).get("status", "configured"),
        "created_at": state.get(env_id, {}).get("created_at", time.strftime("%Y-%m-%dT%H:%M:%SZ")),
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    save_state(state)

    try:
        write_tfvars(env_id, platform, data.get("config", {}))
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500

    return jsonify({"env_id": env_id, "status": "configured"})


@app.route("/api/environment/<env_id>", methods=["DELETE"])
def delete_environment_api(env_id: str):
    if not validate_env_id(env_id):
        return jsonify({"error": "Invalid environment ID"}), 400
    state = load_state()
    state.pop(env_id, None)
    save_state(state)
    # remove tfvars file
    for platform in PLATFORMS:
        p = tfvars_path(env_id, platform)
        if p.exists():
            p.unlink()
    return jsonify({"status": "deleted"})


def _resolve_tf_dir(platform: str) -> str:
    return str(TERRAFORM_DIR / platform)


def _tf_cmd(platform: str, env_id: str, action: str) -> tuple[list[str], str]:
    """Return (command_list, working_dir) for a terraform action."""
    tf_dir = _resolve_tf_dir(platform)
    varfile = tfvars_path(env_id, platform)
    base = ["terraform"]
    if action == "init":
        return base + ["init", "-input=false"], tf_dir
    if action == "apply":
        return (
            base + ["apply", "-auto-approve", "-input=false", f"-var-file={varfile}"],
            tf_dir,
        )
    if action == "destroy":
        return (
            base + ["destroy", "-auto-approve", "-input=false", f"-var-file={varfile}"],
            tf_dir,
        )
    raise ValueError(f"Unknown action: {action}")


def _ansible_cmd(action: str, inventory: str) -> list[str]:
    ansible_dir = str(ANSIBLE_DIR)
    if action == "stop":
        playbook = "stop.yml"
    elif action == "restart":
        playbook = "restart.yml"
    else:
        playbook = "main.yml"
    return ["ansible-playbook", "-i", inventory, playbook]


@app.route("/api/environment/<env_id>/action", methods=["POST"])
def environment_action(env_id: str):
    """
    Supported actions:
      - deploy   : terraform init + apply (+ ansible for cloud)
      - stop     : ansible stop.yml
      - restart  : ansible restart.yml
      - destroy  : terraform destroy
    """
    if not validate_env_id(env_id):
        return jsonify({"error": "Invalid environment ID"}), 400

    state = load_state()
    env = state.get(env_id)
    if not env:
        return jsonify({"error": "Environment not found"}), 404

    body = request.get_json(force=True)
    action = body.get("action")
    platform = env["platform"]
    tf_dir = _resolve_tf_dir(platform)
    varfile = shlex.quote(str(tfvars_path(env_id, platform)))

    valid_actions = {"deploy", "stop", "restart", "destroy"}
    if action not in valid_actions:
        return jsonify({"error": f"Unknown action: {action}"}), 400

    if action == "deploy":
        # Build a multi-step shell command: tf init && tf apply [&& ansible]
        tf_apply_cmd = (
            f"terraform init -input=false && "
            f"terraform apply -auto-approve -input=false -var-file={varfile}"
        )
        if platform != "docker":
            # Also run ansible after terraform
            inventory_guess = shlex.quote(str(ANSIBLE_DIR / "inventory"))
            ansible_playbook = shlex.quote(str(ANSIBLE_DIR / "main.yml"))
            tf_apply_cmd += f" && ansible-playbook -i {inventory_guess} {ansible_playbook}"
        cmd = ["bash", "-c", tf_apply_cmd]
    elif action == "destroy":
        cmd = [
            "bash",
            "-c",
            f"terraform destroy -auto-approve -input=false -var-file={varfile}",
        ]
    elif action in ("stop", "restart"):
        # For docker, use terraform; for cloud, use ansible
        if platform == "docker":
            # docker stop/start via terraform taint or custom script – use terraform apply to reconcile
            cmd = ["bash", "-c", f"terraform apply -auto-approve -input=false -var-file={varfile}"]
        else:
            inventory_guess = shlex.quote(str(ANSIBLE_DIR / "inventory"))
            playbook = shlex.quote(str(ANSIBLE_DIR / ("stop.yml" if action == "stop" else "restart.yml")))
            cmd = ["bash", "-c", f"ansible-playbook -i {inventory_guess} {playbook}"]
    else:
        return jsonify({"error": "Unhandled action"}), 500

    job_id = start_job(cmd, cwd=tf_dir)

    # Update env status
    state[env_id]["status"] = f"{action}_in_progress"
    state[env_id]["last_job_id"] = job_id
    save_state(state)

    return jsonify({"job_id": job_id, "status": f"{action}_in_progress"})


@app.route("/api/job/<job_id>/status")
def job_status(job_id: str):
    status_path = job_status_path(job_id)
    if not status_path.exists():
        return jsonify({"status": "unknown"})
    status = status_path.read_text().strip()
    return jsonify({"status": status})


@app.route("/api/job/<job_id>/stream")
def job_stream(job_id: str):
    """Server-Sent Events stream of job log output."""
    log_path = job_log_path(job_id)
    status_path = job_status_path(job_id)

    def generate():
        # Wait a moment for the file to be created
        for _ in range(20):
            if log_path.exists():
                break
            time.sleep(0.1)

        pos = 0
        while True:
            if log_path.exists():
                with open(log_path) as f:
                    f.seek(pos)
                    chunk = f.read(4096)
                    if chunk:
                        pos += len(chunk)
                        for line in chunk.splitlines():
                            yield f"data: {json.dumps(line)}\n\n"
            # Check if job finished
            if status_path.exists():
                status = status_path.read_text().strip()
                if status != "running":
                    yield f"event: done\ndata: {json.dumps(status)}\n\n"
                    return
            time.sleep(0.3)

    return Response(generate(), mimetype="text/event-stream")


@app.route("/api/job/<job_id>/log")
def job_log(job_id: str):
    log_path = job_log_path(job_id)
    if not log_path.exists():
        return jsonify({"log": "", "status": "unknown"})
    status_path = job_status_path(job_id)
    status = status_path.read_text().strip() if status_path.exists() else "unknown"
    return jsonify({"log": log_path.read_text(), "status": status})


if __name__ == "__main__":
    debug_mode = os.environ.get("FLASK_DEBUG", "0") == "1"
    app.run(host="127.0.0.1", port=5000, debug=debug_mode, threaded=True)
