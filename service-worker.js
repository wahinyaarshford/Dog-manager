// Bump this number whenever you want to force every device to drop its old cache.
const CACHE_NAME = 'dog-care-manager-v4';
const SUPABASE_SCRIPT = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';

// The app itself. If one of these fails to download, installation fails.
const CORE = ['./', './index.html', './manifest.webmanifest'];
// Icons are nice to have offline, but a missing icon must never break installation.
const ICONS = [
  './icons/icon.svg',
  './icons/icon-180.png',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png'
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(CORE);
    await Promise.allSettled([...ICONS, SUPABASE_SCRIPT].map(url => cache.add(url)));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys.filter(k => k.startsWith('dog-care-manager-') && k !== CACHE_NAME).map(k => caches.delete(k))
    );
    await self.clients.claim();
  })());
});

// Network first, so a new version of the app shows up as soon as the device is online.
// If the network is missing or slower than 4 seconds, fall back to the saved copy.
function fetchWithTimeout(request, ms) {
  return Promise.race([
    fetch(request),
    new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), ms))
  ]);
}

async function networkFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = await fetchWithTimeout(request, 4000);
    if (response && response.ok && response.type === 'basic') cache.put(request, response.clone());
    return response;
  } catch (error) {
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;
    if (request.mode === 'navigate') {
      const page = await cache.match('./index.html');
      if (page) return page;
    }
    throw error;
  }
}

async function cachedSupabaseScript(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetchWithTimeout(request, 4000);
  if (response && response.ok && response.type !== 'opaque') {
    try { await cache.put(request, response.clone()); }
    catch (error) { console.error('Dog Care Manager: could not cache Supabase library.', error); }
  }
  return response;
}

self.addEventListener('fetch', event => {
  const { request } = event;
  if (request.method !== 'GET') return;
  if (request.url === SUPABASE_SCRIPT) {
    event.respondWith(cachedSupabaseScript(request));
    return;
  }
  if (new URL(request.url).origin !== self.location.origin) return;
  event.respondWith(networkFirst(request));
});
