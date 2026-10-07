import os
from datetime import timezone
from uuid import UUID, uuid4

import pyodbc


def connect() -> pyodbc.Connection:
    connection_string = os.environ.get("SQL_CONNECTION_STRING")
    if not connection_string:
        raise RuntimeError("SQL_CONNECTION_STRING must be configured.")
    return pyodbc.connect(
        connection_string, timeout=int(os.environ.get("SQL_CONNECT_TIMEOUT", "5"))
    )


def ping() -> None:
    connection = connect()
    try:
        connection.execute("SELECT TOP (0) Id FROM dbo.Notes")
    finally:
        connection.close()


def list_notes() -> list[dict]:
    connection = connect()
    try:
        rows = connection.execute(
            "SELECT TOP (100) Id, Text, CreatedBy, CreatedAt FROM dbo.Notes ORDER BY CreatedAt DESC, Id"
        ).fetchall()
        return [
            {
                "id": str(UUID(str(row.Id))),
                "text": row.Text,
                "createdBy": row.CreatedBy,
                "createdAt": row.CreatedAt.replace(tzinfo=timezone.utc),
            }
            for row in rows
        ]
    finally:
        connection.close()


def create_note(text: str) -> dict:
    connection = connect()
    try:
        row = connection.execute(
            """
            INSERT INTO dbo.Notes (Id, Text, CreatedBy)
            OUTPUT INSERTED.Id, INSERTED.Text, INSERTED.CreatedBy, INSERTED.CreatedAt
            VALUES (?, ?, 'Python')
            """,
            str(uuid4()),
            text,
        ).fetchone()
        connection.commit()
        return {
            "id": str(UUID(str(row.Id))),
            "text": row.Text,
            "createdBy": row.CreatedBy,
            "createdAt": row.CreatedAt.replace(tzinfo=timezone.utc),
        }
    finally:
        connection.close()
