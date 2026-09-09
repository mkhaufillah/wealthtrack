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
