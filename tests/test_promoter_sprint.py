import base64
import json
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

import publisher


def contents_payload(data):
    raw = json.dumps(data).encode("utf-8")
    return {"encoding": "base64", "content": base64.b64encode(raw).decode("ascii")}


class PromoterSprintTests(unittest.TestCase):
    def test_loads_ready_items_and_skips_non_ready(self):
        data = {
            "schema": "tanuki-promoter-sprint/v0.1",
            "items": [
                {
                    "id": "a",
                    "status": "ready",
                    "publish_at": "2026-09-29T00:05:00Z",
                    "product": "P",
                    "campaign": "C",
                    "text": "hello",
                },
                {
                    "id": "b",
                    "status": "draft",
                    "publish_at": "2026-09-29T03:05:00Z",
                    "text": "skip",
                },
            ],
        }
        with patch.object(publisher, "_github_get", return_value=contents_payload(data)):
            items = publisher._load_promoter_sprint()
        self.assertEqual([x.item_id for x in items], ["a"])
        self.assertFalse(items[0].has_media)

    def test_duplicate_ids_fail_closed(self):
        row = {
            "id": "dup",
            "status": "ready",
            "publish_at": "2026-09-29T00:05:00Z",
            "text": "hello",
        }
        data = {"schema": "tanuki-promoter-sprint/v0.1", "items": [row, dict(row)]}
        with patch.object(publisher, "_github_get", return_value=contents_payload(data)):
            with self.assertRaises(ValueError):
                publisher._load_promoter_sprint()

    def test_media_in_promoter_manifest_fails_closed(self):
        data = {
            "schema": "tanuki-promoter-sprint/v0.1",
            "items": [{
                "id": "media",
                "status": "ready",
                "publish_at": "2026-09-29T00:05:00Z",
                "text": "hello",
                "media_paths": ["x.png"],
            }],
        }
        with patch.object(publisher, "_github_get", return_value=contents_payload(data)):
            with self.assertRaises(ValueError):
                publisher._load_promoter_sprint()

    def test_prepare_text_strips_urls_from_automatic_posts(self):
        item = publisher.QueueItem(
            item_id="url",
            text="Useful thing.\n\nhttps://example.com/product",
            short_text="",
            publish_at=datetime(2026, 9, 30, tzinfo=timezone.utc),
            product="P",
            campaign="C",
            has_media=False,
        )
        text, mode, _ = publisher._prepare_text(item)
        self.assertEqual(text, "Useful thing.")
        self.assertEqual(mode, "url_stripped")
        self.assertNotIn("http", text)

    def test_prepare_text_keeps_url_free_posts_unchanged(self):
        item = publisher.QueueItem(
            item_id="plain",
            text="No link here.",
            short_text="",
            publish_at=datetime(2026, 9, 30, tzinfo=timezone.utc),
            product="P",
            campaign="C",
            has_media=False,
        )
        text, mode, _ = publisher._prepare_text(item)
        self.assertEqual(text, "No link here.")
        self.assertEqual(mode, "original")



if __name__ == "__main__":
    unittest.main()
