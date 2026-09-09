from app.services.bank_parser import (
    BANK_PACKAGES,
    bank_for_package,
    fingerprint,
    parse_amount,
    has_amount,
    parse_merchant,
    parse_notification,
    parse_type,
)


def test_package_allow_list():
    assert bank_for_package("com.bca") == "bca"
    assert bank_for_package("id.bmri.livin") == "mandiri"
    assert bank_for_package("id.co.bri.brimo") == "bri"
    assert bank_for_package("com.jago.digitalBanking") == "jago"
    assert bank_for_package("id.co.bankfama.android") == "superbank"
    assert bank_for_package("com.krom.android") == "krom"
    assert bank_for_package("id.dana") == "dana"
    assert bank_for_package("com.gojek.gopay") == "gopay"
    assert bank_for_package("ovo.id") == "ovo"
    assert bank_for_package("com.whatsapp") == "whatsapp"


def test_required_packages_complete():
    required = {
        "com.bibit.bibitid",
        "com.bca",
        "id.co.bankfama.android",
        "com.jago.digitalBanking",
        "id.co.bri.brimo",
        "id.bmri.livin",
        "id.co.btn.mobilebanking.android",
        "com.telkom.mwallet",
        "id.flip",
        "ovo.id",
        "com.stockbit.android",
        "com.gojek.gopay",
        "id.dana",
        "com.krom.android",
        "com.shopeepay.id",
        "id.co.bankbkemobile.digitalbank",
    }
    assert required == set(BANK_PACKAGES)


def test_amount_rp_dotted():
    assert parse_amount("Debit Rp50.000 di QRIS GRAB") == 50000
    assert parse_amount("Rp 1.250.000") == 1250000
    assert parse_amount("IDR 75000") == 75000


def test_amount_missing():
    assert parse_amount("Transaksi berhasil") is None
    assert parse_amount("Diskon 50%") is None
    assert parse_amount("0812.345.678") is None


def test_amount_dollar_and_comma():
    assert parse_amount("Paid $12.50") == 12
    assert parse_amount("USD 1,250.00") == 1250
    assert parse_amount("US$20") == 20
    assert parse_amount("amount 10,000") == 10000


def test_amount_wider_formats():
    assert parse_amount("Rp10.000,-") == 10000
    assert parse_amount("10000 rupiah") == 10000
    assert parse_amount("Debit 25000") == 25000
    assert parse_amount("IDR 75 000") == 75000
    assert parse_amount("50,000") == 50000
    assert has_amount("Debit Rp50.000") is True
    assert has_amount("Promo tanpa angka") is False


def test_type_debit_vs_kredit():
    assert parse_type("Debit Rp10.000 QRIS") == "expense"
    assert parse_type("Kredit Rp2.000.000 gaji") == "income"
    assert parse_type("Transfer masuk Rp100.000") == "income"
    assert parse_type("QRIS Superbank Grab") == "expense"
    assert parse_type("Kamu berhasil pindahin Rp100,00 ke Food and Drinks") == "expense"
    assert parse_type("Transfer ke BCA Rp50.000") == "expense"
    assert parse_type("Dana masuk Rp75.000 dari Jago") == "income"
    assert parse_type("Kartu kredit tagihan") == "expense"


def test_merchant_after_di():
    assert "GRAB" in parse_merchant("Debit Rp50.000 di QRIS GRAB").upper()


def test_parse_jago_and_bca():
    bca = parse_notification(
        "com.bca", "BCA", "Debit Rp125.000 di ALFAMART"
    )
    assert bca["bank"] == "bca"
    assert bca["amount"] == 125000
    assert bca["type"] == "expense"
    assert bca["parsed"] is True

    jago = parse_notification(
        "com.jago.digitalBanking",
        "Jago",
        "Dana masuk Rp500.000 dari NAHDA",
    )
    assert jago["bank"] == "jago"
    assert jago["amount"] == 500000
    assert jago["type"] == "income"


def test_fingerprint_stable():
    a = fingerprint("com.bca", "2026-09-08T10:00:00Z", 50000, "Debit Rp50.000")
    b = fingerprint("com.bca", "2026-09-08T11:00:00Z", 50000, "Debit  Rp50.000")
    assert a == b
