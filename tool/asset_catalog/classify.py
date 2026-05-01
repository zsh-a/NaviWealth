"""A-share code-prefix classification.

The mainland-China exchanges issue tradable securities under fixed
6-digit code blocks. Mapping a code to (market, asset_type) is purely
mechanical and does not require an upstream API; we keep the rules in
one place so adapters that reach BaoStock vs. mootdx vs. anything else
agree on the same partition.

Type returned matches ``AssetType`` enum names used by ``build.py``
(``stock`` / ``etf`` / ``bond``). Indices, repos and other instruments
that do not belong in the asset catalog return ``None`` so the caller
can skip them.
"""
from __future__ import annotations

MARKET_SH = "sh"
MARKET_SZ = "sz"
MARKET_BJ = "bj"

VALID_MARKETS = frozenset({MARKET_SH, MARKET_SZ, MARKET_BJ})


def classify_a_share(market: str, code: str) -> str | None:
    """Return the asset type for an A-share code, or ``None`` to drop.

    ``market`` must be one of ``sh``, ``sz``, ``bj`` (BaoStock convention).
    ``code`` must be the bare 6-digit ticker (no ``sh.`` / ``sz.`` prefix
    and no exchange suffix).
    """
    if market not in VALID_MARKETS:
        return None
    if not code or len(code) != 6 or not code.isdigit():
        return None

    p1 = code[0]
    p2 = code[:2]
    p3 = code[:3]

    if market == MARKET_SH:
        if p2 in ("60", "68"):
            return "stock"
        if p1 == "5":
            return "etf"
        if p3 in ("110", "113"):
            return "bond"
        return None  # 000xxx / 880xxx index, 2xxxxx STAR depositary, etc.

    if market == MARKET_SZ:
        if p2 in ("00", "30"):
            return "stock"
        if p2 in ("15", "16"):
            return "etf"
        if p2 == "12":
            return "bond"
        return None  # 39xxxx index, etc.

    if market == MARKET_BJ:
        if p2 in ("83", "87", "92"):
            return "stock"
        return None

    return None


def detect_market_from_code(code: str) -> str | None:
    """Best-effort reverse lookup when only the bare code is known.

    Used as a fallback when an upstream feed returns codes without an
    explicit market hint. Ambiguous codes (e.g. ``00xxxx`` could be a
    Shenzhen stock or a Shanghai index) are resolved by picking the
    tradable interpretation; callers that already know the market should
    pass it explicitly to ``classify_a_share`` instead.
    """
    if not code or len(code) != 6 or not code.isdigit():
        return None

    p1 = code[0]
    p2 = code[:2]
    p3 = code[:3]

    if p2 in ("60", "68"):
        return MARKET_SH
    if p2 in ("00", "30"):
        return MARKET_SZ
    if p2 in ("83", "87", "92"):
        return MARKET_BJ
    if p1 == "5":
        return MARKET_SH
    if p2 in ("15", "16"):
        return MARKET_SZ
    if p3 in ("110", "113"):
        return MARKET_SH
    if p2 == "12":
        return MARKET_SZ
    return None
