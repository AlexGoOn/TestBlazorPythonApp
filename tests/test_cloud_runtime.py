import importlib
import importlib.util
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

BACKEND = Path(__file__).resolve().parents[1] / "src" / "backend"
sys.path.insert(0, str(BACKEND))
import azure_startup
import database


class CloudRuntimeTests(unittest.TestCase):
    def test_missing_driver_fails_before_starting_server(self):
        with patch("azure_startup.pyodbc.drivers", return_value=[]), patch("azure_startup.uvicorn.run") as run:
            with self.assertRaisesRegex(RuntimeError, "ODBC Driver 18"):
                azure_startup.main()
            run.assert_not_called()

    def test_missing_cloud_settings_fail(self):
        with patch.dict(os.environ, {}, clear=True), patch(
            "azure_startup.pyodbc.drivers", return_value=["ODBC Driver 18 for SQL Server"]
        ):
            with self.assertRaisesRegex(RuntimeError, "SQL_CONNECTION_STRING"):
                azure_startup.main()

    def test_cloud_startup_uses_app_service_port(self):
        with patch.dict(os.environ, {
            "SQL_CONNECTION_STRING": "test",
            "APPLICATIONINSIGHTS_CONNECTION_STRING": "test",
            "OTEL_SERVICE_NAME": "template-dev-python",
        }, clear=True), patch(
            "azure_startup.pyodbc.drivers", return_value=["ODBC Driver 18 for SQL Server"]
        ), patch("azure_startup.uvicorn.run") as run:
            azure_startup.main()
            run.assert_called_once_with("web_app:app", host="0.0.0.0", port=8000)

    def test_cloud_sql_timeout_and_local_default(self):
        for timeout in (None, "30"):
            settings = {"SQL_CONNECTION_STRING": "test"}
            if timeout:
                settings["SQL_CONNECT_TIMEOUT"] = timeout
            with patch.dict(os.environ, settings, clear=True), patch("database.pyodbc.connect") as connect:
                database.connect()
                connect.assert_called_once_with("test", timeout=int(timeout or "5"))

    def test_telemetry_modules_are_installed(self):
        for module in ("azure.monitor.opentelemetry", "opentelemetry.instrumentation.fastapi"):
            self.assertIsNotNone(importlib.util.find_spec(module))

    def test_azure_instruments_fastapi_once_without_exporting_test_data(self):
        with patch.dict(os.environ, {"APPLICATIONINSIGHTS_CONNECTION_STRING": "test"}), patch(
            "azure.monitor.opentelemetry.configure_azure_monitor"
        ) as configure, patch(
            "opentelemetry.instrumentation.fastapi.FastAPIInstrumentor.instrument_app"
        ) as instrument:
            try:
                app_module = importlib.import_module("web_app")
                configure.assert_called_once_with(instrumentation_options={"fastapi": {"enabled": False}})
                instrument.assert_called_once_with(app_module.app)
            finally:
                sys.modules.pop("web_app", None)


if __name__ == "__main__":
    unittest.main()
