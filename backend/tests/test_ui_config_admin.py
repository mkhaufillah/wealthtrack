"""Tests for the admin /ui/config editor endpoints."""
import httpx


async def test_non_admin_forbidden(client: httpx.AsyncClient, nahda_token: str):
    resp = await client.get(
        "/api/v1/ui/config",
        headers={"Authorization": f"Bearer {nahda_token}"},
    )
    assert resp.status_code == 403


async def test_requires_auth(client: httpx.AsyncClient):
    resp = await client.get("/api/v1/ui/config")
    assert resp.status_code == 401


async def test_admin_list_config(client: httpx.AsyncClient, filla_token: str):
    resp = await client.get(
        "/api/v1/ui/config",
        headers={"Authorization": f"Bearer {filla_token}"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data["items"], list)
    keys = [item["key"] for item in data["items"]]
    assert "format" in keys
    assert "flags" in keys
    assert "theme.light" in keys
    fmt = next(i for i in data["items"] if i["key"] == "format")
    assert isinstance(fmt["value"], dict)
    assert "currency_prefix" in fmt["value"]


async def test_admin_put_format_busts_cache(
    client: httpx.AsyncClient, filla_token: str
):
    resp = await client.put(
        "/api/v1/ui/config/format",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"value": {"currency": "IDR", "currency_prefix": "Rp.", "group_sep": ",", "decimal_sep": "."}},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["key"] == "format"
    # Next bootstrap reflects the new prefix (cache busted).
    boot = await client.get("/api/v1/ui/bootstrap")
    assert boot.status_code == 200
    borrow = boot.json()["format"]
    assert borrow["currency_prefix"] == "Rp."

    # Restore
    await client.put(
        "/api/v1/ui/config/format",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"value": {"currency": "IDR", "currency_prefix": "Rp", "group_sep": ".", "decimal_sep": ","}},
    )


async def test_admin_put_rejects_unknown_key(
    client: httpx.AsyncClient, filla_token: str
):
    resp = await client.put(
        "/api/v1/ui/config/bogus",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"value": {"anything": True}},
    )
    assert resp.status_code == 422
    assert "gak dikenal" in resp.json()["detail"].lower()


async def test_admin_put_theme_preset_ok(
    client: httpx.AsyncClient, filla_token: str
):
    """Theme now accepts audited presets (was blocked in v1)."""
    resp = await client.put(
        "/api/v1/ui/config/theme.light",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"preset": "peach"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["key"] == "theme.light"
    assert isinstance(body["value"], dict)
    assert "accent" in body["value"]
    assert body["value"]["accent"].startswith("#")
    # bootstrap reflects it + cache busted
    boot = await client.get("/api/v1/ui/bootstrap")
    assert boot.json()["theme"]["light"]["accent"] == body["value"]["accent"]
    # dark pair available too
    dark_resp = await client.put(
        "/api/v1/ui/config/theme.dark",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"preset": "peach"},
    )
    assert dark_resp.status_code == 200
    assert "accent" in dark_resp.json()["value"]
    # restore default-ish values via the initial preset
    await client.put(
        "/api/v1/ui/config/theme.light",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"preset": "peach"},
    )
    await client.put(
        "/api/v1/ui/config/theme.dark",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"preset": "peach"},
    )


async def test_admin_put_theme_unknown_preset(
    client: httpx.AsyncClient, filla_token: str
):
    resp = await client.put(
        "/api/v1/ui/config/theme.light",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"preset": "totally_unknown"},
    )
    assert resp.status_code == 422
    assert "preset" in resp.json()["detail"].lower()


async def test_admin_put_flags(client: httpx.AsyncClient, filla_token: str):
    resp = await client.put(
        "/api/v1/ui/config/flags",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"value": {"home_all_time": True}},
    )
    assert resp.status_code == 200
    assert resp.json()["value"] == {"home_all_time": True}
    boot = await client.get("/api/v1/ui/bootstrap")
    assert boot.json()["flags"]["home_all_time"] is True
    # Restore
    await client.put(
        "/api/v1/ui/config/flags",
        headers={"Authorization": f"Bearer {filla_token}"},
        json={"value": {"home_all_time": True}},
    )