"""
Chemins et réglages de Faxel Mobile.

Les dossiers sont fixés au démarrage par l'application (init) :
  - documents : fichiers téléchargés, visibles dans l'app Fichiers
                (« Sur mon iPhone › Faxel ») ;
  - data      : réglages, historique, file sauvegardée ;
  - cache     : fichiers en cours de téléchargement, cache de yt-dlp.
"""

import json
import os
import tempfile
import threading

APP_NAME = "Faxel"
APP_VERSION = "1.0.0"

DOCUMENTS_DIR = None
DATA_DIR = None
CACHE_DIR = None
WORK_DIR = None
SETTINGS_FILE = None
HISTORY_FILE = None
QUEUE_FILE = None
PLAYLISTS_FILE = None

MAX_PARALLEL_LIMIT = 3

DEFAULTS = {
    "max_parallel": 2,
    "skip_duplicates": True,
    "clean_titles": True,
    "save_to_photos": True,       # vidéos et photos ajoutées à l'app Photos
    "use_browser_cookies": True,  # réutiliser les connexions faites dans l'onglet Navigateur
    "auto_retry": True,
    "allow_av1": False,           # vidéos AV1 (2K/4K YouTube) si l'iPhone sait les décoder
    "default_media": "video",     # "video" ou "audio"
    "default_quality": "Meilleure",
    "home_page": "https://www.tiktok.com/",
    "keep_awake": True,           # écran allumé pendant les téléchargements
    "theme_mode": "system",       # "system" | "light" | "dark"
    "language": "system",         # "system" | "fr" | "en" (appliquée au prochain lancement)
    "app_lock": False,            # demander Face ID à l'ouverture de l'app
    "library_filter": "all",      # "all" | "video" | "audio"
}

THEME_MODES = ("system", "light", "dark")
LANGUAGES = ("system", "fr", "en")
LIBRARY_FILTERS = ("all", "video", "audio")


def ensure_dir(path):
    try:
        os.makedirs(path, exist_ok=True)
        return True
    except OSError:
        return False


def init(documents_dir, data_dir, cache_dir):
    """À appeler une fois au démarrage, avant tout le reste."""
    global DOCUMENTS_DIR, DATA_DIR, CACHE_DIR, WORK_DIR, SETTINGS_FILE, HISTORY_FILE, QUEUE_FILE
    global PLAYLISTS_FILE, _settings
    DOCUMENTS_DIR = str(documents_dir)
    DATA_DIR = str(data_dir)
    CACHE_DIR = str(cache_dir)
    WORK_DIR = os.path.join(CACHE_DIR, "en-cours")
    for folder in (DOCUMENTS_DIR, DATA_DIR, CACHE_DIR, WORK_DIR):
        ensure_dir(folder)
    SETTINGS_FILE = os.path.join(DATA_DIR, "settings.json")
    HISTORY_FILE = os.path.join(DATA_DIR, "history.json")
    QUEUE_FILE = os.path.join(DATA_DIR, "queue.json")
    PLAYLISTS_FILE = os.path.join(DATA_DIR, "playlists.json")
    _settings = None


def init_default():
    """Dossiers de secours (tests, ordinateur)."""
    base = os.path.join(tempfile.gettempdir(), "faxel-mobile")
    init(os.path.join(base, "Documents"), os.path.join(base, "data"), os.path.join(base, "cache"))


def read_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return default
    except (OSError, ValueError):
        # Fichier abîmé : on le met de côté plutôt que de planter.
        try:
            os.replace(path, path + ".abime")
        except OSError:
            pass
        return default


def write_json_atomic(path, data):
    folder = os.path.dirname(path)
    ensure_dir(folder)
    fd, temp = tempfile.mkstemp(prefix=".faxel-", suffix=".tmp", dir=folder)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=1)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, path)
    except BaseException:
        try:
            os.remove(temp)
        except OSError:
            pass
        raise


def _as_bool(value, default):
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in ("1", "true", "oui", "yes", "on"):
            return True
        if lowered in ("0", "false", "non", "no", "off"):
            return False
    return default


def validate_settings(values):
    clean = dict(DEFAULTS)
    if not isinstance(values, dict):
        values = {}
    try:
        parallel = int(values.get("max_parallel", DEFAULTS["max_parallel"]))
    except (TypeError, ValueError):
        parallel = DEFAULTS["max_parallel"]
    clean["max_parallel"] = max(1, min(MAX_PARALLEL_LIMIT, parallel))
    for key in ("skip_duplicates", "clean_titles", "save_to_photos", "use_browser_cookies",
                "auto_retry", "keep_awake", "app_lock", "allow_av1"):
        clean[key] = _as_bool(values.get(key, DEFAULTS[key]), DEFAULTS[key])
    media = values.get("default_media")
    clean["default_media"] = media if media in ("video", "audio") else DEFAULTS["default_media"]
    quality = values.get("default_quality")
    clean["default_quality"] = quality if isinstance(quality, str) and quality else DEFAULTS["default_quality"]
    home = values.get("home_page")
    clean["home_page"] = home if isinstance(home, str) and home.startswith("http") else DEFAULTS["home_page"]
    for key, allowed in (("theme_mode", THEME_MODES), ("language", LANGUAGES), ("library_filter", LIBRARY_FILTERS)):
        value = values.get(key)
        clean[key] = value if value in allowed else DEFAULTS[key]
    return clean


class Settings:
    def __init__(self, path):
        self.path = path
        self._lock = threading.RLock()
        self._values = validate_settings(read_json(path, {}))

    def get(self, key):
        with self._lock:
            return self._values.get(key, DEFAULTS.get(key))

    def as_dict(self):
        with self._lock:
            return dict(self._values)

    def update(self, **changes):
        with self._lock:
            merged = dict(self._values)
            merged.update(changes)
            self._values = validate_settings(merged)
            write_json_atomic(self.path, self._values)
            return dict(self._values)

    def reload(self):
        """Relit le fichier depuis le disque (ex. après une restauration de sauvegarde)."""
        with self._lock:
            self._values = validate_settings(read_json(self.path, {}))


_settings = None
_settings_lock = threading.Lock()


def get_settings():
    global _settings
    with _settings_lock:
        if _settings is None:
            if SETTINGS_FILE is None:
                init_default()
            _settings = Settings(SETTINGS_FILE)
        return _settings
