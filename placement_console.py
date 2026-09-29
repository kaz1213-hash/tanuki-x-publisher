from __future__ import annotations

import json
import os
import webbrowser
from datetime import datetime, timezone
from pathlib import Path
from tkinter import BOTH, END, LEFT, RIGHT, VERTICAL, Button, Frame, Label, Scrollbar, StringVar, Text, Tk, messagebox
from tkinter import ttk
from urllib.parse import urlencode

ROOT = Path(os.environ.get("LOCALAPPDATA", ".")) / "TanukiXPublisher"
STATE_DIR = Path(os.environ.get("TANUKI_SCOUT_STATE_DIR", ROOT / "placement-state"))
CANDIDATES = STATE_DIR / "scout_candidates_v03.jsonl"
HANDLED = STATE_DIR / "manual_placements.jsonl"


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
    return rows


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

        Button(
            actions,
            text="🦝 Xで返信を開く",
            command=self.open_reply,
            font=("Segoe UI", 14, "bold"),
            padx=18,
            pady=10,
        ).pack(side=LEFT)

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

        note = (
            "宣伝歓迎＝明示的に共有を募っているスレ。話題スレ＝ChatGPT等の関連会話で、宣伝歓迎とは限りません。"
            " どちらも最後のPostは所長が判断して押します。"
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
            self.meta.set("いま使える『人がいる場所』はありません。あとで起動し直せば再スキャンします。")
            self.set_text(self.target, "")
            self.draft.delete("1.0", END)
            return

        metrics = row.get("metrics") or {}
        self.counter.set(f"{self.index + 1} / {len(self.rows)}")
        placement_kind = str(row.get("placement_kind") or "invitation")
        placement_label = "話題スレ" if placement_kind == "topic" else "宣伝歓迎"
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
        if row and row.get("target_url"):
            webbrowser.open(str(row["target_url"]))

    def open_reply(self) -> None:
        row = self.current()
        if not row:
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

    def skip(self) -> None:
        row = self.current()
        if not row:
            return
        record_handled(row, "SKIPPED")
        self.advance()


if __name__ == "__main__":
    root = Tk()
    PlacementConsole(root)
    root.mainloop()
