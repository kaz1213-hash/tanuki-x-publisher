"""Verify exact Director-approved text for autonomous X publisher (no signing here)."""
from __future__ import annotations

import hashlib
import hmac
import json
import os
from datetime import datetime, timedelta, timezone
from typing import Any

ENV_KEY = "TANUKI_MEDIA_APPROVAL_HMAC_KEY"
SCHEMA = "tanuki-media-director-approval/v1"
PROTECTED = {"auto-mine-story", "media-lab-story"}


class Unapproved(ValueError):
    pass


def needs_approval(data: dict[str, Any], *, promoter: bool = False) -> bool:
    return promoter or data.get("auto_generated") is True or data.get("campaign") in PROTECTED


def _content_digest(data: dict[str, Any]) -> str:
    if data.get("media_paths") or data.get("media_path"):
        raise Unapproved("media not supported by text publisher")
    if not isinstance(data.get("id"), str) or not data["id"].strip():
        raise Unapproved("missing item id")
    if not isinstance(data.get("text"), str) or not data["text"].strip():
        raise Unapproved("missing original text")
    if any(data.get(flag) is True for flag in ("automated_reply", "automated_like", "automated_follow", "automated_dm")):
        raise Unapproved("third-party engagement not permitted")
    fields = {
        "id": data["id"], "text": data["text"],
        "short_text": data.get("short_text") or "",
        "campaign": data.get("campaign") or "",
        "product": data.get("product") or "",
        "source_ref": data.get("source_ref") or "",
        "source_ore_id": data.get("source_ore_id") or "",
        "media": [], "channel": "x",
    }
    return hashlib.sha256(json.dumps(fields, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def require_approved(data: dict[str, Any], *, promoter: bool = False,
                     secret: str | None = None, now: datetime | None = None) -> None:
    if not needs_approval(data, promoter=promoter):
        return
    receipt = data.get("director_approval")
    if not isinstance(receipt, dict):
        raise Unapproved("missing explicit Director approval")
    keys = ("schema", "item_id", "content_sha256", "channel", "actor", "decision_ref", "approved_at")
    if receipt.get("schema") != SCHEMA or receipt.get("channel") != "x" or receipt.get("actor") != "Director":
        raise Unapproved("approval source invalid")
    if receipt.get("item_id") != data.get("id") or receipt.get("content_sha256") != _content_digest(data):
        raise Unapproved("approved content changed")
    if not isinstance(receipt.get("decision_ref"), str) or not receipt["decision_ref"].strip():
        raise Unapproved("missing decision evidence")
    try:
        stamp = datetime.fromisoformat(str(receipt["approved_at"]).replace("Z", "+00:00"))
    except (ValueError, KeyError, TypeError) as exc:
        raise Unapproved("invalid approval time") from exc
    current = now or datetime.now(timezone.utc)
    if stamp.tzinfo is None or current.tzinfo is None or not timedelta(minutes=-5) <= current - stamp <= timedelta(days=30):
        raise Unapproved("approval expired or invalid time")
    token = secret if secret is not None else os.getenv(ENV_KEY, "")
    if not token or len(token.encode()) < 32:
        raise Unapproved("trusted verifier missing")
    data_to_sign = json.dumps({k: receipt.get(k) for k in keys}, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
    expected = hmac.new(token.encode(), data_to_sign, hashlib.sha256).hexdigest()
    if not isinstance(receipt.get("signature"), str) or not hmac.compare_digest(receipt["signature"], expected):
        raise Unapproved("approval signature invalid")
