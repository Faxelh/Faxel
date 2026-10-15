"""
Moteur de téléchargement de bout en bout avec le faux yt-dlp (PC
uniquement : sur iPhone le vrai yt-dlp est présent et ces tests sont sautés).
"""

import os
import threading
import time
import unittest
from unittest import mock

from tests import support
from faxel.core import mp4mux

if not support.REAL_YTDLP:
    from faxel.engine import downloader, manager


def wait(predicate, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


@unittest.skipIf(support.REAL_YTDLP, "tests réservés au faux yt-dlp")
class DownloaderTest(unittest.TestCase):
    def setUp(self):
        self.cfg = support.TempConfig().__enter__()
        from faxel.core import storage
        self.history = storage.get_history()
        self.events = []

    def tearDown(self):
        self.cfg.__exit__(None, None, None)

    def run_job(self, url, media="video", quality=None, stop=lambda: False):
        job = {"id": "j" + str(len(self.events)), "url": url, "media_type": media, "quality": quality}
        return downloader.download(job, lambda kind, data: self.events.append((kind, data)), stop, self.history)

    def test_dash_merge(self):
        result = self.run_job("https://test.invalid/dash/abc/Ma vidéo")
        item = result["items"][0]
        self.assertTrue(item["filepath"].endswith("Ma vidéo.mp4"))
        self.assertIn(os.path.join("Documents", "Autres", "Vidéos"), item["filepath"])
        info = mp4mux.probe(item["filepath"])
        self.assertTrue(info["video"] and info["audio"] and not info["fragmented"])
        self.assertEqual(item["height"], 720)
        fractions = [d["fraction"] for k, d in self.events if k == "progress"]
        self.assertEqual(fractions[-1], 1.0)
        self.assertEqual(fractions, sorted(fractions))
        # dossier de travail nettoyé
        from faxel.core import config
        self.assertFalse(os.path.exists(os.path.join(config.WORK_DIR, "j0")))

    def test_quality_limit(self):
        item = self.run_job("https://test.invalid/dash/q", quality="480p")["items"][0]
        self.assertEqual(item["height"], 480)

    def test_single_moov_at_end_is_rewritten(self):
        item = self.run_job("https://test.invalid/single/s1")["items"][0]
        self.assertTrue(downloader._moov_first(item["filepath"]))

    def test_audio(self):
        item = self.run_job("https://test.invalid/audio/a1", media="audio")["items"][0]
        self.assertTrue(item["filepath"].endswith(".m4a"))
        self.assertIn(os.path.join("Audio"), item["filepath"])
        info = mp4mux.probe(item["filepath"])
        self.assertTrue(info["audio"] and not info["video"])

    def test_extract_audio_when_no_audio_only(self):
        item = self.run_job("https://test.invalid/single/s2", media="audio")["items"][0]
        self.assertTrue(item["filepath"].endswith(".m4a"))

    def test_no_compatible_format(self):
        with self.assertRaises(downloader.FaxelError) as ctx:
            self.run_job("https://test.invalid/vp9only/v")
        self.assertEqual(downloader.explain(ctx.exception)[1], "format")

    def test_live_refused(self):
        with self.assertRaises(downloader.FaxelError) as ctx:
            self.run_job("https://test.invalid/live/l")
        self.assertEqual(downloader.explain(ctx.exception)[1], "live")

    def test_same_title_never_overwrites(self):
        first = self.run_job("https://test.invalid/dash/a/Même titre")["items"][0]["filepath"]
        second = self.run_job("https://test.invalid/dash/b/Même titre")["items"][0]["filepath"]
        self.assertNotEqual(first, second)
        self.assertTrue(os.path.exists(first) and os.path.exists(second))

    def test_cancel(self):
        with self.assertRaises(Exception) as ctx:
            self.run_job("https://test.invalid/slow/c", stop=lambda: True)
        self.assertEqual(downloader.explain(ctx.exception)[1], "cancelled")

    def test_analyze(self):
        info = downloader.analyze("https://test.invalid/dash/z/Titre")
        self.assertEqual(info["kind"], "video")
        self.assertEqual(info["title"], "Titre")
        self.assertIn("720p", info["qualities"])
        self.assertNotIn("1080p", info["qualities"])  # 1080 n'existe qu'en VP9
        playlist = downloader.analyze("https://test.invalid/playlist/p")
        self.assertEqual(playlist["kind"], "playlist")
        self.assertEqual(len(playlist["entries"]), 3)


@unittest.skipIf(support.REAL_YTDLP, "tests réservés au faux yt-dlp")
class ManagerTest(unittest.TestCase):
    def setUp(self):
        self.cfg = support.TempConfig().__enter__()
        from faxel.core import config, storage
        self.settings = config.get_settings()
        self.settings.update(max_parallel=2, auto_retry=True)
        self.history = storage.get_history()
        self.done = []
        self.manager = manager.DownloadManager(self.settings, self.history,
                                               on_success=lambda job_id, item: self.done.append(item))

    def tearDown(self):
        self.manager.shutdown(save=False)
        self.cfg.__exit__(None, None, None)

    def status(self, job_id):
        return self.manager.job(job_id)["status"]

    def test_download_and_history(self):
        job_id = self.manager.add("https://test.invalid/dash/h1/Histoire")
        self.assertTrue(wait(lambda: self.status(job_id) == "done"))
        self.assertEqual(len(self.done), 1)
        entries = self.history.entries()
        self.assertEqual(entries[0]["title"], "Histoire")
        self.assertTrue(entries[0]["relpath"].startswith("Autres"))
        events = [k for k, _i, _p in self.manager.poll_events()]
        self.assertIn("finished", events)

    def test_duplicate_skipped_then_forced(self):
        first = self.manager.add("https://test.invalid/dash/dup")
        self.assertTrue(wait(lambda: self.status(first) == "done"))
        second = self.manager.add("https://test.invalid/dash/dup")
        self.assertTrue(wait(lambda: self.status(second) == "skipped"))
        self.assertTrue(self.manager.retry(second, force=True))
        self.assertTrue(wait(lambda: self.status(second) == "done"))

    def test_pause_resume(self):
        job_id = self.manager.add("https://test.invalid/slow/p1")
        self.assertTrue(wait(lambda: self.manager.job(job_id)["fraction"] > 0.1))
        self.assertTrue(self.manager.pause(job_id))
        self.assertTrue(wait(lambda: job_id not in self.manager._running))
        self.assertEqual(self.status(job_id), "paused")
        self.assertTrue(self.manager.resume(job_id))
        self.assertTrue(wait(lambda: self.status(job_id) == "done", 30))

    def test_cancel(self):
        job_id = self.manager.add("https://test.invalid/slow/c1")
        self.assertTrue(wait(lambda: self.manager.job(job_id)["fraction"] > 0.05))
        self.manager.cancel(job_id)
        self.assertTrue(wait(lambda: job_id not in self.manager._running))
        self.assertEqual(self.status(job_id), "cancelled")
        from faxel.core import config
        self.assertFalse(os.path.exists(os.path.join(config.WORK_DIR, job_id)))

    def test_failure_message(self):
        job_id = self.manager.add("https://test.invalid/error/e/Video unavailable")
        self.assertTrue(wait(lambda: self.status(job_id) == "failed"))
        self.assertIn("introuvable", self.manager.job(job_id)["message"])

    def test_parallel_limit(self):
        ids = [self.manager.add(f"https://test.invalid/slow/x{i}") for i in range(4)]
        peak = 0
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline and not all(self.status(i) == "done" for i in ids):
            peak = max(peak, len(self.manager._running))
            time.sleep(0.02)
        self.assertTrue(all(self.status(i) == "done" for i in ids))
        self.assertLessEqual(peak, 2)

    def test_add_many_writes_queue_once(self):
        # Ajouter une grande playlist d'un coup ne doit écrire la file sur le
        # disque qu'une seule fois (et non une fois par vidéo) : c'est ce qui
        # bloquait l'interface plusieurs secondes avec une playlist de
        # plusieurs centaines de vidéos.
        items = [{"url": f"https://test.invalid/slow/many{i}", "media_type": "video"} for i in range(50)]
        with mock.patch("faxel.engine.manager.config.write_json_atomic") as saved:
            ids = self.manager.add_many(items)
        self.assertEqual(len(ids), 50)
        self.assertEqual(len(set(ids)), 50)
        self.assertEqual(saved.call_count, 1)
        snapshot_urls = {job["url"] for job in self.manager.snapshot()}
        for item in items:
            self.assertIn(item["url"], snapshot_urls)

    def test_saved_queue(self):
        self.manager.add("https://test.invalid/slow/q1")
        self.manager.pause_all()
        self.assertTrue(wait(lambda: not self.manager._running))
        other = manager.DownloadManager(self.settings, self.history)
        try:
            saved = other.saved_queue()
            self.assertEqual(len(saved), 1)
            self.assertEqual(other.resume_saved_queue(), 1)
        finally:
            other.shutdown(save=False)


class PlaylistsTest(unittest.TestCase):
    """Playlists (onglet Fichier) : indépendant de yt-dlp, pas de faux moteur requis."""

    def setUp(self):
        self.cfg = support.TempConfig().__enter__()
        from faxel.core import storage
        self.playlists = storage.get_playlists()

    def tearDown(self):
        self.cfg.__exit__(None, None, None)

    def test_create_add_remove_delete(self):
        from faxel.core import config
        path = os.path.join(config.DOCUMENTS_DIR, "TikTok", "Vidéos", "Une vidéo.mp4")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w").close()

        entry = self.playlists.create("Favoris")
        self.assertEqual(entry["items"], [])
        self.assertEqual(len(self.playlists.entries()), 1)

        self.assertTrue(self.playlists.add_item(entry["uid"], path, title="Une vidéo"))
        # Un deuxième ajout du même fichier ne duplique pas l'entrée.
        self.assertFalse(self.playlists.add_item(entry["uid"], path, title="Une vidéo"))
        stored = self.playlists.get(entry["uid"])
        self.assertEqual(len(stored["items"]), 1)
        self.assertEqual(stored["items"][0]["filepath"], path)

        self.assertTrue(self.playlists.remove_item(entry["uid"], path))
        self.assertEqual(len(self.playlists.get(entry["uid"])["items"]), 0)

        self.assertTrue(self.playlists.delete(entry["uid"]))
        self.assertIsNone(self.playlists.get(entry["uid"]))
        self.assertEqual(self.playlists.entries(), [])

    def test_survives_documents_folder_moving(self):
        # Comme l'historique : à chaque mise à jour de l'app sur iPhone, le
        # dossier Documents change de chemin. Les playlists doivent suivre
        # (chemin relatif retrouvé), pas pointer vers un dossier qui n'existe
        # plus.
        from faxel.core import config, storage
        path = os.path.join(config.DOCUMENTS_DIR, "YouTube", "Audio", "Chanson.m4a")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w").close()
        entry = self.playlists.create("Musique")
        self.playlists.add_item(entry["uid"], path, title="Chanson")

        new_documents = os.path.join(self.cfg.root, "Documents-v2")
        os.makedirs(os.path.join(new_documents, "YouTube", "Audio"), exist_ok=True)
        open(os.path.join(new_documents, "YouTube", "Audio", "Chanson.m4a"), "w").close()
        config.DOCUMENTS_DIR = new_documents

        storage._playlists = None
        moved = storage.get_playlists()
        reloaded = moved.get(entry["uid"])
        self.assertEqual(reloaded["items"][0]["filepath"],
                         os.path.join(new_documents, "YouTube", "Audio", "Chanson.m4a"))


if __name__ == "__main__":
    unittest.main()
