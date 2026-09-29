import unittest

import placement_console


class HuntingLaneReplyTests(unittest.TestCase):
    def test_every_hunting_lane_has_reply_copy(self):
        self.assertGreaterEqual(len(placement_console.HUNTING_LANES), 1)
        for lane in placement_console.HUNTING_LANES:
            self.assertTrue(str(lane.get("draft_reply") or "").strip(), lane.get("target_post_id"))
            self.assertTrue(str(lane.get("draft_product_name") or "").strip(), lane.get("target_post_id"))
            self.assertTrue(str(lane.get("search_query") or "").strip(), lane.get("target_post_id"))


if __name__ == "__main__":
    unittest.main()
