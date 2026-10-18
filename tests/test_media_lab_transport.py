import hashlib
import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import media_lab_transport as x

TEXT = "I told my AI assistant to stop asking for permission.\n\n“Understood,” it said.\n\nThen: “May I proceed?”\n\nApparently, I didn’t build an autonomous agent.\n\nI built a permission form with a personality. 🦝"
ID = "TML-X-SHORT-20261017-PERMISSION-FORM-01"


def item():
    return {
        "id": ID, "status": "APPROVED", "director_approved": True,
        "network": "twitter", "media_count": 0,
        "approval_id": "DIRECTOR-20261017-PERMISSION-FORM-EN-01",
        "text": TEXT, "caption_sha256": hashlib.sha256(TEXT.encode()).hexdigest(),
        "not_before": "2026-10-18T00:00:00+09:00",
    }


def receipt(published_at):
    return {"id": "TML-OLDER", "post_id": "2111385989088436226", "published_at": published_at}


class MediaLabTransportTests(unittest.TestCase):
    def test_locked_caption_accepts_exact_director_approval(self):
        self.assertEqual(x._approved_item(item())["text"], TEXT)

    def test_rejects_modified_or_unapproved_text(self):
        for field, value in [
            ("text", TEXT + "!"), ("director_approved", False),
            ("status", "MINED"), ("media_count", 1),
            ("network", "instagram"), ("caption_sha256", "0" * 64)
        ]:
            with self.subTest(field=field):
                wrong = item()
                wrong[field] = value
                with self.assertRaises(ValueError):
                    x._approved_item(wrong)

    def test_empty_x_timeline_must_not_be_mistaken_for_zero_posts(self):
        with patch.object(x, "_get_x", side_effect=[
            {"data": {"id": "3", "username": "TanukiBySCA"}},
            {"meta": {"result_count": 0}, "data": []},
        ]):
            with self.assertRaisesRegex(RuntimeError, "EMPTY"):
                x._live_timeline(object())

    def test_account_mismatch_blocks(self):
        with patch.object(x, "_get_x", return_value={"data": {"id": "3", "username": "wrong"}}):
            with self.assertRaisesRegex(RuntimeError, "ACCOUNT_MISMATCH"):
                x._live_timeline(object())

    def _run_setup(self, td, private_receipts, live, now):
        root = Path(td)
        public = root / "published.jsonl"
        public.write_text(json.dumps(receipt("2026-10-17T09:17:02Z")) + "\n", encoding="utf-8")
        manifest = json.dumps({"schema": x.SCHEMA, "items": [item()]})
        p1 = patch.object(x, "PUBLIC_RECEIPTS", public)
        p2 = patch.object(x, "ATTEMPTS_DIR", root / "attempts")
        p3 = patch.object(x, "_github_read", side_effect=lambda path, allow_missing=False:
            manifest if path == x.APPROVAL_PATH else private_receipts)
        p4 = patch.object(x, "_oauth", return_value=object())
        p5 = patch.object(x, "_live_timeline", side_effect=live)
        p6 = patch.object(x, "datetime")
        for p in [p1, p2, p3, p4, p5, p6]: p.start()
        x.datetime.now.return_value = now
        return [p1, p2, p3, p4, p5, p6], public

    def test_existing_post_reconciled_without_post(self):
        with tempfile.TemporaryDirectory() as td:
            today = datetime(2026, 10, 18, 7, 0, tzinfo=timezone.utc)
            live = [{"id": "2111", "text": TEXT, "created_at": "2026-10-18T01:11:11Z"},
                    {"id": "2111385989088436226", "text": "older", "created_at": "2026-10-17T09:17:02Z"}]
            patches, file = self._run_setup(td, "", [live], today)
            try:
                with patch.object(x.requests, "post") as post:
                    self.assertEqual(x.run(), 0)
                    post.assert_not_called()
                self.assertIn(ID, file.read_text(encoding="utf-8"))
            finally:
                for p in reversed(patches): p.stop()

    def test_same_day_live_post_holds_without_publishing(self):
        with tempfile.TemporaryDirectory() as td:
            today = datetime(2026, 10, 18, 7, 0, tzinfo=timezone.utc)
            live = [{"id": "2111", "text": "someone else posted", "created_at": "2026-10-18T01:11:11Z"},
                    {"id": "2111385989088436226", "text": "older", "created_at": "2026-10-17T09:17:02Z"}]
            patches, file = self._run_setup(td, "", [live], today)
            try:
                with patch.object(x, "_reserve_once") as reserve, patch.object(x.requests, "post") as post:
                    self.assertEqual(x.run(), 0)
                    reserve.assert_not_called()
                    post.assert_not_called()
            finally:
                for p in reversed(patches): p.stop()

    def test_unknown_attempt_cannot_repost(self):
        with tempfile.TemporaryDirectory() as td:
            today = datetime(2026, 10, 18, 7, 0, tzinfo=timezone.utc)
            live = [{"id": "2111385989088436226", "text": "older", "created_at": "2026-10-17T09:17:02Z"}]
            patches, _ = self._run_setup(td, "", [live], today)
            try:
                marker = Path(td) / "attempts" / (ID + ".json")
                marker.parent.mkdir(parents=True)
                marker.write_text("{}", encoding="utf-8")
                with patch.object(x.requests, "post") as post:
                    with self.assertRaisesRegex(RuntimeError, "PREVIOUS_ATTEMPT"):
                        x.run()
                    post.assert_not_called()
            finally:
                for p in reversed(patches): p.stop()

    def test_success_one_post_exact_payload_after_intent(self):
        with tempfile.TemporaryDirectory() as td:
            today = datetime(2026, 10, 18, 7, 0, tzinfo=timezone.utc)
            old = {"id": "2111385989088436226", "text": "older", "created_at": "2026-10-17T09:17:02Z"}
            new = {"id": "2111399000000000000", "text": TEXT, "created_at": "2026-10-18T07:02:00Z"}
            patches, file = self._run_setup(td, "", [[old], [new, old]], today)
            try:
                with patch.object(x, "_reserve_once") as reserve, patch.object(x.time, "sleep"), patch.object(x.requests, "post") as post:
                    post.return_value.status_code = 201
                    post.return_value.json.return_value = {"data": {"id": new["id"]}}
                    self.assertEqual(x.run(), 0)
                    reserve.assert_called_once()
                    post.assert_called_once()
                    self.assertEqual(post.call_args.kwargs["json"], {"text": TEXT})
                    self.assertIn(new["id"], file.read_text(encoding="utf-8"))
            finally:
                for p in reversed(patches): p.stop()


if __name__ == "__main__":
    unittest.main()
