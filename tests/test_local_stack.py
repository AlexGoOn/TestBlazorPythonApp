import os
import sys
import unittest
from uuid import uuid4

import pyodbc
import requests
from playwright.sync_api import sync_playwright

BLAZOR = os.environ.get("BLAZOR_TEST_URL", "http://127.0.0.1:5080")
PYTHON = os.environ.get("PYTHON_TEST_URL", "http://127.0.0.1:3200")


class LocalStackTests(unittest.TestCase):
    def setUp(self):
        self.ids = set()
        self.texts = []

    def tearDown(self):
        connection = pyodbc.connect(os.environ["SQL_CONNECTION_STRING"], timeout=5)
        try:
            for note_id in self.ids:
                connection.execute("DELETE FROM dbo.Notes WHERE Id = ?", note_id)
            for text in self.texts:
                connection.execute("DELETE FROM dbo.Notes WHERE Text = ?", text)
            connection.commit()
        finally:
            connection.close()

    def create(self, url, text, source):
        response = requests.post(url, json={"text": text}, timeout=15)
        self.assertEqual(response.status_code, 201, response.text)
        note = response.json()
        self.ids.add(note["id"])
        self.assertEqual(note["text"], text.strip())
        self.assertEqual(note["createdBy"], source)
        return note

    def test_health_and_existing_greeting(self):
        for base in (BLAZOR, PYTHON):
            response = requests.get(f"{base}/health", timeout=15)
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(response.json()["database"], "ok")
        response = requests.get(f"{PYTHON}/hello", params={"name": "Blazor"}, timeout=15)
        self.assertEqual(response.json(), {"message": "Hello, Blazor!"})

    def test_existing_stream(self):
        response = requests.get(f"{PYTHON}/stream", timeout=15)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.headers["Content-Type"], "text/event-stream; charset=utf-8")
        self.assertEqual(
            response.text,
            "".join(f"data: {number}\n\n" for number in range(6)) + "data: [DONE]\n\n",
        )

    def test_both_writers_and_cross_reads(self):
        text = f"Test O'Brien <script> & {uuid4()}"
        blazor_note = self.create(f"{BLAZOR}/api/notes", f"  {text}  ", "Blazor")
        python_note = self.create(f"{BLAZOR}/api/python/notes", text, "Python")
        direct_note = self.create(f"{PYTHON}/notes", text, "Python")
        for url in (f"{BLAZOR}/api/notes", f"{BLAZOR}/api/python/notes", f"{PYTHON}/notes"):
            response = requests.get(url, timeout=15)
            self.assertEqual(response.status_code, 200, response.text)
            ids = {note["id"] for note in response.json()}
            self.assertTrue({blazor_note["id"], python_note["id"], direct_note["id"]}.issubset(ids))
        connection = pyodbc.connect(os.environ["SQL_CONNECTION_STRING"], timeout=5)
        try:
            for note_id in self.ids:
                row = connection.execute("SELECT Text FROM dbo.Notes WHERE Id = ?", note_id).fetchone()
                self.assertEqual(row.Text, text)
        finally:
            connection.close()

    def test_input_validation(self):
        for path in (f"{BLAZOR}/api/notes", f"{BLAZOR}/api/python/notes", f"{PYTHON}/notes"):
            for text in ("", "  ", "x" * 201, "\U0001f600" * 101, None):
                response = requests.post(path, json={"text": text}, timeout=15)
                self.assertIn(response.status_code, (400, 422), response.text)
        self.create(f"{BLAZOR}/api/notes", "x" * 200, "Blazor")
        self.create(f"{BLAZOR}/api/python/notes", "\U0001f600" * 100, "Python")

    def test_browser_buttons_and_shared_lists(self):
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(channel="msedge" if sys.platform == "win32" else None)
            try:
                page = browser.new_page()
                page.goto(BLAZOR)
                refresh = page.get_by_role("button", name="Refresh both lists")
                refresh.wait_for()
                page.get_by_role("button", name="Save with Blazor").click()
                page.get_by_role("alert").filter(has_text="Text must contain").wait_for()
                for source in ("Blazor", "Python"):
                    text = f"Browser {source} {uuid4()}"
                    self.texts.append(text)
                    page.get_by_label("Note text").fill(text)
                    page.get_by_role("button", name=f"Save with {source}").click()
                    page.get_by_role("status").filter(has_text=f"Saved by {source}.").wait_for()
                    for reader in ("Blazor", "Python"):
                        section = page.get_by_role("region", name=f"Read by {reader}")
                        section.get_by_text(text, exact=True).wait_for()
                page.reload()
                for text in self.texts:
                    for reader in ("Blazor", "Python"):
                        page.get_by_role("region", name=f"Read by {reader}").get_by_text(
                            text, exact=True
                        ).wait_for()
            finally:
                browser.close()


if __name__ == "__main__":
    unittest.main()
