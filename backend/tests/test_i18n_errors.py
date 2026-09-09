from app.core.i18n import error_body, locale_from_request


def test_error_body_english_credentials():
    body = error_body("en-US", "Username atau password salah")
    assert body["code"] == "err.credentials"
    assert body["detail"] == "Wrong username or password"


def test_error_body_id_generic():
    body = error_body("id-ID", "err.generic")
    assert body["code"] == "err.generic"
    assert "beres" in body["detail"]


def test_locale_from_x_locale():
    assert locale_from_request({"x-locale": "en"}) == "en-US"


def test_otp_email_copy_follows_locale():
    from app.core.email import otp_email_copy

    subj_id, body_id = otp_email_copy("123456", "id-ID")
    assert "Kode verifikasi" in subj_id
    assert "123456" in body_id
    assert "{otp}" not in body_id

    subj_en, body_en = otp_email_copy("123456", "en-US")
    assert "Verification code" in subj_en
    assert "123456" in body_en
    assert "{otp}" not in body_en
