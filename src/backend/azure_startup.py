import os

import pyodbc
import uvicorn


def main() -> None:
    required_driver = "ODBC Driver 18 for SQL Server"
    if required_driver not in pyodbc.drivers():
        raise RuntimeError(
            f"{required_driver} is missing from the App Service runtime. "
            "Use a supported Python Linux runtime image with msodbcsql18; "
            "installing pyodbc does not install the system driver."
        )
    for name in ("SQL_CONNECTION_STRING", "APPLICATIONINSIGHTS_CONNECTION_STRING", "OTEL_SERVICE_NAME"):
        if not os.environ.get(name):
            raise RuntimeError(f"{name} must be configured for Azure startup.")
    uvicorn.run("web_app:app", host="0.0.0.0", port=8000)


if __name__ == "__main__":
    main()
