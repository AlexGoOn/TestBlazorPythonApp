"""HTTP utilities for the Python service."""

import inspect
import logging
import urllib.error

from fastapi import Request
from fastapi.responses import JSONResponse


class AuthError(Exception):
    """Raised when authentication fails (results in 401)."""


def route_handler(handler):
    """
    Decorator for route functions. Handles JSON formatting and exceptions.

    Handler signatures:
    - handler(req) -> dict                     - full request only
    - handler(name, age) -> dict               - params from query string
    - handler(name, age, req) -> dict          - both params and request

    Exceptions: AuthError->401, ValueError->400, HTTPError->status, Other->500
    """
    sig = inspect.signature(handler)
    params = list(sig.parameters.keys())
    has_req = "req" in params
    query_params = [p for p in params if p != "req"]

    async def wrapper(req: Request):
        try:
            # Only include params that are present in request (let function defaults apply)
            kwargs = {p: req.query_params[p] for p in query_params if p in req.query_params}
            if has_req:
                kwargs["req"] = req  # type: ignore
            result = handler(**kwargs)
            return JSONResponse(content=result)
        except AuthError as e:
            return JSONResponse(content={"error": str(e)}, status_code=401)
        except ValueError as e:
            return JSONResponse(content={"error": str(e)}, status_code=400)
        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8") if e.fp else ""
            status = e.code if e.code in [400, 401, 403, 404] else 500
            return JSONResponse(content={"error": str(e.code), "details": error_body}, status_code=status)
        except Exception as e:  # pylint: disable=broad-except
            logging.exception("Route error:")
            return JSONResponse(content={"error": str(e)}, status_code=500)

    # Preserve the wrapper's Request signature.
    wrapper.__name__ = handler.__name__
    wrapper.__doc__ = handler.__doc__
    return wrapper
