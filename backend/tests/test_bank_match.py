from app.services.bank_match import suggest_category_id


def test_first_matching_category_wins():
    cats = [
        {"id": 1, "type": "expense", "keywords": '["qris"]'},
        {"id": 2, "type": "expense", "keywords": '["grab"]'},
    ]
    assert suggest_category_id(cats, "QRIS GRAB", "expense") == 1


def test_keywords_fallback():
    cats = [{"id": 3, "type": "expense", "keywords": '["alfamart"]'}]
    assert suggest_category_id(cats, "Debit di Alfamart", "expense") == 3


def test_wrong_type_ignored():
    cats = [{"id": 3, "type": "income", "keywords": '["gaji"]'}]
    assert suggest_category_id(cats, "gaji masuk", "expense") is None


def test_keyword_uses_word_boundary():
    cats = [{"id": 11, "type": "expense", "keywords": '["erha"]'}]
    assert suggest_category_id(cats, "pemindahan uang berhasil ke Food", "expense") is None
    assert suggest_category_id(cats, "Bayar ke ERHA Senayan", "expense") == 11
    assert suggest_category_id(cats, "QRIS grabfood", "expense") is None
    cats2 = [{"id": 6, "type": "expense", "keywords": '["grabfood"]'}]
    assert suggest_category_id(cats2, "QRIS grabfood", "expense") == 6
