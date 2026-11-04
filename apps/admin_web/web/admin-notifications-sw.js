self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('push',event=>{
 let data={};try{data=event.data.json();}catch(_){}
 event.waitUntil(self.registration.showNotification(data.title||'InterCity — проверка личности',{body:data.body||'Откройте очередь проверок.',tag:data.tag||'identity-review',icon:'/icons/Icon-192.png',data:{url:'/#/identity-reviews'}}));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();const url=new URL('/#/identity-reviews',self.location.origin).href;
 event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async windows=>{const page=windows.find(w=>new URL(w.url).origin===self.location.origin);if(page){await page.navigate(url);return page.focus();}return self.clients.openWindow(url);}));
});
