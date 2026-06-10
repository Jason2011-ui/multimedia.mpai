const CACHE_NAME = 'mm-app-shell-v1';
const APP_SHELL = [
  './index.html',
  './manifest.webmanifest',
  './assets/mm-logo-identity.png'
];

const OFFLINE_HTML = `<!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>MM Offline</title>
  <style>
    body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f3e4e4;font-family:Arial,sans-serif;color:#1a1c20}
    main{width:min(420px,calc(100% - 32px));background:#fff;border:1px solid rgba(0,0,0,.06);border-radius:20px;padding:24px;text-align:center;box-shadow:0 14px 34px rgba(8,101,228,.08)}
    img{width:76px;height:76px;object-fit:contain;margin:0 auto 14px}
    h1{font-size:1.1rem;margin:0 0 8px}
    p{margin:0;color:#5a6270;font-size:.88rem;line-height:1.5;font-weight:700}
  </style>
</head>
<body>
  <main>
    <img src="./assets/mm-logo-identity.png" alt="MM">
    <h1>Koneksi belum tersedia</h1>
    <p>Aplikasi masih bisa dibuka sebagian. Sambungkan internet untuk memuat data absensi, Galery, dan Profile terbaru.</p>
  </main>
</body>
</html>`;

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE_NAME).then(cache=>cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE_NAME).map(key=>caches.delete(key))))
  );
  self.clients.claim();
});

self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET')return;

  if(req.mode==='navigate'){
    event.respondWith(
      fetch(req)
        .then(res=>{
          const copy=res.clone();
          caches.open(CACHE_NAME).then(cache=>cache.put('./index.html',copy));
          return res;
        })
        .catch(()=>caches.match('./index.html').then(cached=>cached||new Response(OFFLINE_HTML,{headers:{'Content-Type':'text/html;charset=utf-8'}})))
    );
    return;
  }

  event.respondWith(
    caches.match(req).then(cached=>cached||fetch(req).then(res=>{
      if(new URL(req.url).origin===self.location.origin){
        const copy=res.clone();
        caches.open(CACHE_NAME).then(cache=>cache.put(req,copy));
      }
      return res;
    }))
  );
});
