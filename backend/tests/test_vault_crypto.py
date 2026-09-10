"""Vault primitives: AES-GCM, OPE order, category traces."""

from app.core.vault import (
    aes_decrypt,
    aes_encrypt,
    category_trace,
    generate_dek,
    ope_decode,
    ope_encode,
    parse_dek,
)
from app.core.vault_row import ope_sum_to_plain


def test_aes_roundtrip():
    dek = generate_dek()
    ct = aes_encrypt(dek, "Indomaret 50rb")
    assert "Indomaret" not in ct
    assert aes_decrypt(dek, ct) == "Indomaret 50rb"


def test_aes_wrong_key_fails():
    dek = generate_dek()
    other = generate_dek()
    ct = aes_encrypt(dek, "secret")
    try:
        aes_decrypt(other, ct)
    except Exception:
        return
    raise AssertionError("expected decrypt failure")


def test_ope_preserves_order():
    dek = generate_dek()
    a, b, c = 10_000, 50_000, 80_000
    oa, ob, oc = ope_encode(dek, a), ope_encode(dek, b), ope_encode(dek, c)
    assert oa < ob < oc
    assert ope_decode(dek, ob) == b


def test_ope_different_households_not_same():
    d1, d2 = generate_dek(), generate_dek()
    assert ope_encode(d1, 50_000) != ope_encode(d2, 50_000)


def test_category_trace_stable_and_keyed():
    dek = generate_dek()
    t7 = category_trace(dek, 7)
    assert t7 == category_trace(dek, 7)
    assert t7 != category_trace(dek, 1)
    assert t7 != category_trace(generate_dek(), 7)


def test_ope_sum_homomorphic():
    dek = generate_dek()
    amounts = [10_000, 50_000, 80_000]
    s_ord = sum(ope_encode(dek, a) for a in amounts)
    assert ope_sum_to_plain(dek, s_ord, len(amounts)) == sum(amounts)


def test_parse_dek_rejects_short():
    try:
        parse_dek("dG9vLXNob3J0")
    except ValueError:
        return
    raise AssertionError("expected ValueError")


def test_pack_extra_roundtrip():
    from app.core.vault_row import pack_money, unpack_money

    dek = generate_dek()
    packed = pack_money(
        dek,
        amount=12_000_000,
        extra={"name": "KPR rumah", "property_price": 12_000_000},
    )
    row = unpack_money(dek, packed)
    assert row["amount"] == 12_000_000
    assert row["name"] == "KPR rumah"


def test_pack_negative_amount_still_encrypts():
    from app.core.vault_row import pack_money, unpack_money

    dek = generate_dek()
    packed = pack_money(dek, amount=-1, extra={"remaining_balance": -1})
    assert packed["amount"] == 0
    assert packed["amount_ord"] == ope_encode(dek, 0)
    row = unpack_money(dek, packed)
    assert row["amount"] == -1
    assert row["remaining_balance"] == -1
