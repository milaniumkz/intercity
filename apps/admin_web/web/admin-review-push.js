(() => {
 'use strict';let audio;
 window.intercityAdminPushPermission=async()=>{
  if (!('Notification' in window) || !('serviceWorker' in navigator) || !('PushManager' in window)) return false;
  try {const Audio=window.AudioContext||window.webkitAudioContext;if(Audio){audio ||= new Audio();audio.resume().catch(()=>{});}}catch(_){}
  return (await Notification.requestPermission())==='granted';
 };
 window.intercityAdminPushSubscribe=async key=>{
  if (!('Notification' in window)||Notification.permission!=='granted') throw new Error('Разрешите уведомления в настройках браузера');
  const worker=await navigator.serviceWorker.register('/admin-notifications-sw.js',{scope:'/admin-review-push/'});
  if (!worker.active) await new Promise((resolve,reject)=>{
   const current=worker.installing||worker.waiting;if(!current)return reject(new Error('Не удалось запустить уведомления'));
   const timeout=setTimeout(()=>reject(new Error('Ожидание уведомлений истекло')),15000);
   current.addEventListener('statechange',()=>{if(current.state==='activated'){clearTimeout(timeout);resolve();}});
  });
  const bytes=Uint8Array.from(atob(key.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(key.length/4)*4,'=')),c=>c.charCodeAt(0));
  const subscription=await worker.pushManager.getSubscription()||await worker.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:bytes});
  return JSON.stringify(subscription.toJSON());
 };
 window.intercityAdminReviewSound=()=>{try{if(audio?.state!=='running')return;const oscillator=audio.createOscillator(),gain=audio.createGain();oscillator.frequency.value=760;gain.gain.value=.08;oscillator.connect(gain);gain.connect(audio.destination);oscillator.start();oscillator.stop(audio.currentTime+.18);}catch(_){}};
})();
