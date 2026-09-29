from __future__ import annotations

import base64
import hashlib
import json
import math
import os
from datetime import datetime, timezone
from pathlib import Path

import requests

GITHUB_API = "https://api.github.com"
SOURCE_REPO = os.environ.get("TANUKI_SOURCE_REPO", "kaz1213-hash/tanuki-growth").strip()
CONFIG_PATH = "tanuki-x/scout/SCOUT_CONFIG_V0_2.json"
SEARCH_URL = "https://api.x.com/2/tweets/search/recent"
BEARER_URL = "https://api.x.com/oauth2/token"

STATE_DIR = Path(os.environ.get("TANUKI_SCOUT_STATE_DIR", "state"))
CANDIDATE_STATE = STATE_DIR / "scout_candidates_v03.jsonl"
MARKET_STATE = STATE_DIR / "market_signals.jsonl"


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
        "User-Agent": "tanuki-x-scout",
    }


def _github_get(path: str) -> dict:
    url = f"{GITHUB_API}/repos/{SOURCE_REPO}/contents/{path}"
    response = requests.get(url, headers=_github_headers(), timeout=30)
    if response.status_code < 200 or response.status_code >= 300:
        raise RuntimeError(f"GitHub source read failed: HTTP {response.status_code}")
    payload = response.json()
    if not isinstance(payload, dict) or payload.get("encoding") != "base64":
        raise RuntimeError("GitHub config payload was not a base64 content object")
    return payload


def _decode_content(payload: dict) -> str:
    raw = payload.get("content")
    if not isinstance(raw, str):
        raise RuntimeError("GitHub config payload had no content")
    return base64.b64decode(raw).decode("utf-8")


def _load_config() -> dict:
    data = json.loads(_decode_content(_github_get(CONFIG_PATH)))
    if not isinstance(data, dict) or data.get("schema") != "tanuki-scout/v0.2":
        raise RuntimeError("Unsupported Tanuki Scout config")
    return data


def _app_bearer() -> str:
    response = requests.post(
        BEARER_URL,
        auth=(_require_env("X_API_KEY"), _require_env("X_API_SECRET")),
        data={"grant_type": "client_credentials"},
        timeout=30,
    )
    if response.status_code < 200 or response.status_code >= 300:
        raise RuntimeError(f"X app-only auth failed: HTTP {response.status_code}")
    token = str((response.json() or {}).get("access_token") or "").strip()
    if not token:
        raise RuntimeError("X app-only auth returned no access token")
    return token


def _search_recent(bearer: str, query: str, *, max_results: int = 50) -> dict:
    response = requests.get(
        SEARCH_URL,
        headers={"Authorization": f"Bearer {bearer}"},
        params={
            "query": query,
            "max_results": max(10, min(max_results, 100)),
            "tweet.fields": "id,text,author_id,created_at,public_metrics,lang,conversation_id",
            "expansions": "author_id",
            "user.fields": "id,username,name,verified,public_metrics",
        },
        timeout=30,
    )
    if response.status_code < 200 or response.status_code >= 300:
        raise RuntimeError(f"X recent search failed: HTTP {response.status_code}")
    payload = response.json()
    if not isinstance(payload, dict):
        raise RuntimeError("X recent search returned non-object JSON")
    return payload


def _casefold(value: object) -> str:
    return str(value or "").casefold()


def _contains_any(text: str, phrases: list[object]) -> list[str]:
    body = _casefold(text)
    hits: list[str] = []
    for phrase in phrases:
        value = str(phrase or "").strip()
        if value and _casefold(value) in body:
            hits.append(value)
    return hits


def _thread_relevant(text: str, config: dict) -> bool:
    relevance = config.get("relevance") or {}
    off_topic = _contains_any(text, relevance.get("off_topic_any") or [])
    if not off_topic:
        return True
    builder_hits = _contains_any(text, relevance.get("generic_builder_any") or [])
    return bool(builder_hits)


