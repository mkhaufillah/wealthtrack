from app.services.bank_match import find_pair, suggest_category_id


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


def test_pair_opposite_bank_same_amount():
    a = {
        "id": 1,
        "amount": 50000,
        "txn_type": "expense",
        "bank": "jago",
        "status": "pending",
        "posted_at": "2026-09-08T10:00:00Z",
    }
    b = {
        "id": 2,
        "amount": 50000,
        "txn_type": "income",
        "bank": "bca",
        "status": "pending",
        "posted_at": "2026-09-08T10:05:00Z",
    }
    assert find_pair([a, b], a) == 2
    assert find_pair([a, b], b) == 1


def test_pair_same_bank_skipped():
    a = {"id": 1, "amount": 1, "txn_type": "expense", "bank": "jago", "status": "pending", "posted_at": "2026-09-08T10:00:00Z"}
    b = {"id": 2, "amount": 1, "txn_type": "income", "bank": "jago", "status": "pending", "posted_at": "2026-09-08T10:01:00Z"}
    assert find_pair([a, b], a) is None
