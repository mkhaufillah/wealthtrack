"""Bank inbox HTTP tests."""
import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_ingest_unknown_package(client: AsyncClient, auth_headers: dict):
    res = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={"package": "com.whatsapp", "title": "Hi", "text": "Rp10.000"},
    )
    assert res.status_code == 422
    assert "bukan app bank" in res.json()["detail"]


@pytest.mark.asyncio
async def test_ingest_list_confirm_creates_transaction(client: AsyncClient, auth_headers: dict):
    res = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={
            "package": "com.bca",
            "title": "BCA",
            "text": "Debit Rp50.000 di QRIS GRAB",
            "posted_at": "2026-09-08T10:00:00Z",
        },
    )
    assert res.status_code == 200, res.text
    item = res.json()
    assert item["bank"] == "bca"
    assert item["amount"] == 50000
    assert item["type"] == "expense"
    assert item["parsed"] is True
    assert item["status"] == "pending"
    item_id = item["id"]

    listed = await client.get("/api/v1/bank-inbox", headers=auth_headers)
    assert listed.status_code == 200
    body = listed.json()
    assert body["pending_count"] == 1
    assert body["items"][0]["id"] == item_id

    confirmed = await client.post(
        f"/api/v1/bank-inbox/{item_id}/confirm",
        headers=auth_headers,
        json={},
    )
    assert confirmed.status_code == 200, confirmed.text
    assert confirmed.json()["status"] == "confirmed"
    txn_id = confirmed.json()["transaction_id"]
    assert txn_id

    txn = await client.get(f"/api/v1/transactions/{txn_id}", headers=auth_headers)
    assert txn.status_code == 200
    assert txn.json()["amount"] == 50000
    assert txn.json()["type"] == "expense"


@pytest.mark.asyncio
async def test_ingest_dedup(client: AsyncClient, auth_headers: dict):
    payload = {
        "package": "com.jago.digitalBanking",
        "title": "Jago",
        "text": "Debit Rp25.000 QRIS",
        "posted_at": "2026-09-08T12:00:00Z",
    }
    a = await client.post("/api/v1/bank-inbox", headers=auth_headers, json=payload)
    b = await client.post("/api/v1/bank-inbox", headers=auth_headers, json=payload)
    assert a.status_code == 200
    assert b.status_code == 200
    assert a.json()["id"] == b.json()["id"]


@pytest.mark.asyncio
async def test_reject(client: AsyncClient, auth_headers: dict):
    res = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={"package": "id.co.bri.brimo", "title": "BRImo", "text": "Debit Rp10.000"},
    )
    item_id = res.json()["id"]
    rejected = await client.post(
        f"/api/v1/bank-inbox/{item_id}/reject",
        headers=auth_headers,
    )
    assert rejected.status_code == 200
    assert rejected.json()["status"] == "rejected"

    listed = await client.get("/api/v1/bank-inbox", headers=auth_headers)
    assert listed.json()["pending_count"] == 0


@pytest.mark.asyncio
async def test_unparsed_cannot_confirm(client: AsyncClient, auth_headers: dict):
    res = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={"package": "id.bmri.livin", "title": "Livin", "text": "Transaksi berhasil"},
    )
    assert res.status_code == 200
    assert res.json()["parsed"] is False
    bad = await client.post(
        f"/api/v1/bank-inbox/{res.json()['id']}/confirm",
        headers=auth_headers,
        json={},
    )
    assert bad.status_code == 400
    assert "Nominal" in bad.json()["detail"]


@pytest.mark.asyncio
async def test_requires_auth(client: AsyncClient):
    res = await client.get("/api/v1/bank-inbox")
    assert res.status_code in (401, 403)
