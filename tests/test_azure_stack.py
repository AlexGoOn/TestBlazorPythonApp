import argparse
import os
import sys
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from uuid import uuid4

import requests


def check_anonymous_access(blazor: str, python: str, authority: str) -> None:
    response = requests.get(
        blazor, headers={"User-Agent": "Mozilla/5.0", "Accept": "text/html"},
        allow_redirects=False, timeout=30,
    )
    login = urlsplit(urljoin(blazor, response.headers.get("Location", "")))
    allowed = {
        urlsplit(urljoin(blazor, "/.auth/login/aad"))[:3],
        urlsplit(f"{authority.rstrip('/')}/oauth2/v2.0/authorize")[:3],
    }
    if response.status_code != 302 or login[:3] not in allowed:
        raise AssertionError(
            f"Anonymous Blazor access must redirect to Easy Auth or the configured Entra tenant; "
            f"got {response.status_code}."
        )
    response = requests.get(f"{python}/notes", allow_redirects=False, timeout=30)
    if response.status_code != 403:
        raise AssertionError(f"Public Python access must return 403, got {response.status_code}.")


def main() -> None:
    from playwright.sync_api import expect, sync_playwright

    parser = argparse.ArgumentParser(description="Verify the protected Azure stack after deployment.")
    parser.add_argument("--login", action="store_true", help="Save an interactive Easy Auth session.")
    parser.add_argument("--state", default=".local/azure.auth.json")
    args = parser.parse_args()
    blazor = os.environ["APP_WEB_URL"].rstrip("/")
    python = os.environ["APP_API_URL"].rstrip("/")
    authority = os.environ["ENTRA_AUTHORITY_URL"].rstrip("/")
    for url in (blazor, python, authority):
        if not url.startswith("https://"):
            raise ValueError("Azure test URLs must use HTTPS.")

    check_anonymous_access(blazor, python, authority)

    state = Path(args.state)
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            headless=not args.login, channel="msedge" if sys.platform == "win32" else None
        )
        try:
            if args.login:
                context = browser.new_context()
                page = context.new_page()
                page.goto(blazor)
                print("Complete Microsoft sign-in in the browser (up to 5 minutes).", flush=True)
                page.get_by_role("button", name="Refresh both lists").wait_for(timeout=300_000)
                state.parent.mkdir(parents=True, exist_ok=True)
                context.storage_state(path=str(state))
                print(f"Saved private browser credentials to {state}. Do not commit/share this file.")
                return

            if not state.is_file():
                raise RuntimeError("Run this command with --login before the authenticated test.")
            context = browser.new_context(storage_state=str(state))
            page = context.new_page()
            page.set_default_navigation_timeout(90_000)
            page.goto(blazor)
            page.get_by_role("button", name="Refresh both lists").wait_for(timeout=60_000)
            health = context.request.get(f"{blazor}/health", timeout=60_000)
            if health.status != 200 or health.json().get("database") != "ok":
                raise AssertionError("Blazor could not read dbo.Notes using its managed identity.")
            texts = []
            for source in ("Blazor", "Python"):
                text = f"Azure smoke {source} {uuid4()}"
                texts.append(text)
                page.get_by_label("Note text").fill(text)
                page.get_by_role("button", name=f"Save with {source}").click()
                expect(page.get_by_role("status")).to_have_text(f"Saved by {source}.", timeout=60_000)
                for reader in ("Blazor", "Python"):
                    expect(
                        page.get_by_role("region", name=f"Read by {reader}").get_by_text(text, exact=True)
                    ).to_be_visible(timeout=60_000)
            page.reload()
            for text in texts:
                for reader in ("Blazor", "Python"):
                    expect(
                        page.get_by_role("region", name=f"Read by {reader}").get_by_text(text, exact=True)
                    ).to_be_visible(timeout=60_000)
            print("Verified Entra login, Python restrictions, both SQL writers, cross-reads and persistence.")
            print("Two uniquely named Azure smoke notes remain in the database for inspection.")
        finally:
            browser.close()


if __name__ == "__main__":
    main()
