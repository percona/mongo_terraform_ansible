#!/usr/bin/env python3
"""
Web-based frontend for mongo_terraform_ansible.
Allows users to configure, deploy, and manage MongoDB environments
across AWS, GCP, Azure, and Docker platforms.
"""

import json
import logging
import os
import re
import shlex
import subprocess
import threading
import time
import uuid
from collections.abc import Callable
from pathlib import Path

import requests
from flask import Flask, Response, jsonify, redirect, render_template, request, url_for

# ──────────────────────────────────────────────────────────────────────────────
# Logging
# ──────────────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s – %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────────────────────────
# ANSI / terminal helpers
# ──────────────────────────────────────────────────────────────────────────────

# Matches the full ANSI/VT100 escape sequence: ESC followed by a control sequence
_ANSI_ESCAPE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


def strip_ansi(text: str) -> str:
    """Remove ANSI escape codes and normalise line endings."""
    text = _ANSI_ESCAPE.sub("", text)
    # Terraform uses \r to overwrite progress lines; collapse to nothing.
    text = text.replace("\r", "")
    return text

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
        logger.info("Fetched %d tags for %s/%s", len(tags), namespace, repo)
    except Exception as exc:
        logger.warning("Could not fetch Docker Hub tags for %s/%s: %s", namespace, repo, exc)
        tags = []
    _cache_set(key, tags)
    return tags


def get_psmdb_versions() -> list[str]:
    """Return Percona Server for MongoDB release identifiers."""
    key = "psmdb_versions"
    cached = _cache_get(key)
    if cached is not None:
        return cached
    versions: list[str] = []
    try:
        resp = requests.get("https://repo.percona.com/percona/yum/release/", timeout=6)
        if resp.ok:
            found = re.findall(r"psmdb-\d+", resp.text)
            if found:
                versions = sorted(set(found), reverse=True)
        logger.info("Fetched %d PSMDB versions from Percona repo", len(versions))
    except Exception as exc:
        logger.warning("Could not fetch PSMDB versions: %s", exc)
    _cache_set(key, versions)
    return versions


def get_pmm_server_images() -> list[str]:
    tags = get_dockerhub_tags("percona", "pmm-server", 30)
    return tags or ["latest"]


def get_psmdb_images() -> list[str]:
    tags = get_dockerhub_tags("percona", "percona-server-mongodb", 30)
    return tags or ["latest"]


def get_pbm_images() -> list[str]:
    tags = get_dockerhub_tags("percona", "percona-backup-mongodb", 20)
    return tags or ["latest"]


def get_pmm_client_images() -> list[str]:
    tags = get_dockerhub_tags("percona", "pmm-client", 20)
    return tags or ["latest"]


def _prefetch_versions() -> None:
    """Warm the version/image cache in a background thread at startup."""
    logger.info("Prefetching container image tags and PSMDB versions…")
    get_psmdb_versions()
    get_pmm_server_images()
    get_psmdb_images()
    get_pbm_images()
    get_pmm_client_images()
    logger.info("Version prefetch complete.")


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

    # clusters – always write (even as empty map) so the variable default is overridden.
    # Without this, a user who configures only replica sets would get Terraform's default
    # sharded cluster created because the key is absent from the tfvars file.
    clusters = config.get("clusters") or {}
    lines.append("")
    if clusters:
        lines.append("clusters = {")
        for cname, cval in clusters.items():
            lines.append(f'  "{cname}" = {{')
            for k, v in cval.items():
                lines.append(f"    {k} = {_write_val(v)}")
            lines.append("  }")
        lines.append("}")
    else:
        lines.append("clusters = {}")

    # replsets – always write (even as empty map) for the same reason.
    replsets = config.get("replsets") or {}
    lines.append("")
    if replsets:
        lines.append("replsets = {")
        for rname, rval in replsets.items():
            lines.append(f'  "{rname}" = {{')
            for k, v in rval.items():
                lines.append(f"    {k} = {_write_val(v)}")
            lines.append("  }")
        lines.append("}")
    else:
        lines.append("replsets = {}")

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
    logger.info("Wrote tfvars: %s", path)


# ──────────────────────────────────────────────────────────────────────────────
# Job / background process helpers
# ──────────────────────────────────────────────────────────────────────────────

def job_log_path(job_id: str) -> Path:
    return JOBS_DIR / f"{job_id}.log"


def job_status_path(job_id: str) -> Path:
    return JOBS_DIR / f"{job_id}.status"


