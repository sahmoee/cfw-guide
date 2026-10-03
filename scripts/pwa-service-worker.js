const BASE=new URL('./',self.location.href);
const PREFIX='cfw-pwa-'+encodeURIComponent(BASE.pathname)+'-';
const CACHE=PREFIX+'__VERSION__';
self.addEventListener('install',event=>event.waitUntil((async()=>{
 const response=await fetch(new URL('precache.json',BASE),{cache:'no-store'});if(!response.ok)throw Error('Precache manifest unavailable');
 const paths=await response.json(),cache=await caches.open(CACHE);
 try{for(let i=0;i<paths.length;i+=8)await Promise.all(paths.slice(i,i+8).map(async path=>{const url=new URL(path.split('/').map(encodeURIComponent).join('/'),BASE);const response=await fetch(url,{cache:'no-store'});if(!response.ok)throw Error('Incomplete offline copy');await cache.put(url,response);}));}
 catch(error){await caches.delete(CACHE);throw error;}
})()));
self.addEventListener('activate',event=>event.waitUntil((async()=>{for(const name of await caches.keys())if(name.startsWith(PREFIX)&&name!==CACHE)await caches.delete(name);await self.clients.claim();})()));
self.addEventListener('message',event=>{if(event.data==='ACTIVATE')self.skipWaiting();});
self.addEventListener('fetch',event=>{
 const url=new URL(event.request.url);if(event.request.method!=='GET'||url.origin!==BASE.origin||!url.pathname.startsWith(BASE.pathname))return;
 event.respondWith((async()=>{const cache=await caches.open(CACHE);const cached=await cache.match(event.request,{ignoreSearch:true});if(cached)return cached;try{return await fetch(event.request);}catch{if(event.request.mode==='navigate')return await cache.match(new URL('index.html',BASE));return new Response('Unavailable offline',{status:503});}})());
});
