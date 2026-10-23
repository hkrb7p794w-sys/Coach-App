from fastapi.testclient import TestClient

from coach_backend import __version__
from coach_backend.main import create_app


def test_health_reports_version():
    client = TestClient(create_app())

    response = client.get("/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": __version__}
