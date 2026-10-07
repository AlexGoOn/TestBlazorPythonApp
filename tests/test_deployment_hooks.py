import json
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which("pwsh")
AZD = os.environ.get("AZD_EXE") or shutil.which("azd")


class AccessHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.paths.append(self.path)
        status, location = self.server.responses[self.path]
        self.send_response(status)
        if location:
            self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *_args):
        pass


@unittest.skipUnless(PWSH, "PowerShell 7 is required for deployment hook tests.")
class DeploymentHookTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), AccessHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.server.paths = []
        self.server.responses = {
            "/frontend/": (302, "/.auth/login/aad"),
            "/backend/notes": (403, None),
        }

    def run_hook(self, web_url=None):
        values = json.dumps({
            "APP_WEB_URL": web_url or f"{self.base}/frontend",
            "APP_API_URL": f"{self.base}/backend",
        }).replace("'", "''")
        script = str(ROOT / "infra" / "hooks" / "postdeploy.ps1").replace("'", "''")
        command = (
            "$ErrorActionPreference='Stop'; "
            f"function azd {{ $global:LASTEXITCODE=0; '{values}' }}; "
            f"& '{script}'"
        )
        return subprocess.run(
            [PWSH, "-NoProfile", "-Command", command],
            cwd=ROOT / "src" / "blazor",
            capture_output=True, text=True, timeout=45,
        )

    def test_both_access_rules_after_frontend_publication(self):
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.server.paths, ["/frontend/", "/backend/notes"])

    def test_exposed_python_is_rejected(self):
        self.server.responses["/backend/notes"] = (200, None)
        result = self.run_hook()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected 403, got 200", result.stderr)

    def test_unrelated_redirect_is_rejected(self):
        self.server.responses["/frontend/"] = (302, "/unrelated")
        result = self.run_hook()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not redirect to Easy Auth", result.stderr)

    def test_connection_failure_identifies_the_app(self):
        # Port zero cannot be an HTTP server destination.
        url = "http://127.0.0.1:0/frontend"
        result = self.run_hook(web_url=url)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(url, result.stdout + result.stderr)
        self.assertRegex(result.stderr, r"(?s)startup.*logs")

    @unittest.skipUnless(AZD, "azd is required to verify service hook ordering.")
    def test_azd_checks_frontend_only_after_its_own_deployment(self):
        with tempfile.TemporaryDirectory(prefix="azd-hook-test-") as directory:
            root = Path(directory)
            shutil.copyfile(ROOT / "azure.yaml", root / "azure.yaml")
            for service in ("backend", "blazor"):
                (root / "src" / service).mkdir(parents=True)
            hooks = root / "infra" / "hooks"
            hooks.mkdir(parents=True)
            for name in ("postdeploy.ps1", "common.ps1"):
                shutil.copyfile(ROOT / "infra" / "hooks" / name, hooks / name)
            environment = dict(
                os.environ,
                AZURE_ENV_NAME="hook-test-dev",
                PATH=str(Path(AZD).resolve().parent) + os.pathsep + os.environ.get("PATH", ""),
            )
            commands = [
                ["env", "new", "hook-test-dev", "--subscription",
                 "11111111-1111-1111-1111-111111111111", "--location", "westus3"],
                ["env", "set", "AZURE_RESOURCE_GROUP=rg-hook-test",
                 "AZURE_FRONTEND_NAME=frontend", "AZURE_BACKEND_NAME=backend",
                 f"APP_WEB_URL={self.base}/frontend", f"APP_API_URL={self.base}/backend"],
                ["hooks", "run", "postdeploy", "--service", "backend"],
                ["hooks", "run", "postdeploy", "--service", "frontend"],
            ]
            for index, arguments in enumerate(commands):
                result = subprocess.run(
                    [AZD, *arguments, "--no-prompt"],
                    cwd=root, env=environment, capture_output=True, text=True, timeout=60,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                if index == 2:
                    self.assertEqual(self.server.paths, [], "Backend hook checked unpublished Blazor.")
            self.assertEqual(self.server.paths, ["/frontend/", "/backend/notes"])


if __name__ == "__main__":
    unittest.main()
