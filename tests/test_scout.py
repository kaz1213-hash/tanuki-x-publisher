import unittest
from datetime import datetime, timezone

import scout


CONFIG = {
    "invitation_gate": {
        "require_any_en": ["drop your project", "show me what you built"],
        "require_any_ja": ["宣伝どうぞ", "作品貼って"],
        "reject_any": ["no promo", "宣伝禁止"],
    },
    "limits": {
        "target_max_age_hours": 36,
        "target_min_replies": 2,
        "target_max_replies": 500,
        "min_product_fit": 1,
    },
    "relevance": {
        "off_topic_any": ["歌コレ", "歌ってみた", "music cover"],
        "generic_builder_any": ["ai", "saas", "builder", "project", "project url", "app", "tool", "個人開発", "開発", "アプリ", "プロジェクト"],
        "product_affinity": {
            "project-vault": {
                "terms": ["chatgpt", "ai", "saas", "builder", "app", "tool", "個人開発", "開発", "アプリ"],
                "generic_bias": 3,
            }
        },
    },
    "draft_products": [
        {
            "key": "project-vault",
            "name": "Project Vault",
            "languages": ["en", "ja"],
            "url": "https://example.com",
            "drafts": {
                "en": ["A small local-first tool."],
                "ja": ["小さなローカル寄りツールです。"],
            },
        }
    ],
}


class ScoutTests(unittest.TestCase):
    def test_invitation_gate_accepts_explicit_invite(self):
        self.assertTrue(scout._invitation_gate("Drop your project below!", "en", CONFIG))
        self.assertTrue(scout._invitation_gate("作品貼ってください", "ja", CONFIG))

    def test_invitation_gate_rejects_negative(self):
        self.assertFalse(scout._invitation_gate("Drop your project? No promo please.", "en", CONFIG))
        self.assertFalse(scout._invitation_gate("作品貼って、でも宣伝禁止", "ja", CONFIG))

    def test_candidate_requires_active_recent_thread(self):
        now = datetime(2026, 9, 28, 12, 0, tzinfo=timezone.utc)
        payload = {
            "data": [
                {
                    "id": "123",
                    "text": "Drop your project below!",
                    "author_id": "u1",
                    "created_at": "2026-09-28T10:00:00Z",
                    "public_metrics": {
                        "reply_count": 5,
                        "like_count": 10,
                        "retweet_count": 1,
                        "quote_count": 0,
                    },
                }
            ],
            "includes": {
                "users": [
                    {
                        "id": "u1",
                        "username": "builder",
                        "public_metrics": {"followers_count": 1000},
                    }
                ]
            },
        }
        rows = scout._collect_invitation_candidates(payload, "en", CONFIG, set(), now)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["target_post_id"], "123")
        self.assertEqual(rows[0]["send_status"], "BLOCKED_PENDING_X_AUTO_RESPONSE_APPROVAL")
        self.assertIn("Project Vault", rows[0]["draft_product_name"])

    def test_candidate_skips_low_activity(self):
        now = datetime(2026, 9, 28, 12, 0, tzinfo=timezone.utc)
        payload = {
            "data": [
                {
                    "id": "low",
                    "text": "Drop your project below!",
                    "author_id": "u1",
                    "created_at": "2026-09-28T10:00:00Z",
                    "public_metrics": {
                        "reply_count": 0,
                        "like_count": 50,
                        "retweet_count": 0,
                        "quote_count": 0,
                    },
                }
            ]
        }
        self.assertEqual(scout._collect_invitation_candidates(payload, "en", CONFIG, set(), now), [])

    def test_known_target_is_deduped(self):
        now = datetime(2026, 9, 28, 12, 0, tzinfo=timezone.utc)
        payload = {
            "data": [
                {
                    "id": "123",
                    "text": "Drop your project below!",
                    "author_id": "u1",
                    "created_at": "2026-09-28T10:00:00Z",
                    "public_metrics": {
                        "reply_count": 5,
                        "like_count": 0,
                        "retweet_count": 0,
                        "quote_count": 0,
                    },
                }
            ]
        }
        self.assertEqual(scout._collect_invitation_candidates(payload, "en", CONFIG, {"123"}, now), [])

    def test_japanese_music_invitation_is_rejected_as_off_topic(self):
        now = datetime(2026, 9, 28, 12, 0, tzinfo=timezone.utc)
        payload = {
            "data": [
                {
                    "id": "music",
                    "text": "#歌コレ2026秋 本気の一曲、作品貼ってください！",
                    "author_id": "u1",
                    "created_at": "2026-09-28T10:00:00Z",
                    "public_metrics": {
                        "reply_count": 30,
                        "like_count": 40,
                        "retweet_count": 2,
                        "quote_count": 0,
                    },
                }
            ]
        }
        self.assertEqual(scout._collect_invitation_candidates(payload, "ja", CONFIG, set(), now), [])

    def test_generic_builder_thread_prefers_project_vault(self):
        now = datetime(2026, 9, 28, 12, 0, tzinfo=timezone.utc)
        payload = {
            "data": [
                {
                    "id": "builder",
                    "text": "AI SaaS builders: drop your project URL below!",
                    "author_id": "u1",
                    "created_at": "2026-09-28T10:00:00Z",
                    "public_metrics": {
                        "reply_count": 8,
                        "like_count": 12,
                        "retweet_count": 1,
                        "quote_count": 0,
                    },
                }
            ]
        }
        rows = scout._collect_invitation_candidates(payload, "en", CONFIG, set(), now)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["draft_product_key"], "project-vault")
        self.assertGreater(rows[0]["fit_score"], 0)
        self.assertIn("fit_reason", rows[0])



if __name__ == "__main__":
    unittest.main()
