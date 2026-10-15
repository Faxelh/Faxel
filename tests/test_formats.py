import unittest

from tests import support  # noqa: F401
from faxel.core import formats, platforms


def f(format_id, **kw):
    data = {"format_id": format_id, "protocol": "https"}
    data.update(kw)
    return data


YOUTUBE = [
    f("251", ext="webm", vcodec="none", acodec="opus", abr=130),
    f("140", ext="m4a", container="m4a_dash", vcodec="none", acodec="mp4a.40.2", abr=129),
    f("139", ext="m4a", container="m4a_dash", vcodec="none", acodec="mp4a.40.5", abr=48),
    f("18", ext="mp4", vcodec="avc1.42001E", acodec="mp4a.40.2", height=360, tbr=500),
    f("134", ext="mp4", container="mp4_dash", vcodec="avc1.4d401e", acodec="none", height=360, tbr=300),
    f("136", ext="mp4", container="mp4_dash", vcodec="avc1.4d401f", acodec="none", height=720, tbr=1200),
    f("137", ext="mp4", container="mp4_dash", vcodec="avc1.640028", acodec="none", height=1080, tbr=2500),
    f("248", ext="webm", container="webm_dash", vcodec="vp9", acodec="none", height=1080, tbr=2000),
    f("313", ext="webm", vcodec="vp9", acodec="none", height=2160, tbr=12000),
    f("401", ext="mp4", container="mp4_dash", vcodec="av01.0.12M.08", acodec="none", height=2160),
    f("hls-1080", ext="mp4", protocol="m3u8_native", vcodec="avc1.640028", acodec="mp4a.40.2", height=1080),
]


class ChooseTest(unittest.TestCase):
    def test_youtube_best_is_h264_1080_plus_aac(self):
        plan = formats.choose(YOUTUBE, "video", formats.BEST)
        self.assertEqual(plan["mode"], "merge")
        self.assertEqual(plan["video"]["format_id"], "137")
        self.assertEqual(plan["audio"]["format_id"], "140")

    def test_quality_limit(self):
        plan = formats.choose(YOUTUBE, "video", "720p")
        self.assertEqual(plan["video"]["format_id"], "136")

    def test_quality_below_everything_takes_smallest(self):
        plan = formats.choose(YOUTUBE, "video", "144p")
        self.assertEqual(plan["video"]["height"], 360)

    def test_audio_mode_picks_aac(self):
        plan = formats.choose(YOUTUBE, "audio")
        self.assertEqual(plan["mode"], "audio")
        self.assertEqual(plan["audio"]["format_id"], "140")

    def test_qualities_only_compatible(self):
        labels = formats.qualities_from_formats(YOUTUBE)
        self.assertIn("1080p", labels)
        self.assertNotIn("2160p (4K)", labels)  # 4K uniquement en VP9/AV1

    def test_tiktok_combined(self):
        tiktok = [
            f("h264_540p", ext="mp4", vcodec="h264", acodec="aac", height=1024, width=576),
            f("bytevc1_720p", ext="mp4", vcodec="bytevc1", acodec="aac", height=1280, width=720),
        ]
        plan = formats.choose(tiktok, "video")
        self.assertEqual(plan["mode"], "single")
        # Même hauteur préférée : H.264 ; ici le HEVC est plus grand, il gagne.
        self.assertEqual(plan["video"]["format_id"], "bytevc1_720p")
        audio = formats.choose(tiktok, "audio")
        self.assertEqual(audio["mode"], "extract_audio")

    def test_facebook_progressive_unknown_codecs(self):
        facebook = [f("sd", ext="mp4"), f("hd", ext="mp4")]
        plan = formats.choose(facebook, "video")
        self.assertIsNotNone(plan)
        self.assertEqual(plan["mode"], "single")

    def test_only_webm(self):
        self.assertIsNone(formats.choose([YOUTUBE[0], YOUTUBE[7]], "video"))
        self.assertIsNone(formats.choose([YOUTUBE[0]], "audio"))

    def test_hls_last_resort(self):
        plan = formats.choose([YOUTUBE[-1]], "video")
        self.assertEqual(plan["video"]["format_id"], "hls-1080")

    def test_drm_excluded(self):
        self.assertIsNone(formats.choose([f("x", ext="mp4", vcodec="avc1", acodec="mp4a", has_drm=True)],
                                         "video"))


class TextTest(unittest.TestCase):
    def test_texts(self):
        self.assertEqual(formats.duration_text(75), "1:15")
        self.assertEqual(formats.size_text(2048), "2,0 Ko")
        self.assertEqual(formats.short("a" * 10, 5), "aaaa…")


class PlatformTest(unittest.TestCase):
    def test_detect(self):
        self.assertEqual(platforms.detect_platform("https://vt.tiktok.com/ZSbBPUVxx/"), "tiktok")
        self.assertEqual(platforms.video_id_from_url("https://m.youtube.com/shorts/abcdefghijk"), "abcdefghijk")


if __name__ == "__main__":
    unittest.main()
