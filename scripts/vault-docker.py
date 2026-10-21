#!/usr/bin/env python3
"""Controller-managed Vault bootstrap for Docker. Secrets never enter tfstate."""

import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import time


def run(args, data=None, check=True):
    result = subprocess.run(args, input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    if check and result.returncode:
        # Do not print subprocess output: Vault responses can contain secrets.
        raise RuntimeError("Vault/Docker operation failed: " + args[0])
    return result


def private_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_name(path.name + ".tmp")
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as output:
        output.write(data)
    os.chmod(temp, 0o600)
    os.replace(temp, path)


def upload(volume, image, files, uid, directory="/"):
    archive = io.BytesIO()
    with tarfile.open(fileobj=archive, mode="w") as tar:
        for name, data in files.items():
            if not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
                raise ValueError("Invalid credential filename")
            content = data.encode()
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.uid, info.gid = len(content), 0o400, uid, uid
            tar.addfile(info, io.BytesIO(content))
    run(["docker", "run", "--rm", "-i", "--user", "0", "--entrypoint", "sh",
         "-v", volume + ":/mnt", image, "-c",
         'mkdir -p "/mnt' + directory + '" && tar -xf - -C "/mnt' + directory +
         '" && chown -R ' + str(uid) + ':' + str(uid) + ' /mnt && chmod 700 /mnt'],
        archive.getvalue())


class Vault:
    def __init__(self, name):
        self.name = name

    def call(self, args, token="", body="", check=True):
        # Pass the token on stdin rather than command arguments/container env.
        command = ('read -r VAULT_TOKEN; export VAULT_TOKEN; '
                   'export VAULT_ADDR=https://127.0.0.1:8200 '
                   'VAULT_CACERT=/vault/config/vault.crt; exec vault "$@"')
        result = run([
            "docker", "exec", "-i", self.name, "sh", "-c",
            command,
            "vault", *args], (token + "\n" + body).encode(), check=check)
        return result

    def json(self, args, token=""):
        return json.loads(self.call(args, token).stdout)


def prepare(name, image, state):
    cert, key = state / "vault.crt", state / "vault.key"
    if not cert.exists():
        ssl_config = state / "vault-ssl.cnf"
        private_write(ssl_config,
                      "[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=extensions\n"
                      "[dn]\nCN=" + name + "\n[extensions]\n"
                      "basicConstraints=critical,CA:TRUE\n"
                      "subjectAltName=DNS:" + name + ",IP:127.0.0.1\n")
        run(["openssl", "req", "-x509", "-nodes", "-newkey", "rsa:2048",
             "-days", "3650", "-config", str(ssl_config),
             "-keyout", str(key), "-out", str(cert)])
        os.chmod(key, 0o600)
    config = ('ui = true\ndisable_mlock = true\n'
              'storage "file" { path = "/vault/data/storage" }\n'
              'listener "tcp" {\n address = "0.0.0.0:8200"\n'
              ' tls_cert_file = "/vault/config/vault.crt"\n'
              ' tls_key_file = "/vault/config/vault.key"\n}\n')
    upload(name + "-config", image, {"vault.crt": cert.read_text(),
           "vault.key": key.read_text(), "vault.hcl": config}, 100)
    run(["docker", "run", "--rm", "--user", "0", "--entrypoint", "sh",
         "-v", name + "-data:/mnt", image, "-c",
         "mkdir -p /mnt/storage /mnt/tokens && chown -R 100:100 /mnt && chmod 700 /mnt"])


def bootstrap(name, image, state, credentials):
    vault = Vault(name)
    run(["docker", "start", name])
    status = None
    for _ in range(60):
        result = vault.call(["status", "-format=json"], check=False)
        if result.returncode in (0, 2):
            status = json.loads(result.stdout)
            break
        time.sleep(1)
    if status is None:
        raise RuntimeError("Timed out waiting for Vault")

    recovery_file = state / "init.json"
    if not status["initialized"]:
        if recovery_file.exists():
            raise RuntimeError("Uninitialized Vault has existing controller recovery material; restore its data volume")
        recovery = vault.json(["operator", "init", "-format=json",
                               "-key-shares=5", "-key-threshold=3"])
        private_write(recovery_file, json.dumps(recovery))
    elif not recovery_file.exists():
        raise RuntimeError("Controller init.json is missing; restore recovery material")
    recovery = json.loads(recovery_file.read_text())
    if status["sealed"]:
        vault.call(["write", "-format=json", "sys/unseal", "-"],
                   body=json.dumps({"reset": True}))
        for share in recovery["unseal_keys_b64"][:3]:
            # Submit shares as stdin JSON, never as process arguments.
            vault.call(["write", "-format=json", "sys/unseal", "-"],
                       body=json.dumps({"key": share}))
    if vault.json(["status", "-format=json"])["sealed"]:
        raise RuntimeError("Vault remains sealed")

    root = recovery["root_token"]
    mounts = vault.json(["secrets", "list", "-format=json"], root)
    if "secret/" not in mounts:
        vault.call(["secrets", "enable", "-path=secret", "kv-v2"], root)
    elif mounts["secret/"]["options"].get("version") != "2":
        raise RuntimeError("Vault secret mount must use KV v2")
    vault.call(["write", "secret/config", "max_versions=10000"], root)
    renewal = {}
    for topology, volume in credentials.items():
        if not re.fullmatch(r"(?:cluster|replset)-[A-Za-z0-9_-]+", topology):
            raise ValueError("Invalid topology namespace")
        policy = ('path "secret/data/' + topology + '/*" { capabilities = ["create", "read", "update"] }\n'
                  'path "secret/metadata/' + topology + '/*" { capabilities = ["read"] }\n'
                  'path "secret/config" { capabilities = ["read"] }\n'
                  'path "auth/token/lookup-self" { capabilities = ["read"] }\n'
                  'path "auth/token/renew-self" { capabilities = ["update"] }\n')
        vault.call(["policy", "write", topology, "-"], root, policy)
        token_path = state / (topology + ".token")
        token = token_path.read_text().strip() if token_path.exists() else ""
        if not token or vault.call(["token", "renew", "-format=json"], token, check=False).returncode:
            token = vault.json(["token", "create", "-orphan", "-no-default-policy",
                                "-policy=" + topology, "-period=720h", "-format=json"], root)["auth"]["client_token"]
            private_write(token_path, token)
        upload(volume, image, {"token": token, "vault.crt": (state / "vault.crt").read_text()}, 1001)
        renewal[topology + ".token"] = token
    upload(name + "-data", image, renewal, 100, "/tokens")
    private_write(state / "topologies.json", json.dumps({topology: True for topology in credentials}))


def check_data_mode(volume, image, enabled, uid):
    command = r'''
      set -eu
      marker=/data/db/.framework-vault-encryption
      if [ -f "$marker" ]; then
        [ "$(cat "$marker")" = "$ENCRYPTION" ] || exit 2
      elif [ -f /data/db/WiredTiger ] && [ "$ENCRYPTION" = true ]; then
        exit 2
      fi
      printf '%s' "$ENCRYPTION" > "$marker"
      chmod 600 "$marker"
      chown "$MONGO_UID" "$marker"
    '''
    result = run(["docker", "run", "--rm", "--user", "0", "--entrypoint", "sh",
                  "-e", "ENCRYPTION=" + enabled, "-e", "MONGO_UID=" + uid,
                  "-v", volume + ":/data/db", image, "-c", command], check=False)
    if result.returncode:
        raise RuntimeError("Changing encryption on an existing data volume requires migration or recreation")


def main():
    action = sys.argv[1]
    if action == "check-data":
        check_data_mode(os.environ["VAULT_DATA_VOLUME"], os.environ["VAULT_IMAGE"],
                        os.environ["VAULT_ENCRYPTION"], os.environ["MONGO_UID"])
        return
    state = Path(os.environ["VAULT_CONTROLLER_DIR"]).resolve()
    if action == "destroy":
        # Only delete the exact environment directory supplied by Terraform/UI.
        import shutil
        protected = {Path("/").resolve(), Path.home().resolve(),
                     Path.cwd().resolve(), Path("/tmp").resolve()}
        if state in protected or len(state.parts) < 3:
            raise ValueError("Invalid Vault controller directory")
        if state.exists():
            artifacts = ("init.json", "vault.crt", "topologies.json", "vault-ssl.cnf")
            if any(state.iterdir()) and not any((state / name).is_file() for name in artifacts):
                raise ValueError("Directory does not contain framework Vault recovery artifacts")
            shutil.rmtree(state)
        return
    name, image = os.environ["VAULT_CONTAINER"], os.environ["VAULT_IMAGE"]
    if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
        raise ValueError("Invalid Vault container name")
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(state, 0o700)
    if action == "prepare":
        prepare(name, image, state)
    elif action == "bootstrap":
        bootstrap(name, image, state, json.loads(os.environ["VAULT_CREDENTIALS"]))
    else:
        raise ValueError("Unknown action")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
