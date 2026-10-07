import logging
import os
from contextlib import asynccontextmanager

import pyodbc
from fastapi import FastAPI, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse
from pydantic import BaseModel, field_validator

import database
from routes.hello import hello
from routes.stream import stream


@asynccontextmanager
async def lifespan(_app: FastAPI):
    await run_in_threadpool(database.ping)
    yield


app = FastAPI(title="Blazor Python service", lifespan=lifespan)

if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    from azure.monitor.opentelemetry import configure_azure_monitor
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

    configure_azure_monitor(instrumentation_options={"fastapi": {"enabled": False}})
    FastAPIInstrumentor.instrument_app(app)


class NoteInput(BaseModel):
    text: str

    @field_validator("text")
    @classmethod
    def validate_text(cls, value: str) -> str:
        value = value.strip()
        if not value or len(value.encode("utf-16-le")) // 2 > 200:
            raise ValueError("Text must contain between 1 and 200 UTF-16 code units.")
        return value


@app.exception_handler(pyodbc.Error)
async def database_error(_request: Request, error: pyodbc.Error):
    logging.error("SQL operation failed", exc_info=(type(error), error, error.__traceback__))
    return JSONResponse(status_code=503, content={"error": "SQL database is unavailable."})


@app.get("/health")
def health():
    database.ping()
    return {"status": "ok", "database": "ok"}


@app.get("/hello")
async def greeting(request: Request):
    return await hello(request)


@app.get("/stream")
async def numbers(request: Request):
    return await stream(request)


@app.get("/notes")
def notes():
    return database.list_notes()


@app.post("/notes", status_code=201)
def add_note(note: NoteInput):
    return database.create_note(note.text)
