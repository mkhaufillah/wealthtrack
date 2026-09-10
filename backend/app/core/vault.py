"""Household vault primitives.

AES-256-GCM for text/ids. OPE for rupiah sort keys (offset keyed by DEK —
leaks order and differences; exact display uses AES). HMAC traces for
category filter. No Redis. Never log DEK.
"""

from __future__ import annotations

import hmac
import os
import hashlib
from base64 import b64decode, b64encode

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

AES_PREFIX = "v1:"
AAD = b"wt-vault-v1"
OPE_INFO = b"wt-ope-v1-offset"


def generate_dek() -> bytes:
    return os.urandom(32)


def parse_dek(raw: str | None) -> bytes:
    if not raw or not str(raw).strip():
        raise ValueError("vault key missing")
    try:
        dek = b64decode(str(raw).strip())
    except Exception as e:
        raise ValueError("vault key invalid") from e
    if len(dek) != 32:
        raise ValueError("vault key invalid")
    return dek


def encode_dek(dek: bytes) -> str:
    if len(dek) != 32:
        raise ValueError("dek must be 32 bytes")
    return b64encode(dek).decode("ascii")


def aes_encrypt(dek: bytes, plaintext: str) -> str:
    nonce = os.urandom(12)
    ct = AESGCM(dek).encrypt(nonce, plaintext.encode("utf-8"), AAD)
    return AES_PREFIX + b64encode(nonce + ct).decode("ascii")


def aes_decrypt(dek: bytes, token: str) -> str:
    if not token.startswith(AES_PREFIX):
        raise ValueError("not vault ciphertext")
    raw = b64decode(token[len(AES_PREFIX) :])
    nonce, ct = raw[:12], raw[12:]
    return AESGCM(dek).decrypt(nonce, ct, AAD).decode("utf-8")


def is_aes_token(value: str | None) -> bool:
    return isinstance(value, str) and value.startswith(AES_PREFIX)


def ope_offset(dek: bytes) -> int:
    digest = hmac.new(dek, OPE_INFO, hashlib.sha256).digest()
    return int.from_bytes(digest[:6], "big")


def ope_encode(dek: bytes, amount: int) -> int:
    if not isinstance(amount, int) or amount < 0:
        raise ValueError("amount must be a non-negative int")
    return amount + ope_offset(dek)


def ope_decode(dek: bytes, ordered: int) -> int:
    return int(ordered) - ope_offset(dek)


def category_trace(dek: bytes, category_id: int) -> str:
    msg = f"cat:{int(category_id)}".encode("ascii")
    return hmac.new(dek, msg, hashlib.sha256).hexdigest()


def word_trace(dek: bytes, token: str) -> str:
    norm = " ".join(token.lower().split())
    return hmac.new(dek, f"w:{norm}".encode("utf-8"), hashlib.sha256).hexdigest()
