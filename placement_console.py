from __future__ import annotations

import json
import os
import webbrowser
from datetime import datetime, timezone
from pathlib import Path
from tkinter import BOTH, END, LEFT, RIGHT, Button, Frame, Label, StringVar, Text, Tk, messagebox
from urllib.parse import urlencode
import subprocess

ROOT = Path(os.environ.get("LOCALAPPDATA", ".")) / "TanukiXPublisher"
STATE_DIR = Path(os.environ.get("TANUKI_SCOUT_STATE_DIR", ROOT / "placement-state"))
CANDIDATES = STATE_DIR / "scout_candidates_v03.jsonl"
HANDLED = STATE_DIR / "manual_placements.jsonl"
SCOUT_STATUS = STATE_DIR / "last_scout_status.txt"

HUNTING_LANES = [
    {
        "target_post_id": "hunt-ja-chatgpt-pain",
        "draft_reply": "ChatGPTの昔の会話が埋もれて探しづらいの、自分も困ってProject Vaultを作りました。対応エクスポートをローカルで保存・検索できます。$10買い切りです。\\n\\nhttps://silentcoastasset.com/project-vault.html",
        "language": "ja",
        "placement_kind": "hunting_lane",
        "prospect_intent": "pain",
        "target_username": "X検索",
        "target_text": "ChatGPTの履歴・会話整理・昔のチャットが見つからない人を探す",
        "draft_product_name": "Project Vault",
        "fit_reason": "ChatGPT履歴 / 整理 / 検索",
        "search_query": '(ChatGPT OR 生成AI) (履歴 OR 会話 OR 整理 OR 探せない OR 見つからない OR 埋もれた)',
    },
    {
        "target_post_id": "hunt-ja-chatgpt-usage",
        "draft_reply": "ChatGPTを日常的に使っていると、あとで昔の会話を探すのが地味に大変で、Project Vaultというローカル整理ツールを作りました。$10買い切りです。\\n\\nhttps://silentcoastasset.com/project-vault.html",
        "language": "ja",
        "placement_kind": "hunting_lane",
        "prospect_intent": "usage",
        "target_username": "X検索",
        "target_text": "ChatGPTを何に使っているか話している人を探す",
        "draft_product_name": "Project Vault",
        "fit_reason": "ChatGPT利用者",
        "search_query": 'ChatGPT (何に使ってる OR どう使ってる OR 使ってる OR 活用 OR 課金)',
    },
    {
        "target_post_id": "hunt-ja-story",
        "draft_reply": "ChatGPTとの長い会話や創作ログって、あとから読むと自分の物語になってることがあって、Tanuki Chronicleという読み物化ツールを作りました。US$14.99買い切りです。\\n\\nhttps://silentcoastasset.com/tanuki-chronicle.html",
        "language": "ja",
        "placement_kind": "hunting_lane",
        "prospect_intent": "adjacent",
        "target_username": "X検索",
        "target_text": "ChatGPTで物語・小説・日記・創作をしている人を探す",
        "draft_product_name": "Tanuki Chronicle",
        "fit_reason": "物語 / 小説 / 日記 / 創作",
        "search_query": '(ChatGPT OR 生成AI) (物語 OR 小説 OR 創作 OR 日記 OR ストーリー)',
    },
    {
        "target_post_id": "hunt-ja-fortune",
        "draft_reply": "ChatGPTの過去ログから、その人専用の妙に心当たりがある『札』を作るTanuki Fortuneという変な占いを作りました。端末内で完結、US$4.99買い切りです。\\n\\nhttps://silentcoastasset.com/tanuki-fortune.html",
        "language": "ja",
        "placement_kind": "hunting_lane",
        "prospect_intent": "adjacent",
        "target_username": "X検索",
        "target_text": "ChatGPT占い・タロット・おみくじで遊んでいる人を探す",
        "draft_product_name": "Tanuki Fortune",
        "fit_reason": "占い / タロット / おみくじ",
        "search_query": '(ChatGPT OR 生成AI) (占い OR タロット OR おみくじ OR 運勢)',
    },
    {
        "target_post_id": "hunt-ja-fx",
        "draft_reply": "昔のFX自動売買をChatGPTで復活させようとしたら、教授6人・研究班・監査制度までできて、最後はKindle本『FX大学』になりました。EAやバックテスト好き向けです。\\n\\nhttps://www.amazon.co.jp/dp/B0H1M3VY6B",
        "language": "ja",
        "placement_kind": "hunting_lane",
        "prospect_intent": "question",
        "target_username": "X検索",
        "target_text": "EA・MT4/MT5・FX自動売買の情報交換をしている人を探す",
        "draft_product_name": "FX University",
        "fit_reason": "EA / MT4 / MT5 / FX自動売買",
        "search_query": '(FX自動売買 OR 自動売買 OR EA OR MT4 OR MT5) (使ってる OR おすすめ OR 教えて OR 情報交換 OR バックテスト)',
    },
    {
        "target_post_id": "hunt-en-chatgpt",
        "draft_reply": "I built a few small Tanuki tools around ChatGPT use: Project Vault for local searchable archives, Chronicle for turning long conversations into a story, and Fortune for an oddly personal local fortune from your own logs.\\n\\nhttps://silentcoastasset.com",
        "language": "en",
        "placement_kind": "hunting_lane",
        "prospect_intent": "usage",
        "target_username": "X Search",
        "target_text": "Find English ChatGPT users talking about history, stories, or tarot",
        "draft_product_name": "Vault / Chronicle / Fortune",
        "fit_reason": "English ChatGPT users",
        "search_query": 'ChatGPT ("chat history" OR "using ChatGPT" OR story OR fiction OR tarot OR fortune)',
    },
]


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    rows: list[dict] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(row, dict):
            rows.append(row)
    return rows


