importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBx5o8anmvNDDubNHjEEVKWLRxddM-BERE',
  appId: '1:176647550231:web:6e778252e634289c6d7352',
  messagingSenderId: '176647550231',
  projectId: 'inter-city-pkzpps',
  authDomain: 'inter-city-pkzpps.firebaseapp.com',
  storageBucket: 'inter-city-pkzpps.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  // FCM displays notification messages itself; only display data-only messages.
  if (payload.notification) return;
  const notification = payload.notification || {};
  const data = payload.data || {};
  const title = notification.title || 'INTERCITY';
  const options = {
    body: notification.body || '',
    icon: notification.image || '/icons/Icon-192.png',
    badge: '/icons/Icon-maskable-192.png',
    tag: data.tag || `remote-${payload.messageId || Date.now()}`,
    data: {
      route: data.route || '/profile',
      ...data,
    },
  };

  self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const notificationData = event.notification.data || {};
  // Automatically displayed FCM notifications wrap our payload in FCM_MSG.
  const payload = notificationData.FCM_MSG?.data || notificationData;
  const targetRoute = payload.route || '/profile';
  const targetUrl = new URL(targetRoute.startsWith('/#') ? targetRoute : `/#${targetRoute}`, self.location.origin).href;

  event.waitUntil((async () => {
    const clientsList = await clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });

    for (const client of clientsList) {
      if ('focus' in client) {
        await client.focus();
      }
      if ('postMessage' in client) {
        client.postMessage({
          type: 'notification-click',
          payload,
        });
      }
      if ('navigate' in client && client.url !== targetUrl) {
        await client.navigate(targetUrl);
      }
      return;
    }

    await clients.openWindow(targetUrl);
  })());
});
