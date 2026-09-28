import base64
import json
import unittest
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


if __name__ == "__main__":
    unittest.main()