def _product_fit(text: str, product_key: str, config: dict) -> tuple[int, list[str]]:
    relevance = config.get("relevance") or {}
    product_cfg = ((relevance.get("product_affinity") or {}).get(product_key) or {})
    hits = _contains_any(text, product_cfg.get("terms") or [])
    score = len(set(_casefold(hit) for hit in hits)) * 2
    if _contains_any(text, relevance.get("generic_builder_any") or []):
        score += int(product_cfg.get("generic_bias") or 0)
    return score, hits


def _invitation_gate(text: str, language: str, config: dict) -> bool:
    gate = config.get("invitation_gate") or {}
    body = _casefold(text)
    for phrase in gate.get("reject_any") or []:
        if _casefold(phrase) in body:
            return False
    key = "require_any_ja" if language == "ja" else "require_any_en"
    phrases = gate.get(key) or []
    return any(_casefold(phrase) in body for phrase in phrases)


def _parse_created_at(raw: object) -> datetime | None:
    if not isinstance(raw, str) or not raw.strip():
        return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        return None
    return dt.astimezone(timezone.utc)


def _metrics(post: dict) -> dict[str, int]:
    raw = post.get("public_metrics")
    if not isinstance(raw, dict):
        raw = {}
    keys = ("reply_count", "like_count", "retweet_count", "quote_count")
    return {key: int(raw.get(key) or 0) for key in keys}


def _score(post: dict, user: dict | None = None) -> float:
    m = _metrics(post)
    score = (
        m["reply_count"] * 3.0
        + m["like_count"] * 1.0
        + m["retweet_count"] * 2.0
        + m["quote_count"] * 2.0
    )
    followers = 0
    if isinstance(user, dict):
        pm = user.get("public_metrics")
        if isinstance(pm, dict):
            followers = int(pm.get("followers_count") or 0)
    if followers > 0:
        score += min(12.0, math.log10(followers + 1) * 2.0)
    return round(score, 2)


def _user_map(payload: dict) -> dict[str, dict]:
    out: dict[str, dict] = {}
    includes = payload.get("includes")
    if not isinstance(includes, dict):
        return out
    for user in includes.get("users") or []:
        if isinstance(user, dict) and user.get("id"):
            out[str(user["id"])] = user
    return out


def _known_ids(path: Path, key: str) -> set[str]:
    if not path.exists():
        return set()
    out: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        value = row.get(key)
        if value:
            out.add(str(value))
    return out


