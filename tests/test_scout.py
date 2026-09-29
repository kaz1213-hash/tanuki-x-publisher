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


    def test_language_balance_keeps_japanese_candidates_visible(self):
        rows = [
            {"target_post_id": f"en-{i}", "language": "en", "score": 200 - i, "age_hours": 1}
            for i in range(10)
        ] + [
            {"target_post_id": "ja-1", "language": "ja", "score": 50, "age_hours": 1},
            {"target_post_id": "ja-2", "language": "ja", "score": 40, "age_hours": 1},
        ]
        selected = scout._select_language_balanced_candidates(
            rows,
            6,
            {"ja": 2, "en": 4},
        )
        self.assertEqual(sum(1 for row in selected if row["language"] == "ja"), 2)
        self.assertEqual(sum(1 for row in selected if row["language"] == "en"), 4)


    def test_japanese_self_made_app_mention_is_not_an_invitation(self):
        config = {
            **CONFIG,
            "invitation_gate": {
                "require_any_en": ["drop your project", "show me what you built"],
                "require_any_ja": ["宣伝どうぞ", "作品貼って", "アプリ貼って"],
                "reject_any": ["no promo", "宣伝禁止"],
            },
        }
        self.assertFalse(scout._invitation_gate("自作アプリの攻略本を作った！", "ja", config))
        self.assertTrue(scout._invitation_gate("個人開発のみなさん、アプリ貼ってください！", "ja", config))


    def test_topic_gate_accepts_chatgpt_story_and_fortune_threads(self):
        config = {
            **CONFIG,
            "topic_gate": {
                "require_domain_ja": ["chatgpt", "生成ai", "ai"],
                "require_domain_en": ["chatgpt", "generative ai", "ai"],
                "require_context_ja": ["使い方", "物語", "小説", "占い", "タロット"],
                "require_context_en": ["how do you use", "story", "fiction", "fortune", "tarot"],
            },
        }
        self.assertTrue(scout._topic_gate("ChatGPTで物語を作ってる人いる？", "ja", config))
        self.assertTrue(scout._topic_gate("ChatGPT占い、みんなどう使ってる？", "ja", config))
        self.assertTrue(scout._topic_gate("How do you use ChatGPT for writing stories?", "en", config))
        self.assertFalse(scout._topic_gate("今日は普通の小説を読んだ", "ja", config))

    def test_topic_product_fit_routes_story_and_fortune(self):
        config = {
            **CONFIG,
            "topic_gate": {
                "require_domain_ja": ["chatgpt", "ai"],
                "require_domain_en": ["chatgpt", "ai"],
                "require_context_ja": ["使い方", "物語", "小説", "占い", "タロット"],
                "require_context_en": ["how do you use", "story", "fiction", "fortune", "tarot"],
            },
            "relevance": {
                "off_topic_any": [],
                "generic_builder_any": ["chatgpt", "ai"],
                "product_affinity": {
                    "project-vault": {
                        "terms": ["chatgpt", "使い方", "how do you use"],
                        "generic_bias": 3,
                    },
                    "tanuki-chronicle": {
                        "terms": ["chatgpt", "物語", "小説", "story", "fiction"],
                        "generic_bias": 2,
                    },
                    "tanuki-fortune": {
                        "terms": ["chatgpt", "占い", "タロット", "fortune", "tarot"],
                        "generic_bias": 2,
                    },
                },
            },
            "draft_products": [
                {
                    "key": "project-vault",
                    "name": "Project Vault",
                    "languages": ["ja", "en"],
                    "url": "https://example.com/vault",
                    "drafts": {"ja": ["Vault"], "en": ["Vault"]},
                },
                {
                    "key": "tanuki-chronicle",
                    "name": "Tanuki Chronicle",
                    "languages": ["ja", "en"],
                    "url": "https://example.com/chronicle",
                    "drafts": {"ja": ["Chronicle"], "en": ["Chronicle"]},
                },
                {
                    "key": "tanuki-fortune",
                    "name": "Tanuki Fortune",
                    "languages": ["ja", "en"],
                    "url": "https://example.com/fortune",
                    "drafts": {"ja": ["Fortune"], "en": ["Fortune"]},
                },
            ],
        }

        story = scout._draft_for("story", "ja", "ChatGPTで小説と物語を作ってる", config, placement_kind="topic")
        fortune = scout._draft_for("fortune", "ja", "ChatGPTで占いとタロットを試してる", config, placement_kind="topic")
        usage = scout._draft_for("usage", "ja", "ChatGPTの使い方、みんなどうしてる？", config, placement_kind="topic")

        self.assertEqual(story[0], "tanuki-chronicle")
        self.assertEqual(fortune[0], "tanuki-fortune")
        self.assertEqual(usage[0], "project-vault")
        self.assertIn("Chronicle", story[2])
        self.assertNotIn("スレお借りします", story[2])

    def test_topic_candidate_is_manual_only(self):
        config = {
            **CONFIG,
            "topic_gate": {
                "require_domain_ja": ["chatgpt", "ai"],
                "require_domain_en": ["chatgpt", "ai"],
                "require_context_ja": ["使い方", "物語"],
                "require_context_en": ["how do you use", "story"],
            },
        }
        now = datetime(2026, 9, 29, 12, 0, tzinfo=timezone.utc)
        payload = {
            "data": [
                {
                    "id": "topic-1",
                    "text": "ChatGPTの使い方、みんなどうしてる？",
                    "author_id": "u1",
                    "created_at": "2026-09-29T10:00:00Z",
                    "public_metrics": {
                        "reply_count": 5,
                        "like_count": 10,
                        "retweet_count": 0,
                        "quote_count": 0,
                    },
                }
            ]
        }
        rows = scout._collect_topic_candidates(payload, "ja", "chatgpt-topic", config, set(), now)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["placement_kind"], "topic")
        self.assertEqual(rows[0]["send_status"], "MANUAL_ONLY_TOPIC_PLACEMENT")



if __name__ == "__main__":
    unittest.main()
