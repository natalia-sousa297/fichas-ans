// Fichas ANS: guarda o sistema no aparelho para abrir sem internet.
// Os dados das fichas ficam no próprio aparelho (cópia local) e no Supabase; aqui só ficam os arquivos do site.
const VERSAO = "fichas-v4";
const ARQUIVOS = [
  "./", "index.html", "config.js", "icon.svg", "manifest.webmanifest",
  "vendor/supabase.js", "vendor/jspdf.umd.min.js",
];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(VERSAO).then(c => c.addAll(ARQUIVOS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== VERSAO && k.startsWith("fichas-")).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// rede primeiro (para receber atualizações); se demorar ou falhar, usa a cópia guardada
async function redePrimeiro(req, chave) {
  const cache = await caches.open(VERSAO);
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 4000);
    const res = await fetch(req, { signal: ctrl.signal });
    clearTimeout(t);
    if (res.ok) cache.put(chave || req, res.clone());
    return res;
  } catch (_) {
    const hit = await cache.match(chave || req, { ignoreSearch: true });
    if (hit) return hit;
    throw _;
  }
}

// cópia guardada primeiro, atualizando por trás (bibliotecas, logo, fontes)
async function cacheAtualiza(req) {
  const cache = await caches.open(VERSAO);
  const hit = await cache.match(req, { ignoreSearch: true });
  const rede = fetch(req).then(res => { if (res.ok || res.type === "opaque") cache.put(req, res.clone()); return res; }).catch(() => null);
  return hit || (await rede) || Response.error();
}

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  // fontes do Google
  if (url.hostname === "fonts.googleapis.com" || url.hostname === "fonts.gstatic.com") {
    e.respondWith(cacheAtualiza(req));
    return;
  }
  if (url.origin !== self.location.origin) return; // Supabase e outros: direto na rede

  if (req.mode === "navigate") { e.respondWith(redePrimeiro(req, "index.html")); return; }
  if (url.pathname.endsWith("/config.js") || url.pathname.endsWith("/index.html")) { e.respondWith(redePrimeiro(req)); return; }
  e.respondWith(cacheAtualiza(req));
});
