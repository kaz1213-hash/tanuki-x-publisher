"""Director-approved Tanuki Media Lab X transport. Existing Actions job; no new scheduler."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import subprocess
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests
from requests_oauthlib import OAuth1

GROWTH_REPO = "kaz1213-hash/tanuki-growth"
APPROVAL_PATH = "tanuki-x/media-lab/x_approved_queue.json"
PRIVATE_RECEIPTS = "tanuki-x/state/published.jsonl"
PUBLIC_RECEIPTS = Path("state/published.jsonl")
ATTEMPTS_DIR = Path("state/attempts")
API = "https://api.x.com/2"
HANDLE = "TanukiBySCA"
SCHEMA = "tanuki-media-lab-x-approved/v1"
ID_PATTERN = re.compile(r"^TML-X-SHORT-[0-9]{8}-[A-Z0-9-]+$")


def _github_read(path: str, *, allow_missing: bool = False) -> str | None:
    token = os.environ["TANUKI_GROWTH_READ_TOKEN"]
    response = requests.get(
        f"https://api.github.com/repos/{GROWTH_REPO}/contents/{path}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"},
        timeout=25,
    )
    if allow_missing and response.status_code == 404:
        return None
    if response.status_code != 200:
        raise RuntimeError(f"PRIVATE_SOURCE_UNAVAILABLE HTTP_{response.status_code}")
    value = response.json()
    if not isinstance(value, dict) or value.get("encoding") != "base64":
        raise RuntimeError("PRIVATE_SOURCE_INVALID")
    return base64.b64decode(value["content"]).decode("utf-8")


def _read_receipts(raw: str) -> list[dict]:
    rows = []
    for line in raw.splitlines():
        if line.strip():
            item = json.loads(line)
            if not isinstance(item, dict) or not item.get("id"):
                raise RuntimeError("INVALID_RECEIPT")
            rows.append(item)
    return rows


def _now_jst(dt: datetime) -> str:
    return dt.astimezone(timezone(timedelta(hours=9))).date().isoformat()


def _iso(raw: str) -> datetime:
    d = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    if d.tzinfo is None:
        raise ValueError("TIMEZONE_REQUIRED")
    return d


def _approved_item(raw: dict) -> dict:
    if (not isinstance(raw, dict) or raw.get("status") != "APPROVED"
        or raw.get("director_approved") is not True or raw.get("network") != "twitter"
        or raw.get("media_count") != 0 or not raw.get("approval_id")):
        raise ValueError("NOT_DIRECTOR_APPROVED")
    item_id, caption = raw.get("id"), raw.get("text")
    if not isinstance(item_id, str) or not ID_PATTERN.fullmatch(item_id):
        raise ValueError("INVALID_MEDIA_LAB_ID")
    if not isinstance(caption, str) or caption != caption.strip() or not caption:
        raise ValueError("INVALID_EXACT_CAPTION")
    if re.search(r"https?://|www\.", caption, re.I):
        raise ValueError("CAPTION_URL_NOT_ALLOWED")
    if sum(1 if ord(c) < 128 else 2 for c in caption) > 280:
        raise ValueError("CAPTION_OVER_280_WEIGHT")
    sha = hashlib.sha256(caption.encode("utf-8")).hexdigest()
    if sha != raw.get("caption_sha256"):
        raise ValueError("CAPTION_HASH_NOT_APPROVED")
    _iso(raw["not_before"])
    return raw


def _oauth():
    return OAuth1(
        os.environ["X_API_KEY"], os.environ["X_API_SECRET"],
        os.environ["X_ACCESS_TOKEN"], os.environ["X_ACCESS_TOKEN_SECRET"],
    )


def _get_x(url: str, auth: OAuth1, params=None) -> dict:
    response = requests.get(url, auth=auth, params=params, timeout=25)
    if response.status_code != 200:
        raise RuntimeError(f"X_READ_UNAVAILABLE_HTTP_{response.status_code}")
    result = response.json()
    if not isinstance(result, dict):
        raise RuntimeError("X_READ_INVALID")
    return result


def _live_timeline(auth: OAuth1) -> list[dict]:
    me = _get_x(f"{API}/users/me", auth).get("data") or {}
    if me.get("username", "").lower() != HANDLE.lower() or not str(me.get("id", "")).isdigit():
        raise RuntimeError("X_ACCOUNT_MISMATCH")
    timeline = _get_x(
        f"{API}/users/{me['id']}/tweets",
        auth, {"max_results": 10, "tweet.fields": "created_at"},
    )
    tweets = timeline.get("data")
    if not isinstance(tweets, list) or not tweets:
        raise RuntimeError("X_TIMELINE_EMPTY_OR_UNAVAILABLE")
    clean = []
    for t in tweets:
        if not isinstance(t, dict) or not str(t.get("id", "")).isdigit() or not isinstance(t.get("text"), str):
            raise RuntimeError("X_TIMELINE_INVALID")
        if not isinstance(t.get("created_at"), str):
            raise RuntimeError("X_TIMESTAMP_MISSING")
        _iso(t["created_at"])
        clean.append(t)
    return clean


def _save_receipt(item: dict, tweet: dict) -> None:
    row = {
        "id": item["id"], "post_id": str(tweet["id"]),
        "published_at": tweet["created_at"],
        "url": f"https://x.com/{HANDLE}/status/{tweet['id']}",
        "product": "Tanuki Media Lab", "campaign": "research-lab-witty-short",
        "text_mode": "director_approved_short", "media_count": 0,
        "caption_sha256": item["caption_sha256"], "approval_id": item["approval_id"],
        "verified_from": "X_API_AUTHENTICATED_TIMELINE",
    }
    PUBLIC_RECEIPTS.parent.mkdir(parents=True, exist_ok=True)
    with PUBLIC_RECEIPTS.open("a", encoding="utf-8") as out:
        out.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"X_PUBLISHED_VERIFIED {row['url']}")


def _reserve_once(item: dict) -> None:
    marker = ATTEMPTS_DIR / (item["id"] + ".json")
    if marker.exists():
        raise RuntimeError("PRIOR_ATTEMPT_UNRESOLVED_NO_REPOST")
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(json.dumps({
        "id": item["id"], "caption_sha256": item["caption_sha256"],
        "state": "ATTEMPT_RESERVED_NO_AUTOMATIC_RETRY",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }, ensure_ascii=False) + "\n", encoding="utf-8")
    # Public, metadata-only reservation. A failed commit or push MUST abort before X POST.
    for args in [
        ["git", "add", "--", str(marker)],
        ["git", "-c", "user.name=tanuki-x-free-publisher",
         "-c", "user.email=actions@users.noreply.github.com", "commit",
         "-m", f"Reserve exact-once X intent {item['id']} [skip ci]", "--", str(marker)],
        ["git", "push", "origin", "HEAD:main"],
    ]:
        subprocess.run(args, check=True, capture_output=True, text=True)


def run() -> int:
    now = datetime.now(timezone.utc)
    raw = _github_read(APPROVAL_PATH, allow_missing=True)
    if raw is None:
        print("NO_PRIVATE_DIRECTOR_APPROVED_QUEUE; legacy automated X queue HOLD")
        return 0
    doc = json.loads(raw)
    if not isinstance(doc, dict) or doc.get("schema") != SCHEMA:
        raise RuntimeError("APPROVAL_SCHEMA_INVALID")
    # X API is metered. Never spend credits or trigger a top-up without an explicit, verified prepaid-use gate.
    if doc.get("allow_prepaid_api_usage") is not True:
        print("PAID_X_API_NOT_AUTHORIZED_HOLD")
        return 0
    items = [_approved_item(x) for x in doc.get("items", [])]
    ids = [x["id"] for x in items]
    if len(set(ids)) != len(ids):
        raise RuntimeError("DUPLICATE_APPROVAL_ID")
    if not PUBLIC_RECEIPTS.exists():
        raise RuntimeError("PUBLIC_RECEIPTS_MISSING")
    local_rows = _read_receipts(PUBLIC_RECEIPTS.read_text(encoding="utf-8"))
    private_raw = _github_read(PRIVATE_RECEIPTS)
    private_rows = _read_receipts(private_raw)
    union = local_rows + private_rows
    published_ids = {x["id"] for x in union}
    day = _now_jst(now)
    if any(x.get("published_at") and _now_jst(_iso(x["published_at"])) == day for x in union):
        print("DAY_LIMIT_FROM_LEDGER_HOLD")
        return 0
    due = sorted(
        (x for x in items if x["id"] not in published_ids and _iso(x["not_before"]) <= now),
        key=lambda x: (x["not_before"], x["id"]),
    )
    if not due:
        print("NO_DUE_APPROVED_SHORTS")
        return 0
    item = due[0]
    auth = _oauth()
    tweets = _live_timeline(auth)
    previous = [
        x for x in union
        if x.get("post_id") and x.get("published_at")
        and _iso(x["published_at"]) >= now - timedelta(days=7)
    ]
    known_ids = {str(x["post_id"]) for x in previous}
    observed_ids = {str(x["id"]) for x in tweets}
    if known_ids and not (known_ids & observed_ids):
        raise RuntimeError("LIVE_TIMELINE_INCOMPLETE_RELATIVE_TO_LEDGER")
    matches = [x for x in tweets if x["text"] == item["text"]]
    if len(matches) > 1:
        raise RuntimeError("X_DUPLICATE_CONTENT_AMBIGUOUS")
    if len(matches) == 1:
        _save_receipt(item, matches[0])
        print("RECONCILED_WITHOUT_REPOST")
        return 0
    if any(_now_jst(_iso(x["created_at"])) == day for x in tweets):
        print("DAY_LIMIT_FROM_LIVE_X_HOLD")
        return 0
    if (ATTEMPTS_DIR / (item["id"] + ".json")).exists():
        raise RuntimeError("PREVIOUS_ATTEMPT_UNKNOWN_NO_REPOST")
    _reserve_once(item)
    # Once reserved, absolutely no automatic second POST, including after HTTP timeout.
    response = requests.post(
        f"{API}/tweets", json={"text": item["text"]}, auth=auth, timeout=30,
    )
    if response.status_code not in range(200, 300):
        raise RuntimeError(f"X_POST_UNCERTAIN_NO_RETRY_HTTP_{response.status_code}")
    new_id = str((response.json().get("data") or {}).get("id") or "")
    if not new_id.isdigit():
        raise RuntimeError("X_POST_RESULT_AMBIGUOUS_NO_RETRY")
    time.sleep(3)
    live = _live_timeline(auth)
    found = [x for x in live if str(x["id"]) == new_id and x["text"] == item["text"]]
    if len(found) != 1:
        raise RuntimeError("X_POST_READBACK_NOT_CONFIRMED_NO_RETRY")
    _save_receipt(item, found[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
