import unittest
from datetime import datetime, timezone

import publisher


def item(item_id: str, hour: int) -> publisher.QueueItem:
    return publisher.QueueItem(
        item_id=item_id,
        text=item_id,
        short_text="",
        publish_at=datetime(2026, 9, 29, hour, 0, tzinfo=timezone.utc),
        product="",
        campaign="",
        has_media=False,
    )


class PromoterPriorityTests(unittest.TestCase):
    def test_due_promoter_beats_older_legacy_backlog(self):
        now = datetime(2026, 9, 29, 1, 0, tzinfo=timezone.utc)
        legacy = [item("legacy-old", 0)]
        promoter = [item("promoter-due", 1)]
        selected = publisher._select_due_queue(promoter, legacy, set(), now)
        self.assertEqual([x.item_id for x in selected], ["promoter-due"])

    def test_legacy_runs_when_no_promoter_is_due(self):
        now = datetime(2026, 9, 29, 1, 0, tzinfo=timezone.utc)
        legacy = [item("legacy-old", 0)]
        promoter = [item("promoter-future", 2)]
        selected = publisher._select_due_queue(promoter, legacy, set(), now)
        self.assertEqual([x.item_id for x in selected], ["legacy-old"])

    def test_published_promoter_does_not_block_legacy(self):
        now = datetime(2026, 9, 29, 1, 0, tzinfo=timezone.utc)
        legacy = [item("legacy-old", 0)]
        promoter = [item("promoter-due", 1)]
        selected = publisher._select_due_queue(promoter, legacy, {"promoter-due"}, now)
        self.assertEqual([x.item_id for x in selected], ["legacy-old"])


if __name__ == "__main__":
    unittest.main()
