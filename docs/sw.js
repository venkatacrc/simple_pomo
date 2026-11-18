// Stale-while-revalidate service worker: opens instantly/offline, updates in the background.
// Bump VERSION to force old caches to be dropped.
const VERSION = 'v1';
const CACHE = `simple-pomo-${VERSION}`;
const CORE = [
  './', 'index.html', 'styles.css', 'manifest.webmanifest',
  'js/main.js', 'js/core.js', 'js/timer.js',
  'js/ui/common.js', 'js/ui/sheets.js', 'js/ui/focus.js', 'js/ui/tasks.js',
  'js/ui/plan.js', 'js/ui/reports.js', 'js/ui/settings.js',
  'icons/icon-192.png', 'icons/icon-512.png', 'icons/apple-touch-icon.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(CORE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  e.respondWith(
    caches.open(CACHE).then(async (cache) => {
      const cached = await cache.match(req, { ignoreSearch: true });
      const network = fetch(req).then((res) => {
        if (res && res.ok) cache.put(req, res.clone());
        return res;
      }).catch(() => cached);
      return cached || network;
    }),
  );
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window' }).then((list) => {
    if (list.length) return list[0].focus();
    return self.clients.openWindow('./');
  }));
});
