"""
Pont Swift ↔ Python (faxel.bridge) : tout ce que l'interface SwiftUI
appelle, avec le faux yt-dlp.
"""

import json
import os
import shutil
import tempfile
import time
import unittest

from tests import support


def call(_op, **args):
    from faxel import bridge
    return json.loads(bridge.dispatch(_op, json.dumps(args)))


@unittest.skipIf(support.REAL_YTDLP, "tests réservés au faux yt-dlp")
class BridgeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from faxel import bridge
        from faxel.core import storage
        cls.root = tempfile.mkdtemp(prefix="faxel-bridge-")
        storage._history = None
        storage._playlists = None
        bridge.S.manager = None
        cls.docs = os.path.join(cls.root, "Documents")
        os.makedirs(cls.docs)
        # Un morceau laissé par l'ancienne version : retrouvé au démarrage.
        shutil.copyfile(support.fixture("a_frag.m4a"), os.path.join(cls.docs, "Ancien morceau.m4a"))
        cls.info = call("init", documents=cls.docs, data=os.path.join(cls.root, "data"),
                        cache=os.path.join(cls.root, "cache"), language="fr")

    @classmethod
    def tearDownClass(cls):
        call("shutdown")
        from faxel import bridge
        bridge.S.manager = None
        shutil.rmtree(cls.root, ignore_errors=True)

    def wait_done(self, timeout=20):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = call("poll")
            if not state["active"]:
                return state
            time.sleep(0.1)
        self.fail("imports toujours en cours")

    def test_00_errors_never_raise(self):
        self.assertIn("error", call("inconnue"))
        from faxel import bridge
        self.assertIn("error", json.loads(bridge.dispatch("import", "{pas du json")))

    def test_01_init_and_rescan(self):
        self.assertTrue(self.info["ok"])
        self.assertIn("python", self.info)
        titles = [e["title"] for e in call("library")["entries"]]
        self.assertIn("Ancien morceau", titles)

    def test_02_import_and_library(self):
        rev = call("poll")["rev"]
        result = call("import_text", text="regarde https://test.invalid/audio/b1/Titre%20Pont et voilà", media_type="audio")
        self.assertEqual(result["count"], 1)
        state = call("poll")
        self.assertTrue(state["jobs"])
        state = self.wait_done()
        lib = call("library")
        self.assertGreater(lib["rev"], rev)
        entry = next(e for e in lib["entries"] if e["title"] == "Titre Pont")
        self.assertTrue(entry["exists"])
        self.assertTrue(os.path.isfile(entry["filepath"]))

    def test_03_favorites_playlists(self):
        entry = next(e for e in call("library")["entries"] if e["title"] == "Titre Pont")
        self.assertTrue(call("toggle_favorite", entry=entry)["favorite"])
        self.assertIn(entry["filepath"], call("library")["favorites"])
        self.assertFalse(call("toggle_favorite", entry=entry)["favorite"])
        uid = call("playlist_create", name="Soirée")["uid"]
        self.assertTrue(call("playlist_add", uid=uid, entry=entry)["added"])
        self.assertFalse(call("playlist_add", uid=uid, entry=entry)["added"])
        self.assertTrue(call("playlist_rename", uid=uid, name="Route")["ok"])
        playlists = call("library")["playlists"]
        self.assertEqual(playlists[0]["name"], "Route")
        self.assertEqual(len(playlists[0]["items"]), 1)
        self.assertTrue(call("playlist_remove", uid=uid, filepath=entry["filepath"])["ok"])
        self.assertTrue(call("playlist_delete", uid=uid)["ok"])

    def test_04_vault(self):
        entry = next(e for e in call("library")["entries"] if e["title"] == "Titre Pont")
        moved = call("vault_add", entry=entry)
        self.assertTrue(moved["ok"])
        self.assertIn(os.sep + ".coffre" + os.sep, moved["filepath"])
        lib = call("library")
        self.assertNotIn(entry["filepath"], [e["filepath"] for e in lib["entries"]])
        item = lib["vault"][0]
        self.assertTrue(call("vault_remove", item=item)["ok"])
        lib = call("library")
        self.assertEqual(lib["vault"], [])
        self.assertIn(entry["filepath"], [e["filepath"] for e in lib["entries"]])

    def test_05_search_trending(self):
        self.assertTrue(call("search", query="soleil")["results"])
        self.assertTrue(call("trending")["results"])

    def test_06_backup_restore_and_settings(self):
        self.assertTrue(call("backup")["ok"])
        self.assertEqual(call("settings", values={"max_parallel": 3})["max_parallel"], 3)
        self.assertTrue(call("restore")["ok"])

    def test_07_delete(self):
        entry = next(e for e in call("library")["entries"] if e["title"] == "Ancien morceau")
        call("filesize", filepath=entry["filepath"], size=123)
        self.assertTrue(call("delete", entry=entry)["ok"])
        self.assertFalse(os.path.exists(entry["filepath"]))
        self.assertNotIn("Ancien morceau", [e["title"] for e in call("library")["entries"]])

    def test_08_jobs(self):
        job_id = call("import", items=[{"url": "https://test.invalid/slow/jb"}])["ids"][0]
        call("job", action="pause", id=job_id)
        call("job", action="cancel", id=job_id)
        call("job", action="clear_finished")
        self.wait_done()

    def test_09_analyze_and_video_import(self):
        info = call("analyze", url="https://test.invalid/dash/an1/Vid%C3%A9o%20Pont")["info"]
        self.assertEqual(info["kind"], "video")
        self.assertIn("720p", info["qualities"])
        ids = call("import", items=[{"url": "https://test.invalid/dash/an1/Vid%C3%A9o%20Pont"}],
                   media_type="video", quality="720p")["ids"]
        self.assertEqual(len(ids), 1)
        state = self.wait_done()
        job = next(j for j in state["jobs"] if j["id"] == ids[0])
        self.assertEqual(job["status"], "done")
        self.assertTrue(job["filepath"].endswith(".mp4"))


if __name__ == "__main__":
    unittest.main()


@unittest.skipIf(support.REAL_YTDLP, "tests réservés au faux yt-dlp")
class FilesSyncTest(unittest.TestCase):
    """Sons copiés avec 3uTools / l'app Fichiers : ajoutés, puis retirés s'ils disparaissent."""

    def test_rescan_adds_and_prunes(self):
        from faxel import bridge
        from faxel.core import storage
        root = tempfile.mkdtemp(prefix="faxel-sync-")
        try:
            storage._history = None
            storage._playlists = None
            bridge.S.manager = None
            docs = os.path.join(root, "Documents")
            os.makedirs(os.path.join(docs, "Albums", "Mon album"))
            song = os.path.join(docs, "Albums", "Mon album", "01 Titre.flac")
            shutil.copyfile(support.fixture("a_frag.m4a"), song)
            with open(os.path.join(docs, "notes.txt"), "w") as handle:
                handle.write("pas un son")
            call("init", documents=docs, data=os.path.join(root, "data"), cache=os.path.join(root, "cache"))
            paths = [e["filepath"] for e in call("library")["entries"]]
            self.assertEqual(paths, [song])
            self.assertEqual(call("library")["entries"][0]["media_type"], "audio")
            os.remove(song)
            self.assertEqual(call("rescan")["added"], 0)
            self.assertEqual(call("library")["entries"], [])
        finally:
            call("shutdown")
            bridge.S.manager = None
            storage._history = None
            storage._playlists = None
            shutil.rmtree(root, ignore_errors=True)
