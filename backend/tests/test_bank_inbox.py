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
    assert res.status_code == 200
    assert res.json()["bank"] == "whatsapp"


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

    deleted = await client.delete(
        f"/api/v1/transactions/{txn_id}",
        headers=auth_headers,
    )
    assert deleted.status_code == 204, deleted.text
    gone = await client.get(f"/api/v1/transactions/{txn_id}", headers=auth_headers)
    assert gone.status_code == 404


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
    assert listed.status_code == 200
    assert listed.json()["pending_count"] == 0
    assert listed.json()["items"][0]["status"] == "rejected"


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


@pytest.mark.asyncio
async def test_list_sorts_pending_then_confirmed_then_rejected(
    client: AsyncClient, auth_headers: dict
):
    older_pending = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={
            "package": "com.bca",
            "title": "BCA",
            "text": "Debit Rp11.000",
            "posted_at": "2026-09-01T10:00:00Z",
        },
    )
    newer_pending = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={
            "package": "com.jago.digitalBanking",
            "title": "Jago",
            "text": "Debit Rp22.000",
            "posted_at": "2026-09-08T10:00:00Z",
        },
    )
    confirmed = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={
            "package": "id.co.bri.brimo",
            "title": "BRImo",
            "text": "Debit Rp33.000",
            "posted_at": "2026-09-09T10:00:00Z",
        },
    )
    rejected = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={
            "package": "id.dana",
            "title": "DANA",
            "text": "Debit Rp44.000",
            "posted_at": "2026-09-10T10:00:00Z",
        },
    )
    await client.post(
        f"/api/v1/bank-inbox/{confirmed.json()['id']}/confirm",
        headers=auth_headers,
        json={},
    )
    await client.post(
        f"/api/v1/bank-inbox/{rejected.json()['id']}/reject",
        headers=auth_headers,
    )
    listed = await client.get("/api/v1/bank-inbox", headers=auth_headers)
    statuses = [i["status"] for i in listed.json()["items"]]
    ids = [i["id"] for i in listed.json()["items"]]
    assert statuses == ["pending", "pending", "confirmed", "rejected"]
    assert ids[0] == newer_pending.json()["id"]
    assert ids[1] == older_pending.json()["id"]


@pytest.mark.asyncio
async def test_delete_inbox_item_keeps_transaction(
    client: AsyncClient, auth_headers: dict
):
    res = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={
            "package": "com.krom.android",
            "title": "Krom",
            "text": "Debit Rp15.000",
            "posted_at": "2026-09-08T10:00:00Z",
        },
    )
    item_id = res.json()["id"]
    confirmed = await client.post(
        f"/api/v1/bank-inbox/{item_id}/confirm",
        headers=auth_headers,
        json={},
    )
    txn_id = confirmed.json()["transaction_id"]
    deleted = await client.delete(
        f"/api/v1/bank-inbox/{item_id}",
        headers=auth_headers,
    )
    assert deleted.status_code == 204, deleted.text
    listed = await client.get("/api/v1/bank-inbox", headers=auth_headers)
    assert all(i["id"] != item_id for i in listed.json()["items"])
    txn = await client.get(f"/api/v1/transactions/{txn_id}", headers=auth_headers)
    assert txn.status_code == 200
    missing = await client.delete(
        f"/api/v1/bank-inbox/{item_id}",
        headers=auth_headers,
    )
    assert missing.status_code == 404


@pytest.mark.asyncio
async def test_rule_suggests_category_on_confirm(client: AsyncClient, auth_headers: dict):
    rule = await client.post(
        "/api/v1/bank-inbox/rules",
        headers=auth_headers,
        json={"bank": "superbank", "keyword": "grab", "category_id": 2},
    )
    assert rule.status_code == 200, rule.text
    listed_rules = await client.get("/api/v1/bank-inbox/rules", headers=auth_headers)
    assert listed_rules.status_code == 200
    assert listed_rules.json()[0]["keyword"] == "grab"

    draft = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={
            "package": "id.co.bankfama.android",
            "title": "Superbank",
            "text": "Debit Rp20.000 QRIS GRAB",
            "posted_at": "2026-09-08T10:00:00Z",
        },
    )
    assert draft.json()["suggested_category_id"] == 2
    confirmed = await client.post(
        f"/api/v1/bank-inbox/{draft.json()['id']}/confirm",
        headers=auth_headers,
        json={},
    )
    txn = await client.get(
        f"/api/v1/transactions/{confirmed.json()['transaction_id']}",
        headers=auth_headers,
    )
    assert txn.json()["category"]["id"] == 2


@pytest.mark.asyncio
async def test_internal_transfer_confirms_pair(client: AsyncClient, auth_headers: dict):
    out_ = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={
            "package": "com.jago.digitalBanking",
            "title": "Jago",
            "text": "Debit Rp75.000 transfer ke BCA",
            "posted_at": "2026-09-08T10:00:00Z",
        },
    )
    inn = await client.post(
        "/api/v1/bank-inbox",
        headers=auth_headers,
        json={
            "package": "com.bca",
            "title": "BCA",
            "text": "Kredit Rp75.000 dari JAGO",
            "posted_at": "2026-09-08T10:02:00Z",
        },
    )
    listed = await client.get("/api/v1/bank-inbox", headers=auth_headers)
    by_id = {i["id"]: i for i in listed.json()["items"]}
    assert by_id[out_.json()["id"]]["internal_suggested"] is True
    assert by_id[out_.json()["id"]]["pair_id"] == inn.json()["id"]
    confirmed = await client.post(
        f"/api/v1/bank-inbox/{out_.json()['id']}/confirm",
        headers=auth_headers,
        json={"internal": True, "pair_id": inn.json()["id"]},
    )
    assert confirmed.status_code == 200, confirmed.text
    listed2 = await client.get("/api/v1/bank-inbox", headers=auth_headers)
    pending = [i for i in listed2.json()["items"] if i["status"] == "pending"]
    assert pending == []
