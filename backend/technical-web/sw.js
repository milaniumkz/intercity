'use strict';
self.addEventListener('push', (event) => {
    let data = {};
    try {
        data = event.data.json();
    } catch {}
    const url =
        typeof data.url === 'string' &&
        data.url.startsWith('/api/technical/panel/#issues/')
            ? data.url
            : '/api/technical/panel/';
    event.waitUntil(
        self.registration.showNotification(
            'INTERCITY: техническое уведомление',
            {
                body: 'Откройте техническую панель для просмотра события',
                tag: url,
                data: { url },
            },
        ),
    );
});
self.addEventListener('notificationclick', (event) => {
    event.notification.close();
    const url = new URL(
        event.notification.data?.url || '/api/technical/panel/',
        self.location.origin,
    ).href;
    event.waitUntil(
        clients
            .matchAll({ type: 'window', includeUncontrolled: true })
            .then(async (list) => {
                const target = list.find((c) =>
                    c.url.startsWith(self.location.origin + '/api/technical/'),
                );
                if (target) {
                    await target.navigate(url);
                    return target.focus();
                }
                return clients.openWindow(url);
            }),
    );
});
