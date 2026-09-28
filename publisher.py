from __future__ import annotations

import base64
import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import requests
from requests_oauthlib import OAuth1

GITHUB_API = "https://api.github.com"
SOURCE_REPO = os.environ.get("TANUKI_SOURCE_REPO", "kaz1213-hash/tanuki-growth").strip()
QUEUE_PATH = "tanuki-x/queue"
SOURCE_STATE_PATH = "tanuki-x/state/published.jsonl"
PROMOTER_SPRINT_PATH = "tanuki-x/promoter/EXPOSURE_SPRINT_V0_1.json"
LOCAL_STATE = Path("state/published.jsonl")

POST_API_URL = "https://api.x.com/2/tweets"
MAX_POST_WEIGHT = 280
MAX_POSTS_PER_RUN = 1


@dataclass(frozen=True)
class QueueItem:
    item_id: str
    text: str
    short_text: str
    publish_at: datetime
    product: str
    campaign: str
    has_media: bool


def _require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def _github_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {_require_env('TANUKI_GROWTH_READ_TOKEN')}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "tanuki-x-public-publisher",
    }


def _github_get(path: str, *, allow_404: bool = False):
    url = f"{GITHUB_API}/repos/{SOURCE_REPO}/contents/{path}"
    response = requests.get(url, headers=_github_headers(), timeout=30)
    if allow_404 and response.status_code == 404:
        return None
    if response.status_code < 200 or response.status_code >= 300:
        raise RuntimeError(f"GitHub source read failed: HTTP {response.status_code}")
    return response.json()


def _decode_contents_payload(payload: dict) -> str:
    if not isinstance(payload, dict):
        raise RuntimeError("GitHub content payload was not an object")
    if payload.get("encoding") != "base64":
        raise RuntimeError("GitHub content payload was not base64 encoded")
    raw = payload.get("content")
    if not isinstance(raw, str):
        raise RuntimeError("GitHub content payload had no content")
    return base64.b64decode(raw).decode("utf-8")


def _parse_publish_at(raw: object) -> datetime:
    if not isinstance(raw, str) or not raw.strip():
        raise ValueError("publish_at is required")
    dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        raise ValueError("publish_at must include a timezone offset")
    return dt


def _load_private_queue() -> list[QueueItem]:
    listing = _github_get(QUEUE_PATH)
    if not isinstance(listing, list):
        raise RuntimeError("Private queue listing was not a list")

    items: list[QueueItem] = []
    for entry in listing:
        if not isinstance(entry, dict):
            continue
        name = str(entry.get("name") or "")
        if not name.endswith(".json") or name.endswith(".example"):
            continue
        path = str(entry.get("path") or "")
        payload = _github_get(path)
        data = json.loads(_decode_contents_payload(payload))
        if data.get("status") != "ready":
            continue

        item_id = data.get("id")
        text = data.get("text")
        short_text = data.get("short_text")
        if not isinstance(item_id, str) or not item_id.strip():
            raise ValueError(f"{name}: id is required")
        if not isinstance(text, str) or not text.strip():
            raise ValueError(f"{name}: text is required")
        if short_text is not None and not isinstance(short_text, str):
            raise ValueError(f"{name}: short_text must be a string when present")

        raw_media = data.get("media_paths")
        has_media = bool(raw_media) or bool(data.get("media_path"))
        items.append(
            QueueItem(
                item_id=item_id.strip(),
                text=text.strip(),
                short_text=(short_text or "").strip(),
                publish_at=_parse_publish_at(data.get("publish_at")),
                product=str(data.get("product") or ""),
                campaign=str(data.get("campaign") or ""),
                has_media=has_media,
            )
        )
    return items


def _load_promoter_sprint() -> list[QueueItem]:
    payload = _github_get(PROMOTER_SPRINT_PATH, allow_404=True)
    if payload is None:
        return []
    data = json.loads(_decode_contents_payload(payload))
    if not isinstance(data, dict):
        raise RuntimeError("Promoter sprint payload was not an object")
    if data.get("schema") != "tanuki-promoter-sprint/v0.1":
        raise RuntimeError("Unsupported promoter sprint schema")
    raw_items = data.get("items")
    if not isinstance(raw_items, list):
        raise RuntimeError("Promoter sprint items was not a list")

    items: list[QueueItem] = []
    for index, row in enumerate(raw_items):
        name = f"promoter item #{index + 1}"
        if not isinstance(row, dict):
            raise ValueError(f"{name}: object required")
        if row.get("status") != "ready":
            continue
        item_id = row.get("id")
        text = row.get("text")
        short_text = row.get("short_text")
        if not isinstance(item_id, str) or not item_id.strip():
            raise ValueError(f"{name}: id is required")
        if not isinstance(text, str) or not text.strip():
            raise ValueError(f"{name}: text is required")
        if short_text is not None and not isinstance(short_text, str):
            raise ValueError(f"{name}: short_text must be a string when present")
        if row.get("media_paths") or row.get("media_path"):
            raise ValueError(f"{name}: promoter v0.1 is text-only")
        items.append(
            QueueItem(
                item_id=item_id.strip(),
                text=text.strip(),
                short_text=(short_text or "").strip(),
                publish_at=_parse_publish_at(row.get("publish_at")),
                product=str(row.get("product") or ""),
                campaign=str(row.get("campaign") or ""),
                has_media=False,
            )
        )

    ids = [item.item_id for item in items]
    if len(ids) != len(set(ids)):
        raise ValueError("Promoter sprint contains duplicate item ids")
    return items


