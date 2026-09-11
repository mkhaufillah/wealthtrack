"""Guardrail: test schema (conftest.SCHEMA_SQL) must match production.

The prod schema is snapshotted in schema_prod_snapshot.txt (generated from
`information_schema.columns` on the production database). Vault refactors
drop plaintext columns; forgetting to mirror that in the test schema makes
tests exercise a different reality than prod.

When the prod schema changes intentionally, regenerate the snapshot:
    psql -d wealthtrack -t -A -c \\
      "SELECT table_name || '|' || column_name FROM information_schema.columns
       WHERE table_schema='public' ORDER BY table_name, ordinal_position;" \\
      > backend/tests/schema_prod_snapshot.txt
"""

import re
from pathlib import Path

_SNAPSHOT = Path(__file__).resolve().parent / "schema_prod_snapshot.txt"
_CONFTEST = Path(__file__).resolve().parent / "conftest.py"

_COL = re.compile(r"^\s{4}(\w+)\s+(SERIAL|TEXT|INTEGER|BIGINT|JSONB|TIMESTAMPTZ|TEXT\[\])", re.M)


def _snapshot_tables() -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for line in _SNAPSHOT.read_text().splitlines():
        line = line.strip()
        if not line or "|" not in line:
            continue
        table, col = line.split("|", 1)
        out.setdefault(table, set()).add(col)
    return out


def _conftest_tables() -> dict[str, set[str]]:
    text = _CONFTEST.read_text()
    out: dict[str, set[str]] = {}
    for name in re.findall(r"CREATE TABLE (?:IF NOT EXISTS )?(?:\w+\.)?(\w+)\s*\(", text):
        block = re.search(
            r"CREATE TABLE (?:IF NOT EXISTS )?(?:\w+\.)?" + re.escape(name) + r"\s*\((.*?)\)\s*;",
            text,
            re.S,
        )
        if block:
            out[name] = {col for col, _ in _COL.findall(block.group(1))}
    return out


def test_conftest_matches_prod_snapshot():
    prod = _snapshot_tables()
    test = _conftest_tables()

    assert set(prod) == set(test), (
        "table drift: only-in-prod="
        f"{sorted(set(prod) - set(test))} "
        f"only-in-conftest={sorted(set(test) - set(prod))}"
    )

    drift = {
        table: (sorted(prod[table] - test[table]), sorted(test[table] - prod[table]))
        for table in prod
        if prod[table] != test[table]
    }
    assert not drift, f"column drift: {drift}"