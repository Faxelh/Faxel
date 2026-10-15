"""
Assemblage MP4 sans FFmpeg : chaque échantillon (image / bloc de son) du
fichier produit doit être identique, octet pour octet et au même instant,
à celui des fichiers d'origine.
"""

import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest

from tests import support  # noqa: F401  (chemins)
from faxel.core import mp4mux

FFMPEG = shutil.which("ffmpeg")


def samples(path, kind):
    source = mp4mux.Source(path)
    track = source.track(kind)
    hashes = []
    with open(path, "rb") as handle:
        for offset, size in zip(track.offsets, track.sizes):
            handle.seek(offset)
            hashes.append(hashlib.md5(handle.read(size)).hexdigest())
    dts = 0
    times = []
    for duration, cts in zip(track.durations, track.cts):
        times.append((dts, dts + cts))
        dts += duration
    return track, hashes, times


class MergeTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="faxel-mux-")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def check_merge(self, video, audio):
        out = os.path.join(self.dir, f"{video}+{audio}.mp4")
        mp4mux.merge(support.fixture(video), support.fixture(audio), out)
        self.assertTrue(mp4mux.is_mp4(out))
        info = mp4mux.probe(out)
        self.assertTrue(info["video"] and info["audio"])
        self.assertFalse(info["fragmented"])
        with open(out, "rb") as handle:
            kinds = [box[0] for box in mp4mux._top_level(handle)[0]]
        self.assertEqual(kinds[0], "ftyp")
        self.assertLess(kinds.index("moov"), kinds.index("mdat"))  # index au début (lecture immédiate)

        for source, kind in ((video, "vide"), (audio, "soun")):
            src_track, src_hashes, src_times = samples(support.fixture(source), kind)
            out_track, out_hashes, out_times = samples(out, kind)
            self.assertEqual(src_hashes, out_hashes, f"données {kind} différentes")
            self.assertEqual(src_track.sync, out_track.sync)
            self.assertEqual(src_times, out_times, f"horodatage {kind} différent")
            self.assertEqual(src_track.timescale, out_track.timescale)
        if FFMPEG:
            result = subprocess.run([FFMPEG, "-v", "error", "-i", out, "-f", "null", "-"],
                                    capture_output=True, text=True)
            self.assertEqual(result.stderr.strip(), "", result.stderr)
        return out

    def test_plain_files(self):
        self.check_merge("v_plain.mp4", "a_plain.m4a")

    def test_fragmented_dash_files(self):
        self.check_merge("v_frag.mp4", "a_frag.m4a")

    def test_absolute_base_offsets(self):
        self.check_merge("v_frag_abs.mp4", "a_frag.m4a")

    def test_mixed(self):
        self.check_merge("v_plain.mp4", "a_frag.m4a")

    def test_remux_audio_only(self):
        out = os.path.join(self.dir, "son.m4a")
        mp4mux.remux(support.fixture("a_frag.m4a"), out, kinds=("soun",))
        info = mp4mux.probe(out)
        self.assertTrue(info["audio"])
        self.assertFalse(info["video"])
        self.assertFalse(info["fragmented"])
        self.assertEqual(samples(out, "soun")[1], samples(support.fixture("a_frag.m4a"), "soun")[1])
        with open(out, "rb") as handle:
            self.assertEqual(handle.read(12)[8:12], b"M4A ")

    def test_extract_audio_from_combined(self):
        out = os.path.join(self.dir, "extrait.m4a")
        mp4mux.remux(support.fixture("av_plain.mp4"), out, kinds=("soun",))
        self.assertEqual(samples(out, "soun")[1], samples(support.fixture("av_plain.mp4"), "soun")[1])

    def test_bframes_edit_list(self):
        """Fichier fragmenté avec images B : une liste d'éditions remet la 1re image à 0."""
        out = self.check_merge("v_frag.mp4", "a_frag.m4a")
        video = mp4mux.Source(out).track("vide")
        self.assertTrue(video.edits)
        self.assertGreater(video.edits[-1][1], 0)

    def test_cancel_removes_partial_file(self):
        out = os.path.join(self.dir, "annule.mp4")
        with self.assertRaises(mp4mux.Cancelled):
            mp4mux.merge(support.fixture("v_frag.mp4"), support.fixture("a_frag.m4a"), out,
                         cancel=lambda: True)
        self.assertFalse(os.path.exists(out))
        self.assertFalse(os.path.exists(out + ".faxelmux"))

    def test_progress_reaches_one(self):
        values = []
        mp4mux.merge(support.fixture("v_frag.mp4"), support.fixture("a_frag.m4a"),
                     os.path.join(self.dir, "p.mp4"), progress=values.append)
        self.assertTrue(values)
        self.assertAlmostEqual(values[-1], 1.0)

    def test_not_mp4(self):
        path = os.path.join(self.dir, "faux.mp4")
        with open(path, "wb") as handle:
            handle.write(b"\x47" * 1000)  # MPEG-TS
        self.assertFalse(mp4mux.is_mp4(path))
        with self.assertRaises(mp4mux.Mp4Error):
            mp4mux.remux(path, os.path.join(self.dir, "x.mp4"))

    def test_truncated_file(self):
        path = os.path.join(self.dir, "coupe.mp4")
        with open(support.fixture("v_frag.mp4"), "rb") as handle:
            data = handle.read()
        with open(path, "wb") as handle:
            handle.write(data[:600])  # moov incomplet
        with self.assertRaises(mp4mux.Mp4Error):
            mp4mux.merge(path, support.fixture("a_frag.m4a"), os.path.join(self.dir, "y.mp4"))


if __name__ == "__main__":
    unittest.main()