def handled_ids() -> set[str]:
    ids: set[str] = set()
    for row in read_jsonl(HANDLED):
        value = row.get("target_post_id")
        if value:
            ids.add(str(value))
    return ids


def record_handled(row: dict, action: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "target_post_id": row.get("target_post_id"),
        "target_url": row.get("target_url"),
        "target_username": row.get("target_username"),
        "target_text": row.get("target_text"),
        "placement_kind": row.get("placement_kind"),
        "prospect_intent": row.get("prospect_intent"),
        "lane": row.get("lane"),
        "draft_product_key": row.get("draft_product_key"),
        "draft_product_name": row.get("draft_product_name"),
        "fit_score": row.get("fit_score"),
        "fit_reason": row.get("fit_reason"),
        "action": action,
        "handled_at": datetime.now(timezone.utc).isoformat(),
    }
    with HANDLED.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False) + "\n")


def load_candidates() -> list[dict]:
    done = handled_ids()
    rows = [
        row for row in read_jsonl(CANDIDATES)
        if str(row.get("target_post_id") or "") not in done
    ]
    rows.sort(key=lambda r: (-float(r.get("score") or 0), float(r.get("age_hours") or 9999)))

    # If both languages exist, interleave them so Japanese leads are not buried
    # under higher-volume English builder threads.
    ja = [row for row in rows if str(row.get("language") or "") == "ja"]
    en = [row for row in rows if str(row.get("language") or "") == "en"]
    other = [row for row in rows if str(row.get("language") or "") not in {"ja", "en"}]
    if ja and en:
        mixed: list[dict] = []
        limit = max(len(ja), len(en))
        for i in range(limit):
            if i < len(ja):
                mixed.append(ja[i])
            if i < len(en):
                mixed.append(en[i])
        mixed.extend(other)
        return mixed
    if rows:
        return rows
    return [dict(row) for row in HUNTING_LANES]


