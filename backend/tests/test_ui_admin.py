"""Tests for the admin ui_copy editor endpoints."""
import httpx


async def test_non_admin_forbidden_get(client: httpx.AsyncClient, nahda_token: str):
    resp = await client.get(
        "/api/v1/ui/copy",
        headers={"Authorization": f"Bearer {nahda_token}"},
    )
    assert resp.status_code == 403


async def test_non_admin_forbidden_put(client: httpx.AsyncClient, nahda_token: str):
    resp = await client.put(
        "/api/v1/ui/copy/common.apply",
        headers={"Authorization": f"Bearer {nahda_token}"},
        json={"value": "x"},
    )
    assert resp.status_code == 403


async def test_requires_auth(client: httpx.AsyncClient):
    resp = await client.get("/api/v1/ui/copy")
    assert resp.status_code == 401


async def test_admin_list_copy(client: httpx.AsyncClient, filla_token: str):
    resp = await client.get(
        "/api/v1/ui/copy",
        headers={"Authorization": f"Bearer {filla_token}"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data["items"], list)
    assert len(data["items"]) > 100
    keys = [item["key"] for item in data["items"]]
    assert "common.apply" in keys
    assert "home.hero_title" in keys
    item = next(i for i in data["items"] if i["key"] == "common.apply")
    assert isinstance(item["value"], str) and item["value"]


async def test_admin_list_search(client: httpx.AsyncClient, filla_token: str):
    resp = await client.get(
        "/api/v1/ui/copy?search=hero_title",
        headers={"Authorization": f"Bearer {filla_token}"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["items"]) >= 1
    assert all("hero_title" in item["key"] for item in data["items"])


async def test_admin_put_updates_and_busts_cache(
    client: httpx.AsyncClient, filla_token: str
):
    """PUT changes value; next bootstrap (cache busted) shows it."""
    resp = await client.put(
        "/api/v1/ui/copy/common.apply",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"value": "Simpan tes admin"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["key"] == "common.apply"
    assert data["value"] == "Simpan tes admin"

    # No auth on bootstrap; should pick new value after PUT busts cache.
    boot = await client.get("/api/v1/ui/bootstrap")
    assert boot.status_code == 200
    boot_data = boot.json()
    assert boot_data["copy"]["common.apply"] == "Simpan tes admin"

    # Restore
    await client.put(
        "/api/v1/ui/copy/common.apply",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"value": "Terapin"},
    )


async def test_admin_put_upserts_new_key(
    client: httpx.AsyncClient, filla_token: str
):
    resp = await client.put(
        "/api/v1/ui/copy/common.testadmin",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"value": "Nilai admin"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["key"] == "common.testadmin"
    assert body["value"] == "Nilai admin"

    boot = await client.get("/api/v1/ui/bootstrap")
    assert boot.json()["copy"].get("common.testadmin") == "Nilai admin"

    # Cleanup the test key (no delete endpoint; reset to empty via direct SQL not available,
    # so leaving it is acceptable for test DB isolation in conftest drops).