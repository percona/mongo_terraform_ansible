import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("vault_docker", Path(__file__).parents[1] / "vault-docker.py")
vault = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vault)


class BootstrapTests(unittest.TestCase):
    def test_destroy_removes_only_the_requested_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            first, second = Path(directory) / "first", Path(directory) / "second"
            for state in (first, second):
                vault.private_write(state / "init.json", '{}')
            with patch.dict(os.environ, {"VAULT_CONTROLLER_DIR": str(first)}), patch.object(vault.sys, "argv", ["vault-docker.py", "destroy"]):
                vault.main()
            self.assertFalse(first.exists())
            self.assertTrue((second / "init.json").exists())

    def test_destroy_rejects_an_unrelated_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "unrelated"
            vault.private_write(state / "notes.txt", "keep me")
            with patch.dict(os.environ, {"VAULT_CONTROLLER_DIR": str(state)}), patch.object(vault.sys, "argv", ["vault-docker.py", "destroy"]):
                with self.assertRaisesRegex(ValueError, "recovery artifacts"):
                    vault.main()
            self.assertEqual((state / "notes.txt").read_text(), "keep me")

    def test_recovery_is_persisted_before_unseal_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            recovery = {"root_token": "test-root", "unseal_keys_b64": ["one", "two", "three"]}

            class FakeVault:
                def __init__(self, name):
                    pass

                def call(self, args, *a, **kw):
                    if args[0] == "status":
                        return type("Result", (), {"returncode": 2, "stdout": json.dumps({"initialized": False, "sealed": True})})()
                    self_outer.assertEqual(json.loads((state / "init.json").read_text()), recovery)
                    raise RuntimeError("unseal failed")

                def json(self, args, *a):
                    return recovery

            self_outer = self
            with patch.object(vault, "Vault", FakeVault), patch.object(vault, "run"):
                with self.assertRaisesRegex(RuntimeError, "unseal failed"):
                    vault.bootstrap("test-vault", "image", state, {})
            self.assertEqual((state / "init.json").stat().st_mode & 0o777, 0o600)

    def test_missing_recovery_never_reinitializes_existing_vault(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(vault, "Vault") as api, patch.object(vault, "run"):
                api.return_value.call.return_value.returncode = 2
                api.return_value.call.return_value.stdout = json.dumps({"initialized": True, "sealed": True})
                with self.assertRaisesRegex(RuntimeError, "missing"):
                    vault.bootstrap("test-vault", "image", Path(directory), {})
                api.return_value.json.assert_not_called()

    def test_existing_recovery_blocks_accidental_new_key_service(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            vault.private_write(state / "init.json", '{}')
            with patch.object(vault, "Vault") as api, patch.object(vault, "run"):
                api.return_value.call.return_value.returncode = 2
                api.return_value.call.return_value.stdout = json.dumps({"initialized": False, "sealed": True})
                with self.assertRaisesRegex(RuntimeError, "restore its data volume"):
                    vault.bootstrap("test-vault", "image", state, {})
                api.return_value.json.assert_not_called()


if __name__ == "__main__":
    unittest.main()