def _published_ids_from_jsonl(text: str) -> set[str]:
    ids: set[str] = set()
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        row = json.loads(line)
        item_id = row.get("id")
        if isinstance(item_id, str) and item_id:
            ids.add(item_id)
    return ids


def _load_published_ids() -> set[str]:
    ids: set[str] = set()

    source_state = _github_get(SOURCE_STATE_PATH, allow_404=True)
    if source_state is not None:
        ids |= _published_ids_from_jsonl(_decode_contents_payload(source_state))

    if LOCAL_STATE.exists():
        ids |= _published_ids_from_jsonl(LOCAL_STATE.read_text(encoding="utf-8"))

    return ids


def _text_weight(text: str) -> int:
    return sum(1 if ord(ch) < 128 else 2 for ch in text)


def _trim_to_weight(text: str, max_weight: int = MAX_POST_WEIGHT) -> str:
    if _text_weight(text) <= max_weight:
        return text.strip()
    ellipsis = "…"
    budget = max_weight - _text_weight(ellipsis)
    out: list[str] = []
    used = 0
    for ch in text:
        weight = 1 if ord(ch) < 128 else 2
        if used + weight > budget:
            break
        out.append(ch)
        used += weight
    prefix = "".join(out).rstrip()
    last_space = prefix.rfind(" ")
    if last_space >= max(0, len(prefix) - 24):
        prefix = prefix[:last_space].rstrip()
    return (prefix + ellipsis).strip()


def _prepare_text(item: QueueItem) -> tuple[str, str, int]:
    if _text_weight(item.text) <= MAX_POST_WEIGHT:
        return item.text, "original", _text_weight(item.text)
    if item.short_text and _text_weight(item.short_text) <= MAX_POST_WEIGHT:
        return item.short_text, "short_text", _text_weight(item.short_text)
    source = item.short_text or item.text
    fitted = _trim_to_weight(source)
    return fitted, "auto_fitted", _text_weight(fitted)


def _oauth1() -> OAuth1:
    return OAuth1(
        _require_env("X_API_KEY"),
        _require_env("X_API_SECRET"),
        _require_env("X_ACCESS_TOKEN"),
        _require_env("X_ACCESS_TOKEN_SECRET"),
    )


def _publish_text(text: str) -> tuple[str, str]:
    response = requests.post(
        POST_API_URL,
        json={"text": text},
        auth=_oauth1(),
        timeout=30,
    )
    if response.status_code < 200 or response.status_code >= 300:
        raise RuntimeError(f"X post failed: HTTP {response.status_code}")

    payload = response.json()
    post_id = str(((payload.get("data") or {}).get("id")) or "")
    if not post_id:
        raise RuntimeError("X post succeeded without a post id")
    return post_id, f"https://x.com/i/web/status/{post_id}"


def _append_receipt(item: QueueItem, post_id: str, url: str, text_mode: str, weighted_length: int) -> None:
    LOCAL_STATE.parent.mkdir(parents=True, exist_ok=True)
    row = {
        "id": item.item_id,
        "post_id": post_id,
        "published_at": datetime.now(timezone.utc).isoformat(),
        "url": url,
        "product": item.product,
        "campaign": item.campaign,
        "text_mode": text_mode,
        "weighted_length": weighted_length,
    }
    with LOCAL_STATE.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def main() -> int:
    now = datetime.now(timezone.utc)
    published = _load_published_ids()
    legacy_queue = _load_private_queue()
    promoter_queue = _load_promoter_sprint()
    queue = legacy_queue + promoter_queue
    queue_ids = [item.item_id for item in queue]
    if len(queue_ids) != len(set(queue_ids)):
        raise ValueError("Duplicate queue item id across legacy queue and promoter sprint")

    promoter_due = sorted(
        (
            item
            for item in promoter_queue
            if item.item_id not in published and item.publish_at <= now
        ),
        key=lambda item: (item.publish_at, item.item_id),
    )
    legacy_due = sorted(
        (
            item
            for item in legacy_queue
            if item.item_id not in published and item.publish_at <= now
        ),
        key=lambda item: (item.publish_at, item.item_id),
    )

    # During the bounded Promoter sprint, a due promoter item gets the slot first.
    # This prevents older legacy-ready items from starving the 8/day exposure cadence.
    due = promoter_due if promoter_due else legacy_due

    text_due = [item for item in due if not item.has_media]
    media_blocked = [item for item in due if item.has_media]

    for item in media_blocked:
        print(f"SKIP_MEDIA_UNSUPPORTED: {item.item_id}")

    if not text_due:
        print("NO_DUE_TEXT_POSTS")
        return 0

    for item in text_due[:MAX_POSTS_PER_RUN]:
        text, text_mode, weighted_length = _prepare_text(item)
        post_id, url = _publish_text(text)
        _append_receipt(item, post_id, url, text_mode, weighted_length)
        print(f"POSTED: {item.item_id} -> {url}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