def _run_job(job_id: str, cmd: list[str], cwd: str, env: dict | None = None,
             on_complete: Callable[[str], None] | None = None):
    """Run a command in a thread, writing output to a log file."""
    log = job_log_path(job_id)
    status = job_status_path(job_id)
    status.write_text("running")
    full_env = {**os.environ, **(env or {})}
    final_status = "error"

    # For ["bash", "-c", "..."] show the shell string; otherwise quote each token.
    if cmd[:2] == ["bash", "-c"] and len(cmd) == 3:
        cmd_display = cmd[2]
    else:
        cmd_display = shlex.join(cmd)

    logger.info("job=%s cwd=%s  cmd: %s", job_id, cwd, cmd_display)

    try:
        with open(log, "w") as f:
            # Write the command at the top of the log so it is visible in the terminal.
            f.write(f"$ {cmd_display}\n")
            f.write(f"# cwd: {cwd}\n\n")
            f.flush()
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
        final_status = "success" if rc == 0 else f"failed:{rc}"
        status.write_text(final_status)
        logger.info("job=%s finished: %s (exit code %d)", job_id, final_status, rc)
    except Exception as exc:
        with open(log, "a") as f:
            f.write(f"\nError: {exc}\n")
        status.write_text("error")
        logger.exception("job=%s raised an exception", job_id)
    if on_complete:
        try:
            on_complete(final_status)
        except Exception:
            pass


def start_job(cmd: list[str], cwd: str, env: dict | None = None,
              on_complete: Callable[[str], None] | None = None) -> str:
    job_id = str(uuid.uuid4())
    t = threading.Thread(target=_run_job, args=(job_id, cmd, cwd, env, on_complete), daemon=True)
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


def _make_destroy_callback(env_id: str, platform: str):
    """Return a callback that removes the env from inventory after a successful destroy."""
    def _callback(status: str):
        if status == "success":
            state = load_state()
            state.pop(env_id, None)
            save_state(state)
            p = tfvars_path(env_id, platform)
            if p.exists():
                p.unlink()
    return _callback


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
        if platform == "docker":
            # Sanitise the prefix to prevent shell injection.  Hyphens are
            # retained because they are valid in container names and are not
            # interpreted as flags by `docker ps --filter name=…`.
            prefix = re.sub(r"[^a-zA-Z0-9_-]", "", env.get("config", {}).get("prefix", env_id))
            if not prefix:
                prefix = env_id
            if action == "stop":
                # Only target running containers (no -a flag)
                cmd = ["bash", "-c",
                    f"docker ps -q --filter 'name={prefix}-' | xargs -r docker stop"]
            else:  # restart
                # Target running and already-stopped containers
                cmd = ["bash", "-c",
                    f"docker ps -aq --filter 'name={prefix}-' | xargs -r docker restart"]
        else:
            inventory_guess = shlex.quote(str(ANSIBLE_DIR / "inventory"))
            playbook = shlex.quote(str(ANSIBLE_DIR / ("stop.yml" if action == "stop" else "restart.yml")))
            cmd = ["bash", "-c", f"ansible-playbook -i {inventory_guess} {playbook}"]
    else:
        return jsonify({"error": "Unhandled action"}), 500

    on_complete = _make_destroy_callback(env_id, platform) if action == "destroy" else None
    job_id = start_job(cmd, cwd=tf_dir, on_complete=on_complete)

    # Update env status
    state[env_id]["status"] = f"{action}_in_progress"
    state[env_id]["last_job_id"] = job_id
    save_state(state)

    logger.info(
        "action=%s env=%s platform=%s job=%s", action, env_id, platform, job_id
    )

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
                            yield f"data: {json.dumps(strip_ansi(line))}\n\n"
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


@app.route("/api/environment/<env_id>/tfvars")
def get_tfvars(env_id: str):
    """Return the raw content of the generated tfvars file for preview."""
    if not validate_env_id(env_id):
        return jsonify({"error": "Invalid environment ID"}), 400
    state = load_state()
    env = state.get(env_id)
    if not env:
        return jsonify({"error": "Environment not found"}), 404
    platform = env["platform"]
    path = tfvars_path(env_id, platform)
    if not path.exists():
        return jsonify({"content": "", "message": "tfvars file not yet generated"})
    return jsonify({"content": path.read_text(), "filename": path.name})


# ──────────────────────────────────────────────────────────────────────────────
# Startup
# ──────────────────────────────────────────────────────────────────────────────

# Prefetch image tags and version lists as soon as the module loads so that the
# first page load is not blocked by network I/O and the lists are always fresh.
threading.Thread(target=_prefetch_versions, daemon=True).start()

if __name__ == "__main__":
    debug_mode = os.environ.get("FLASK_DEBUG", "0") == "1"
    app.run(host="127.0.0.1", port=5000, debug=debug_mode, threaded=True)
