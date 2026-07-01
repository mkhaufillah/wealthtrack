"""Shared rate limiter — used by main.py and auth endpoints."""

import os

from slowapi import Limiter
from slowapi.util import get_remote_address


def _safe_remote_address(request):
    """Return remote address; fallback to 'test' if request state is missing."""
    try:
        return get_remote_address(request)
    except Exception:
        return "test"


limiter = Limiter(key_func=_safe_remote_address)