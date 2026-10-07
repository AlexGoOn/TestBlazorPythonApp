from utils.http import route_handler


@route_handler
def hello(name: str = "World") -> dict:
    """Demo endpoint that greets by name."""
    return {"message": f"Hello, {name}!"}
