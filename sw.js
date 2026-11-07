// Stackfall service worker: makes the game installable and playable offline.
//  - the page itself is fetched network-first, so a new deploy shows up on the next visit
//  - icons, manifest and the pixel font are served from cache and refreshed in the background
// Paths are relative so it works both on a domain root (Vercel) and under a
// sub-path (GitHub Pages).
const CACHE = "stackfall-v1";
const SHELL = [
  "./",
  "index.html",
  "manifest.webmanifest",
  "icons/icon-192.png",
  "icons/icon-512.png",
  "icons/icon-maskable-512.png",
  "icons/apple-touch-icon.png",
];
const FONT_HOSTS = ["fonts.googleapis.com", "fonts.gstatic.com"];
const NAV_TIMEOUT = 4000;   // on a bad connection fall back to the cached page after this long

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

async function networkFirst(req) {
  const cache = await caches.open(CACHE);
  const cached = () => cache.match(req).then(r => r || cache.match("index.html"));
  try {
    const res = await Promise.race([
      fetch(req),
      new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), NAV_TIMEOUT)),
    ]);
    if (res.ok) cache.put(req, res.clone());
    return res;
  } catch (err) {
    const hit = await cached();
    if (hit) return hit;
    throw err;
  }
}

async function staleWhileRevalidate(req) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(req);
  const refresh = fetch(req)
    .then(res => { if (res.ok || res.type === "opaque") cache.put(req, res.clone()); return res; })
    .catch(() => null);
  return hit || (await refresh) || Response.error();
}

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (req.mode === "navigate") e.respondWith(networkFirst(req));
  else if (url.origin === self.location.origin || FONT_HOSTS.includes(url.hostname)) {
    e.respondWith(staleWhileRevalidate(req));
  }
});
