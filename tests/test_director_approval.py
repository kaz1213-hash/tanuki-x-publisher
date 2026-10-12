"""Publisher approval tests: no network calls, no X posts."""
import copy
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

import approval_verifier as AV
import publisher

KEY = "a" * 40
FIXTURE = {
    "id": "pilot-story-01-x",
    "text": "作品の実話から漫画とBlogができた。🦝",
    "short_text": "",
    "status": "ready",
    "campaign": "auto-mine-story",
    "auto_generated": True,
    "product": "Tanuki Media Lab",
    "source_ref": "story-0001",
    "source_ore_id": "ore-001",
    "director_approval": {
        "schema": "tanuki-media-director-approval/v1",
        "item_id": "pilot-story-01-x",
        "content_sha256": "eb3eacc4b8413a7c621431280626745171da8c7e0dee7c93deeb9170a36fadc9",
        "channel": "x",
        "actor": "Director",
        "decision_ref": "test-approved-123",
        "approved_at": "2026-10-10T00:00:00+00:00",
        "signature": "b6799dabd4466bc0098e30a3299ef673874bdfe8a1bd2334a40ffbbfb3e79b56",
    },
}
NOW = datetime(2026, 10, 10, 1, tzinfo=timezone.utc)


def mock_item(*, promoter=False, data=None):
    data = data or {"id": "unapproved", "text": "hello", "campaign": "auto-mine-story", "auto_generated": True}
    return publisher.QueueItem(
        item_id=data["id"], text=data["text"], short_text=data.get("short_text", ""),
        publish_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
        product=data.get("product", ""), campaign=data.get("campaign", ""),
        has_media=False, approval_data=data, promoter=promoter,
    )


class DirectorApprovalPublisherTests(unittest.TestCase):
    def test_fixed_growth_signature_is_verified(self):
        AV.require_approved(FIXTURE, secret=KEY, now=NOW)

    def test_changed_text_and_fake_signature_fail(self):
        data = copy.deepcopy(FIXTURE)
        data["text"] += " 追加文"
        with self.assertRaisesRegex(AV.Unapproved, "changed"):
            AV.require_approved(data, secret=KEY, now=NOW)
        data = copy.deepcopy(FIXTURE)
        data["director_approval"]["signature"] = "0" * 64
        with self.assertRaisesRegex(AV.Unapproved, "signature"):
            AV.require_approved(data, secret=KEY, now=NOW)

    def test_missing_key_or_receipt_fails_closed(self):
        with self.assertRaisesRegex(AV.Unapproved, "verifier missing"):
            AV.require_approved(FIXTURE, secret="", now=NOW)
        with self.assertRaisesRegex(AV.Unapproved, "missing explicit"):
            AV.require_approved({"id": "item", "text": "hello", "campaign": "auto-mine-story"}, secret=KEY)

    def test_promoter_requires_each_own_approval_even_if_campaign_unknown(self):
        with self.assertRaisesRegex(AV.Unapproved, "missing explicit"):
            AV.require_approved({"id": "promoter", "text": "hello", "campaign": "sprint"}, promoter=True, secret=KEY)

    def test_unapproved_generated_queue_never_calls_x_api(self):
        item = mock_item()
        with patch.object(publisher, "_load_published_ids", return_value=set()), \
             patch.object(publisher, "_load_private_queue", return_value=[item]), \
             patch.object(publisher, "_load_promoter_sprint", return_value=[]), \
             patch.object(publisher, "_publish_text", side_effect=AssertionError("X API must never be called")):
            self.assertEqual(publisher.main(), 0)

    def test_unapproved_promoter_does_not_starve_approved_queue(self):
        # With an authenticated verifier key, promoter row is still rejected
        # while a duly approved auto-mine queue item is eligible.
        item = mock_item(data=FIXTURE)
        promoter = mock_item(promoter=True, data={"id": "sprint", "text": "hello", "campaign": "sprint"})
        with patch.dict("os.environ", {AV.ENV_KEY: KEY}), \
             patch.object(publisher, "_load_published_ids", return_value=set()), \
             patch.object(publisher, "_load_private_queue", return_value=[item]), \
             patch.object(publisher, "_load_promoter_sprint", return_value=[promoter]), \
             patch.object(publisher, "_publish_text", return_value=("fake-test-id", "https://x.com/i/web/status/fake")), \
             patch.object(publisher, "_append_receipt") as append:
            self.assertEqual(publisher.main(), 0)
            append.assert_called_once()
            self.assertEqual(append.call_args.args[0].item_id, FIXTURE["id"])


if __name__ == "__main__":
    unittest.main()
