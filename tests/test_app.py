import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.app import Base, app, engine  # noqa: E402


@pytest.fixture
def client():
    Base.metadata.create_all(engine)
    app.config["TESTING"] = True
    with app.test_client() as test_client:
        yield test_client


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_create_widget(client):
    resp = client.post("/widgets", json={"name": "sprocket"})
    assert resp.status_code == 201
    body = resp.get_json()
    assert body["name"] == "sprocket"


def test_list_widgets(client):
    client.post("/widgets", json={"name": "gear"})
    resp = client.get("/widgets")
    assert resp.status_code == 200
    names = [w["name"] for w in resp.get_json()]
    assert "gear" in names
