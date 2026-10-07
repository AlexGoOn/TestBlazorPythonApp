import json
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import Mock, patch

from test_azure_stack import check_anonymous_access

ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which("pwsh")
AZD = os.environ.get("AZD_EXE") or shutil.which("azd")
AUTHORITY = "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/"
AUTHORIZE = f"{AUTHORITY}oauth2/v2.0/authorize"


class AccessHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.paths.append(self.path)
        self.server.request_headers[self.path] = self.headers
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
        self.server.request_headers = {}
        self.server.responses = {
            "/frontend/": (302, "/.auth/login/aad"),
            "/backend/notes": (403, None),
        }

    def run_hook(self, web_url=None):
        values = json.dumps({
            "APP_WEB_URL": web_url or f"{self.base}/frontend",
            "APP_API_URL": f"{self.base}/backend",
            "ENTRA_AUTHORITY_URL": AUTHORITY,
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
        headers = self.server.request_headers["/frontend/"]
        self.assertEqual(headers.get("User-Agent"), "Mozilla/5.0")
        self.assertEqual(headers.get("Accept"), "text/html")

    def test_direct_entra_redirect_is_accepted(self):
        self.server.responses["/frontend/"] = (302, f"{AUTHORIZE}?client_id=test")
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_untrusted_login_redirects_are_rejected(self):
        for location in (
            "https://untrusted.example/.auth/login/aad",
            "https://login.microsoftonline.com/other-tenant/oauth2/v2.0/authorize",
            f"{AUTHORIZE}.invalid",
            None,
        ):
            with self.subTest(location=location):
                self.server.responses["/frontend/"] = (302, location)
                result = self.run_hook()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("did not redirect to Easy Auth", result.stderr)

    def test_browser_probe_requires_login_redirect(self):
        for status in (200, 401, 403, 500):
            with self.subTest(status=status):
                self.server.responses["/frontend/"] = (status, None)
                result = self.run_hook()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"expected 302, got {status}", result.stderr)

    def test_service_discovery_does_not_use_untyped_resource_name_lookup(self):
        self.assertNotIn("resourceName:", (ROOT / "azure.yaml").read_text(encoding="utf-8"))

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
                 f"ENTRA_AUTHORITY_URL={AUTHORITY}",
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


class AzureBrowserProbeTests(unittest.TestCase):
    def run_probe(self, status=302, location="/.auth/login/aad", backend_status=403):
        frontend = Mock(status_code=status, headers={"Location": location} if location else {})
        backend = Mock(status_code=backend_status)
        with patch("test_azure_stack.requests.get", side_effect=[frontend, backend]) as get:
            check_anonymous_access("https://frontend.example", "https://backend.example", AUTHORITY)
        return get

    def test_browser_headers_and_trusted_redirects(self):
        for location in ("/.auth/login/aad", "https://frontend.example/.auth/login/aad",
                         f"{AUTHORIZE}?client_id=test"):
            with self.subTest(location=location):
                get = self.run_probe(location=location)
                self.assertEqual(
                    get.call_args_list[0].kwargs["headers"],
                    {"User-Agent": "Mozilla/5.0", "Accept": "text/html"},
                )
                self.assertFalse(get.call_args_list[0].kwargs["allow_redirects"])

    def test_untrusted_or_missing_redirect_is_rejected(self):
        for location in ("https://untrusted.example/.auth/login/aad", None,
                         "https://login.microsoftonline.com/other-tenant/oauth2/v2.0/authorize",
                         f"{AUTHORIZE}.invalid"):
            with self.subTest(location=location), self.assertRaisesRegex(AssertionError, "must redirect"):
                self.run_probe(location=location)

    def test_frontend_without_login_redirect_is_rejected(self):
        for status in (200, 401, 403, 500):
            with self.subTest(status=status), self.assertRaisesRegex(AssertionError, f"got {status}"):
                self.run_probe(status=status, location=None)

    def test_exposed_backend_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, "must return 403, got 200"):
            self.run_probe(backend_status=200)


if __name__ == "__main__":
    unittest.main()
