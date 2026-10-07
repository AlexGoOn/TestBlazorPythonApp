import asyncio

from fastapi import Request
from fastapi.responses import StreamingResponse


async def number_generator():
    """Generate numbers 0-5 with 1 second delay, formatted as SSE."""
    for i in range(6):
        yield f"data: {i}\n\n"
        await asyncio.sleep(1)
    yield "data: [DONE]\n\n"


async def stream(req: Request) -> StreamingResponse:
    """Streaming endpoint that returns numbers 0-5, one per second (SSE format)."""
    return StreamingResponse(
        number_generator(),
        media_type="text/event-stream",
    )