def _append_rows(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def _draft_for(post_id: str, language: str, text: str, config: dict) -> tuple[str, str, str, int, str] | None:
    products = [
        row for row in (config.get("draft_products") or [])
        if isinstance(row, dict) and language in (row.get("languages") or [])
    ]
    if not products:
        raise RuntimeError(f"No draft products configured for language={language}")

    relevance = config.get("relevance") or {}
    scored: list[tuple[int, str, dict, list[str]]] = []
    for product in products:
        key = str(product.get("key") or "")
        if relevance:
            fit, hits = _product_fit(text, key, config)
        else:
            fit, hits = 1, []
        scored.append((fit, key, product, hits))

    scored.sort(key=lambda row: (-row[0], row[1]))
    fit, product_key, product, hits = scored[0]
    min_fit = int((config.get("limits") or {}).get("min_product_fit") or (1 if relevance else 0))
    if fit < min_fit:
        return None

    digest = int(hashlib.sha256(post_id.encode("utf-8")).hexdigest(), 16)
    drafts = ((product.get("drafts") or {}).get(language) or [])
    if not drafts:
        raise RuntimeError("Selected draft product has no compatible draft")
    base = str(drafts[digest % len(drafts)]).strip()
    intros = {
        "en": [
            "Thanks for opening the thread — dropping one:",
            "One project for the thread:",
            "Adding one small build here:",
            "Here is one from the Tanuki pile:",
        ],
        "ja": [
            "スレお借りします。ひとつ投下します。",
            "ひとつ作品を置かせてください。",
            "作ったものを一つ。",
            "タヌキ棚から一つ置いていきます。🦝",
        ],
    }
    intro = intros[language][(digest // 17) % len(intros[language])]
    if language == "ja":
        url = str(product.get("url_ja") or product.get("url") or "").strip()
    else:
        url = str(product.get("url_en") or product.get("url") or "").strip()
    reply = f"{intro}\n\n{base}"
    if url:
        reply += f"\n\n{url}"

    if hits:
        reason = " / ".join(hits[:4])
    elif _contains_any(text, relevance.get("generic_builder_any") or []):
        reason = "generic builder / product thread"
    else:
        reason = "explicit promotion thread"
    return product_key, str(product.get("name") or ""), reply, fit, reason

def _post_url(username: str, post_id: str) -> str:
    if username:
        return f"https://x.com/{username}/status/{post_id}"
    return f"https://x.com/i/web/status/{post_id}"


def _collect_invitation_candidates(payload: dict, language: str, config: dict, known: set[str], now: datetime) -> list[dict]:
    limits = config.get("limits") or {}
    max_age_hours = float(limits.get("target_max_age_hours") or 36)
    min_replies = int(limits.get("target_min_replies") or 0)
    max_replies = int(limits.get("target_max_replies") or 999999)
    users = _user_map(payload)
    rows: list[dict] = []
    for post in payload.get("data") or []:
        if not isinstance(post, dict):
            continue
        post_id = str(post.get("id") or "")
        if not post_id or post_id in known:
            continue
        text = str(post.get("text") or "")
        if not _invitation_gate(text, language, config):
            continue
        if not _thread_relevant(text, config):
            continue
        created = _parse_created_at(post.get("created_at"))
        if created is None:
            continue
        age_hours = (now - created).total_seconds() / 3600
        if age_hours < 0 or age_hours > max_age_hours:
            continue
        metrics = _metrics(post)
        if metrics["reply_count"] < min_replies or metrics["reply_count"] > max_replies:
            continue
        author_id = str(post.get("author_id") or "")
        user = users.get(author_id) or {}
        username = str(user.get("username") or "")
        product_choice = _draft_for(post_id, language, text, config)
        if product_choice is None:
            continue
        product_key, product_name, draft, fit_score, fit_reason = product_choice
        crowd_score = _score(post, user)
        placement_score = round(crowd_score + fit_score * 15.0, 2)
        rows.append({
            "schema": "tanuki-scout-candidate/v0.3",
            "observed_at": now.isoformat(),
            "target_post_id": post_id,
            "target_url": _post_url(username, post_id),
            "target_author_id": author_id,
            "target_username": username,
            "language": language,
            "created_at": created.isoformat(),
            "age_hours": round(age_hours, 2),
            "metrics": metrics,
            "crowd_score": crowd_score,
            "fit_score": fit_score,
            "fit_reason": fit_reason,
            "score": placement_score,
            "target_text": text[:1000],
            "draft_product_key": product_key,
            "draft_product_name": product_name,
            "draft_reply": draft,
            "send_status": "BLOCKED_PENDING_X_AUTO_RESPONSE_APPROVAL",
        })
    rows.sort(key=lambda row: (-float(row["score"]), float(row["age_hours"])))
    return rows


def _collect_market_signals(payload: dict, label: str, language: str, known: set[str], now: datetime) -> list[dict]:
    users = _user_map(payload)
    rows: list[dict] = []
    for post in payload.get("data") or []:
        if not isinstance(post, dict):
            continue
        post_id = str(post.get("id") or "")
        if not post_id or post_id in known:
            continue
        author_id = str(post.get("author_id") or "")
        user = users.get(author_id) or {}
        username = str(user.get("username") or "")
        rows.append({
            "schema": "tanuki-market-signal/v0.2",
            "observed_at": now.isoformat(),
            "post_id": post_id,
            "url": _post_url(username, post_id),
            "author_id": author_id,
            "username": username,
            "label": label,
            "language": language,
            "metrics": _metrics(post),
            "score": _score(post, user),
            "text": str(post.get("text") or "")[:1000],
            "action": "RESEARCH_ONLY_NO_AUTOREPLY",
        })
    rows.sort(key=lambda row: -float(row["score"]))
    return rows


def _select_language_balanced_candidates(
    candidate_rows: list[dict],
    candidate_limit: int,
    per_language: object,
) -> list[dict]:
    rows = sorted(
        candidate_rows,
        key=lambda row: (-float(row["score"]), float(row["age_hours"])),
    )
    if not isinstance(per_language, dict) or not per_language:
        return rows[:candidate_limit]

    selected: list[dict] = []
    selected_ids: set[str] = set()
    for language, raw_limit in per_language.items():
        try:
            language_limit = max(0, int(raw_limit))
        except (TypeError, ValueError):
            language_limit = 0
        if language_limit <= 0:
            continue
        lang_rows = [row for row in rows if str(row.get("language") or "") == str(language)]
        for row in lang_rows[:language_limit]:
            selected.append(row)
            selected_ids.add(str(row.get("target_post_id") or ""))

    if len(selected) < candidate_limit:
        for row in rows:
            row_id = str(row.get("target_post_id") or "")
            if row_id in selected_ids:
                continue
            selected.append(row)
            selected_ids.add(row_id)
            if len(selected) >= candidate_limit:
                break

    return sorted(
        selected[:candidate_limit],
        key=lambda row: (-float(row["score"]), float(row["age_hours"])),
    )


def main() -> int:
    config = _load_config()
    if config.get("auto_reply_enabled") is True:
        raise RuntimeError("Tanuki Scout v0.2 is discovery-only. Third-party auto-replies remain disabled pending X approval.")
    if config.get("scan_enabled") is not True:
        print("SCOUT_DISABLED")
        return 0

    bearer = _app_bearer()
    limits = config.get("limits") or {}
    max_calls = int(limits.get("search_calls_per_run") or 4)
    candidate_limit = int(limits.get("candidate_rows_per_run") or 12)
    market_limit = int(limits.get("market_signal_rows_per_run") or 12)
    now = datetime.now(timezone.utc)

    known_candidates = _known_ids(CANDIDATE_STATE, "target_post_id")
    known_market = _known_ids(MARKET_STATE, "post_id")
    candidate_rows: list[dict] = []
    market_rows: list[dict] = []
    calls = 0

    for spec in config.get("invitation_searches") or []:
        if calls >= max_calls:
            break
        payload = _search_recent(bearer, str(spec["query"]))
        calls += 1
        candidate_rows.extend(
            _collect_invitation_candidates(
                payload,
                str(spec.get("language") or "en"),
                config,
                known_candidates | {row["target_post_id"] for row in candidate_rows},
                now,
            )
        )

    for spec in config.get("market_searches") or []:
        if calls >= max_calls:
            break
        payload = _search_recent(bearer, str(spec["query"]))
        calls += 1
        market_rows.extend(
            _collect_market_signals(
                payload,
                str(spec.get("label") or "market"),
                str(spec.get("language") or "en"),
                known_market | {row["post_id"] for row in market_rows},
                now,
            )
        )

    candidate_rows = _select_language_balanced_candidates(
        candidate_rows,
        candidate_limit,
        limits.get("candidate_rows_per_language") or {},
    )
    market_rows.sort(key=lambda row: -float(row["score"]))
    market_rows = market_rows[:market_limit]

    _append_rows(CANDIDATE_STATE, candidate_rows)
    _append_rows(MARKET_STATE, market_rows)

    print(f"SCOUT_OK calls={calls} new_candidates={len(candidate_rows)} new_market_signals={len(market_rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
