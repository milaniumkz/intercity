const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
test('background Firebase notification click uses app route before SDK default handler',async()=>{
 const handlers={},order=[],opened=[];let completed,stopped=false,closed=false;
 const self={location:{origin:'https://intercity.example'},registration:{showNotification(){}} ,addEventListener:(type,fn)=>{handlers[type]=fn;order.push(type)}};
 const clients={matchAll:async()=>[],openWindow:async url=>opened.push(url)};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../apps/mobile_flutter/web/firebase-messaging-sw.js'),'utf8'),{self,clients,URL,importScripts:()=>order.push('firebase'),firebase:{initializeApp(){},messaging:()=>({onBackgroundMessage(){}})}});
 assert.equal(order[0],'notificationclick');
 handlers.notificationclick({stopImmediatePropagation(){stopped=true},notification:{close(){closed=true},data:{FCM_MSG:{data:{type:'chat_message',route:'/intercity/request/trip?chat=1&chatMessageId=msg'}}}},waitUntil(p){completed=p}});
 await completed;assert(stopped);assert(closed);assert.deepEqual(opened,['https://intercity.example/#/intercity/request/trip?chat=1&chatMessageId=msg']);
});
