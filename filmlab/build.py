#!/usr/bin/env python3
"""Build FilmLab from src/app.html.

Outputs
  www/                 installable web app (index.html, manifest, service worker, icons)
  FilmLab.html         the same app as one self-contained file
  FilmLab.zip          www/ zipped for download
  --artifact PATH      optional: page body only, for publishing as a claude.ai artifact
"""
import base64
import hashlib
import json
import pathlib
import shutil
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / "src" / "app.html"
ASSETS = ROOT / "assets"
WWW = ROOT / "www"

SAMPLES = [
    ("portrait.jpg", "宇航员肖像", "NASA · 公有领域"),
    ("dusk.jpg", "黄昏发射台", "SpaceX · 公有领域"),
    ("espresso.jpg", "意式浓缩", "Rachel Michetti · CC0"),
    ("cat.jpg", "猫", "Stefan van der Walt · CC0"),
]

HEAD = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="FilmLab">
<meta name="theme-color" content="#0f0d0c">
<meta name="description" content="28 种胶片模拟、彩色暗房放大机、试条与色环，在 iPhone 上冲印你的照片。">
{pwa}<style>:root{{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}}</style>
</head>
<body>
"""
PWA_LINKS = '<link rel="manifest" href="manifest.webmanifest">\n<link rel="apple-touch-icon" href="icons/icon-180.png">\n<link rel="icon" href="icons/icon-192.png">\n'
TAIL = "\n</body>\n</html>\n"

MANIFEST = {
    "name": "FilmLab 胶片暗房",
    "short_name": "FilmLab",
    "description": "胶片模拟与彩色暗房",
    "start_url": "./",
    "scope": "./",
    "display": "standalone",
    "orientation": "portrait",
    "background_color": "#0f0d0c",
    "theme_color": "#0f0d0c",
    "lang": "zh-CN",
    "icons": [
        {"src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png"},
        {"src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable"},
    ],
}

SW = """// FilmLab service worker: app shell cache-first, Google Fonts cached at runtime.
const CACHE = 'filmlab-{version}';
const SHELL = ['./', './index.html', './manifest.webmanifest', './icons/icon-180.png', './icons/icon-192.png', './icons/icon-512.png'];
self.addEventListener('install', e => {{
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
}});
self.addEventListener('activate', e => {{
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
}});
self.addEventListener('fetch', e => {{
  const req = e.request;
  if (req.method !== 'GET') return;
  e.respondWith(caches.match(req, {{ ignoreSearch: true }}).then(hit => hit || fetch(req).then(res => {{
    if (res && (res.ok || res.type === 'opaque')) {{ const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }}
    return res;
  }}).catch(() => hit)));
}});
"""


def samples_script() -> str:
    items = []
    for fname, name, credit in SAMPLES:
        data = base64.b64encode((ASSETS / "samples" / fname).read_bytes()).decode()
        items.append({"src": "data:image/jpeg;base64," + data, "name": name, "credit": credit})
    return "<script>window.FILMLAB_SAMPLES=" + json.dumps(items, ensure_ascii=False) + ";</script>"


def body() -> str:
    src = SRC.read_text(encoding="utf-8")
    tag = '<script src="samples.js"></script>'
    if tag not in src:
        sys.exit("samples.js tag not found in src/app.html")
    return src.replace(tag, samples_script())


def main() -> None:
    page = body()
    version = hashlib.sha1(page.encode()).hexdigest()[:10]

    if WWW.exists():
        shutil.rmtree(WWW)
    (WWW / "icons").mkdir(parents=True)
    (WWW / "index.html").write_text(HEAD.format(pwa=PWA_LINKS) + page + TAIL, encoding="utf-8")
    (WWW / "manifest.webmanifest").write_text(json.dumps(MANIFEST, ensure_ascii=False, indent=2), encoding="utf-8")
    (WWW / "sw.js").write_text(SW.format(version=version), encoding="utf-8")
    for icon in (ASSETS / "icons").glob("*.png"):
        shutil.copy(icon, WWW / "icons" / icon.name)

    (ROOT / "FilmLab.html").write_text(HEAD.format(pwa="") + page + TAIL, encoding="utf-8")

    with zipfile.ZipFile(ROOT / "FilmLab.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(WWW.rglob("*")):
            if f.is_file():
                z.write(f, pathlib.Path("FilmLab") / f.relative_to(WWW))

    if "--artifact" in sys.argv:
        out = pathlib.Path(sys.argv[sys.argv.index("--artifact") + 1])
        out.write_text(page, encoding="utf-8")
        print("artifact page:", out)
    print("built version", version)


if __name__ == "__main__":
    main()
