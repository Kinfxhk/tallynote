// Tallynote's own service worker. Flutter's generated one unregisters itself,
// and a notepad that needs the network to open is not offline.
//
// Navigation is network-first so a new deploy shows immediately; everything
// else is stale-while-revalidate so the second open is instant and the app
// still starts with the network unplugged.
const CACHE = 'tallynote-v3';

// Best effort: one missing file must not fail the whole install.
const PRECACHE = [
  './',
  './index.html',
  './manifest.json',
  './version.json',
  './flutter_bootstrap.js',
  './main.dart.js',
  './canvaskit/canvaskit.js',
  './canvaskit/canvaskit.wasm',
  // Flutter refuses to start without its asset manifest, so this one is not
  // optional even though a missing file is otherwise ignored.
  './assets/AssetManifest.bin.json',
  './assets/AssetManifest.json',
  './assets/FontManifest.json',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      await Promise.all(
        PRECACHE.map((url) =>
          cache.add(new Request(url, { cache: 'reload' })).catch(() => {})
        )
      );
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))
      );
      await self.clients.claim();
    })()
  );
});

function put(request, response) {
  if (!response || !response.ok || response.type === 'opaque') return;
  const copy = response.clone();
  caches.open(CACHE).then((cache) => cache.put(request, copy)).catch(() => {});
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  // Exchange rates are the one thing that may leave the app; never cache them.
  if (url.origin !== self.location.origin) return;

  // The app itself is network-first: a fix must be live on the next open, not
  // the one after. Everything else stays stale-while-revalidate.
  const path = url.pathname;
  const isApp =
    request.mode === 'navigate' ||
    path.endsWith('/main.dart.js') ||
    path.endsWith('/flutter_bootstrap.js') ||
    path.endsWith('/version.json');

  if (isApp) {
    event.respondWith(
      (async () => {
        try {
          const fresh = await fetch(request);
          put(request, fresh.clone());
          return fresh;
        } catch (_) {
          const hit = await caches.match(request);
          if (hit) return hit;
          // Only a navigation may fall back to the shell document; a missing
          // script must fail as itself.
          if (request.mode === 'navigate') {
            const shell = await caches.match('./index.html');
            if (shell) return shell;
          }
          throw _;
        }
      })()
    );
    return;
  }

  event.respondWith(
    (async () => {
      const hit = await caches.match(request);
      const network = fetch(request)
        .then((response) => {
          put(request, response.clone());
          return response;
        })
        .catch(() => hit);
      return hit || network;
    })()
  );
});
