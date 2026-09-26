import json
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from backend_fastapi.main import Settings, create_app

USER = "3e8af526-7aa2-47d6-997f-d94fdf8d2501"
HEADERS = {"Authorization": "Bearer valid-token"}


def payload(**updates):
    return {"request_id": str(uuid4()), "latitud": 20.5333, "longitud": -97.4595,
            "descripcion": "Obstrucción junto al cruce principal", "tipo": "obstruccion", **updates}


@pytest.fixture
def client():
    calls = []

    def handle(request):
        calls.append(request)
        path = request.url.path
        if path == "/auth/v1/user":
            if request.headers.get("authorization") != "Bearer valid-token":
                return httpx.Response(401, json={"message": "invalid token"})
            return httpx.Response(200, json={"id": USER, "is_anonymous": False})
        if path == "/rest/v1/alertx_reports":
            return httpx.Response(200, json=[])
        if path == "/rest/v1/rpc/alertx_create_report":
            body = json.loads(request.content)
            return httpx.Response(200, json={"id": "saved-id", "estado": "recibido", **body})
        if path == "/rest/v1/rpc/alertx_my_stats":
            return httpx.Response(200, json={"total": 1200, "recibidos": 1198, "en_revision": 1, "cerrados": 1})
        return httpx.Response(200, json={"ok": True})

    app = create_app(Settings(supabase_url="https://project.supabase.co", supabase_anon_key="public-key",
        cors_origins=("https://app.example.com",)), transport=httpx.MockTransport(handle))
    with TestClient(app) as test_client:
        yield test_client, calls


@pytest.mark.parametrize("path", ["/reportes", "/estadisticas"])
def test_private_routes_require_session(client, path):
    api, calls = client
    assert api.get(path).status_code == 401
    assert not calls


def test_invalid_token_never_reaches_database(client):
    api, calls = client
    assert api.get("/reportes", headers={"Authorization": "Bearer invalid"}).status_code == 401
    assert len(calls) == 1


def test_list_scopes_user_and_bounds_page(client):
    api, calls = client
    assert api.get("/reportes?limit=20&offset=40", headers=HEADERS).status_code == 200
    assert calls[-1].url.params["usuario_id"] == f"eq.{USER}"
    assert calls[-1].url.params["offset"] == "40"
    assert calls[-1].headers["authorization"] == "Bearer valid-token"
    assert api.get("/reportes?limit=10000", headers=HEADERS).status_code == 422


@pytest.mark.parametrize("updates", [
    {"latitud": 91}, {"longitud": -181}, {"descripcion": " " * 20},
    {"descripcion": "x" * 2001}, {"tipo": "unknown"}, {"precision_metros": -1},
    {"usuario_id": "spoofed-user"}, {"usuario_verificado": True}, {"estado": "cerrado"},
    {"request_id": "not-a-uuid"}, {"latitud": "NaN"},
])
def test_invalid_or_forged_report_rejected(client, updates):
    api, calls = client
    response = api.post("/reportes", headers=HEADERS, json=payload(**updates))
    assert response.status_code == 422
    assert not any("alertx_create_report" in r.url.path for r in calls)
    assert "spoofed-user" not in response.text


def test_creation_forwards_idempotency_key_not_identity(client):
    api, calls = client
    data = payload()
    for _ in range(2):
        response = api.post("/reportes", headers=HEADERS, json=data)
        assert response.status_code == 201
    sent = [json.loads(r.content) for r in calls if "alertx_create_report" in r.url.path]
    assert sent[0] == sent[1]
    assert sent[0]["p_request_id"] == data["request_id"]
    assert "usuario_id" not in sent[0]


def test_stats_uses_database_aggregate(client):
    api, calls = client
    assert api.get("/estadisticas", headers=HEADERS).json()["total"] == 1200
    assert calls[-1].url.path.endswith("/alertx_my_stats")


def test_body_limit_and_security_headers(client):
    api, _ = client
    response = api.post("/reportes", headers=HEADERS, content=b"x" * 20000)
    assert response.status_code == 413
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-request-id"]


def test_cors_allowlist(client):
    api, _ = client
    headers = {"Origin": "https://app.example.com", "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "Authorization"}
    response = api.options("/reportes", headers=headers)
    assert response.headers["access-control-allow-origin"] == "https://app.example.com"
    headers["Origin"] = "https://unknown.example"
    assert "access-control-allow-origin" not in api.options("/reportes", headers=headers).headers


def test_liveness_does_not_claim_database_readiness():
    with TestClient(create_app(Settings())) as api:
        assert api.get("/health").status_code == 200
        assert api.get("/ready").status_code == 503


@pytest.mark.parametrize("status,body,expected", [
    (500, {"message": "secret connection password"}, 503),
    (400, {"message": "report_rate_limit"}, 429),
    (400, {"message": "idempotency_conflict"}, 409),
])
def test_upstream_failures_are_sanitized(status, body, expected):
    def handler(request):
        if request.url.path == "/auth/v1/user":
            return httpx.Response(200, json={"id": USER})
        return httpx.Response(status, json=body)
    with TestClient(create_app(Settings(supabase_url="https://example.com", supabase_anon_key="public"), transport=httpx.MockTransport(handler))) as api:
        response = api.post("/reportes", headers=HEADERS, json=payload())
        assert response.status_code == expected
        assert "password" not in response.text


def test_upstream_timeout_returns_retryable_error():
    def handler(request):
        raise httpx.ReadTimeout("secret host", request=request)
    with TestClient(create_app(Settings(supabase_url="https://example.com", supabase_anon_key="public"), transport=httpx.MockTransport(handler))) as api:
        response = api.get("/reportes", headers=HEADERS)
        assert response.status_code == 503
        assert "secret host" not in response.text


def test_production_refuses_missing_settings_or_secret_key():
    with pytest.raises(RuntimeError):
        create_app(Settings(environment="production"))
    with pytest.raises(RuntimeError):
        create_app(Settings(supabase_anon_key="sb_secret_example"))


def test_experimental_endpoints_are_retired(client):
    api, _ = client
    assert api.post("/analizar_imagen_accidente", headers=HEADERS).status_code == 410


def test_unknown_host_rejected(client):
    api, _ = client
    assert api.get("/health", headers={"Host": "attacker.example"}).status_code == 400