class PlacementConsole:
    def __init__(self, root: Tk):
        self.root = root
        self.root.title("Tanuki Placement Console")
        self.root.geometry("980x760")
        self.rows = load_candidates()
        self.index = 0

        top = Frame(root)
        top.pack(fill="x", padx=18, pady=(16, 8))
        Label(top, text="🦝 Tanuki Placement Console", font=("Segoe UI", 20, "bold")).pack(side=LEFT)
        self.counter = StringVar()
        Label(top, textvariable=self.counter, font=("Segoe UI", 11)).pack(side=RIGHT)

        self.meta = StringVar()
        Label(root, textvariable=self.meta, anchor="w", font=("Segoe UI", 11)).pack(fill="x", padx=18, pady=(0, 8))

        Label(root, text="このスレ", anchor="w", font=("Segoe UI", 10, "bold")).pack(fill="x", padx=18)
        self.target = Text(root, height=8, wrap="word", font=("Segoe UI", 11))
        self.target.pack(fill=BOTH, padx=18, pady=(4, 12))
        self.target.configure(state="disabled")

        Label(root, text="タヌキが用意した返信", anchor="w", font=("Segoe UI", 10, "bold")).pack(fill="x", padx=18)
        self.draft = Text(root, height=8, wrap="word", font=("Segoe UI", 11))
        self.draft.pack(fill=BOTH, padx=18, pady=(4, 12))

        actions = Frame(root)
        actions.pack(fill="x", padx=18, pady=8)

        self.primary_button = Button(
            actions,
            text="🦝 Xで返信を開く",
            command=self.open_reply,
            font=("Segoe UI", 14, "bold"),
            padx=18,
            pady=10,
        )
        self.primary_button.pack(side=LEFT)

        Button(
            actions,
            text="元ポストを見る",
            command=self.open_source,
            font=("Segoe UI", 11),
            padx=12,
            pady=10,
        ).pack(side=LEFT, padx=8)

        Button(
            actions,
            text="今回はスキップ",
            command=self.skip,
            font=("Segoe UI", 11),
            padx=12,
            pady=10,
        ).pack(side=RIGHT)

        Button(
            actions,
            text="再スキャン",
            command=self.rescan,
            font=("Segoe UI", 11),
            padx=12,
            pady=10,
        ).pack(side=RIGHT, padx=8)

        Button(
            actions,
            text="Xで狩場を開く",
            command=self.open_hunting_ground,
            font=("Segoe UI", 11),
            padx=12,
            pady=10,
        ).pack(side=RIGHT, padx=8)

        note = (
            "狩場候補では返信案も用意します。『狩場を開く＋返信コピー』でX検索を開き、返信文をクリップボードへコピーします。"
            " 投稿先を選んで文脈を確認し、貼り付けて最後のPostだけ所長が判断します。"
        )
        Label(root, text=note, wraplength=930, justify="left", font=("Segoe UI", 9)).pack(fill="x", padx=18, pady=(4, 12))

        self.show_current()

    def current(self) -> dict | None:
        if 0 <= self.index < len(self.rows):
            return self.rows[self.index]
        return None

    def set_text(self, widget: Text, value: str) -> None:
        widget.configure(state="normal")
        widget.delete("1.0", END)
        widget.insert("1.0", value)
        widget.configure(state="disabled")

    def show_current(self) -> None:
        row = self.current()
        if row is None:
            self.counter.set("候補 0")
            status = ""
            if SCOUT_STATUS.exists():
                try:
                    status = SCOUT_STATUS.read_text(encoding="utf-8-sig").strip().upper()
                except OSError:
                    status = ""
            if status == "FAILED":
                self.meta.set("X API検索が使えません。『Xで狩場を開く』ならX公式検索で今すぐ掘れます。")
            else:
                self.meta.set("いまの自動候補は一巡しました。『再スキャン』か『Xで狩場を開く』で続行できます。")
            self.set_text(self.target, "")
            self.draft.delete("1.0", END)
            return

        metrics = row.get("metrics") or {}
        self.counter.set(f"{self.index + 1} / {len(self.rows)}")
        placement_kind = str(row.get("placement_kind") or "invitation")
        if placement_kind == "hunting_lane":
            self.primary_button.configure(text="🦝 狩場を開く＋返信コピー")
        else:
            self.primary_button.configure(text="🦝 Xで返信を開く")
        intent = str(row.get("prospect_intent") or "")
        labels = {
            "question": "質問・募集",
            "pain": "困りごと",
            "usage": "ChatGPT利用中",
            "adjacent": "関連話題",
        }
        if placement_kind == "hunting_lane":
            placement_label = "狩場候補"
        else:
            placement_label = labels.get(intent, "見込み客会話" if placement_kind == "prospect" else "宣伝歓迎")
        self.meta.set(
            f"[{placement_label}] @{row.get('target_username') or '?'}  |  "
            f"返信 {metrics.get('reply_count', 0)}  いいね {metrics.get('like_count', 0)}  "
            f"RT {metrics.get('retweet_count', 0)}  |  crowd {row.get('crowd_score', row.get('score', 0))}  |  "
            f"fit {row.get('fit_score', '?')}  |  {row.get('age_hours', '?')}h前  |  "
            f"推奨: {row.get('draft_product_name') or '-'}  |  理由: {row.get('fit_reason') or '-'}"
        )
        self.set_text(self.target, str(row.get("target_text") or ""))
        self.draft.delete("1.0", END)
        self.draft.insert("1.0", str(row.get("draft_reply") or ""))

    def advance(self) -> None:
        if self.index < len(self.rows):
            self.rows.pop(self.index)
        self.show_current()

    def open_source(self) -> None:
        row = self.current()
        if not row:
            return
        if row.get("placement_kind") == "hunting_lane":
            draft = self.draft.get("1.0", END).strip()
            if draft:
                self.root.clipboard_clear()
                self.root.clipboard_append(draft)
                self.root.update()
            query = str(row.get("search_query") or "").strip()
            if query:
                webbrowser.open("https://x.com/search?" + urlencode({
                    "q": query,
                    "src": "typed_query",
                    "f": "live",
                }))
            return
        if row.get("target_url"):
            webbrowser.open(str(row["target_url"]))

    def open_reply(self) -> None:
        row = self.current()
        if not row:
            return
        if row.get("placement_kind") == "hunting_lane":
            query = str(row.get("search_query") or "").strip()
            if query:
                webbrowser.open("https://x.com/search?" + urlencode({
                    "q": query,
                    "src": "typed_query",
                    "f": "live",
                }))
            return
        post_id = str(row.get("target_post_id") or "")
        if not post_id:
            messagebox.showerror("Tanuki Placement", "返信先Post IDがありません。")
            return
        text = self.draft.get("1.0", END).strip()
        if not text:
            messagebox.showerror("Tanuki Placement", "返信文が空です。")
            return

        url = "https://x.com/intent/tweet?" + urlencode({
            "in_reply_to": post_id,
            "text": text,
        })
        webbrowser.open(url)
        record_handled(row, "OPENED_REPLY_INTENT")
        self.advance()

    def open_hunting_ground(self) -> None:
        queries = [
            '(ChatGPT OR 生成AI OR FX自動売買 OR EA) (使ってる OR おすすめ OR 履歴 OR 整理 OR 物語 OR 小説 OR 占い OR タロット)',
            '(ChatGPT OR "trading bot") ("using ChatGPT" OR recommend OR "chat history" OR story OR fiction OR tarot OR fortune)',
        ]
        for query in queries:
            webbrowser.open("https://x.com/search?" + urlencode({
                "q": query,
                "src": "typed_query",
                "f": "live",
            }))

    def rescan(self) -> None:
        script = ROOT / "repo" / "local_windows" / "run_manual_placement.ps1"
        if not script.exists():
            messagebox.showerror("Tanuki Placement", "再スキャン用スクリプトが見つかりません。")
            return
        subprocess.Popen([
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(script),
        ])
        self.root.destroy()

    def skip(self) -> None:
        row = self.current()
        if not row:
            return
        if row.get("placement_kind") == "hunting_lane":
            if self.rows:
                first = self.rows.pop(self.index)
                self.rows.append(first)
                if self.index >= len(self.rows):
                    self.index = 0
            self.show_current()
            return
        record_handled(row, "SKIPPED")
        self.advance()


if __name__ == "__main__":
    root = Tk()
    PlacementConsole(root)
    root.mainloop()
