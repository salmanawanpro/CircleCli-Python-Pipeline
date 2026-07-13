import os
import sys
from pathlib import Path

import pytest
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

BASE_URL = os.environ.get("BASE_URL", "http://127.0.0.1:5000")


@pytest.fixture(scope="module")
def base_url():
    return BASE_URL.rstrip("/")


def test_image_health(base_url):
    resp = requests.get(f"{base_url}/health", timeout=10)
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_image_ready(base_url):
    resp = requests.get(f"{base_url}/ready", timeout=10)
    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"


def test_image_widget_flow(base_url):
    created = requests.post(
        f"{base_url}/widgets",
        json={"name": "image-smoke"},
        timeout=10,
    )
    assert created.status_code == 201
    assert created.json()["name"] == "image-smoke"

    listed = requests.get(f"{base_url}/widgets", timeout=10)
    assert listed.status_code == 200
    names = [w["name"] for w in listed.json()]
    assert "image-smoke" in names
