(() => {
  'use strict';
  const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (!ios) return;
  const installed = () => navigator.standalone === true || matchMedia('(display-mode: standalone)').matches;
  const storageKey = kind => `intercity.pwa.${kind}.dismissedUntil`;
  const read = key => { try { return Number(localStorage.getItem(key) || 0); } catch (_) { return 0; } };
  let panel, forced = false, busy = false, sequence = 0, lastStatus, message = '';
  const close = () => { const kind = installed() ? 'push' : 'install'; try { localStorage.setItem(storageKey(kind), String(Date.now() + 86400000)); } catch (_) {} forced = false; panel?.remove(); panel = null; };
  const element = (tag, text, parent) => { const e = document.createElement(tag); if (text) e.textContent = text; parent?.append(e); return e; };
  const button = (label, action, parent, secondary = false) => { const e = element('button', label, parent); e.type = 'button'; e.className = secondary ? 'pwa-secondary' : 'pwa-primary'; e.onclick = action; return e; };
  function render(status = {}) {
    if (/^#\/(identity|forgot-password)(?:[/?]|$)/.test(location.hash)) { panel?.remove(); panel = null; return; }
    lastStatus = status;
    const standalone = installed(), kind = standalone ? 'push' : 'install';
    if (!forced && read(storageKey(kind)) > Date.now()) return;
    if (standalone && !forced && (!status.signedIn || status.registered)) { panel?.remove(); panel = null; return; }
    panel?.remove(); panel = element('section', '', document.body); panel.id = 'intercity-pwa-prompt'; panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-labelledby', 'intercity-pwa-title');
    const x = button('×', close, panel, true); x.className = 'pwa-close'; x.setAttribute('aria-label', 'Закрыть подсказку');
    const logo = element('img', '', panel); logo.src = '/icons/Icon-192.png'; logo.alt = ''; logo.width = logo.height = 48;
    const h = element('h2', standalone ? 'Уведомления INTERCITY' : 'INTERCITY на главном экране', panel); h.id = 'intercity-pwa-title';
    if (!standalone) {
      element('p', 'Добавьте веб-версию на главный экран iPhone. Она будет открываться по своей иконке как отдельное приложение.', panel);
      const list = element('ol', '', panel);
      ['В браузере нажмите «Поделиться» — значок со стрелкой вверх.', 'Выберите «На экран “Домой”» / «Добавить на главный экран».', 'Подтвердите «Добавить», затем откройте INTERCITY по новой иконке.'].forEach(t => element('li', t, list));
      element('p', 'Если такого пункта нет в вашем браузере, откройте эту же ссылку в Safari. В установленной версии войдите в тот же аккаунт — приглашение уже сохранено на сервере.', panel);
      button('Скопировать ссылку для Safari', async () => { try { await navigator.clipboard.writeText(location.href); message = 'Ссылка скопирована. Откройте её в Safari.'; } catch (_) { message = 'Скопируйте адрес из адресной строки браузера и откройте его в Safari.'; } render(lastStatus); }, panel, true);
      button('Понятно, добавлю', close, panel);
    } else if (!status.signedIn) {
      element('p', 'Приложение уже добавлено на главный экран. Войдите в аккаунт, чтобы подключить уведомления о заказах, поездках и сообщениях.', panel);
      button('Войти', () => { close(); location.hash = '/login'; }, panel);
    } else if (status.permission === 'unsupported' || !('PushManager' in window)) {
      element('p', 'Push-уведомления на iPhone доступны начиная с iOS 16.4 в веб-приложении, открытом по иконке главного экрана. Обновите iOS и проверьте настройки устройства.', panel);
      button('Понятно', close, panel);
    } else if (status.permission === 'denied') {
      element('p', 'Уведомления отключены. Откройте «Настройки» iPhone → «Уведомления» → INTERCITY и включите допуск уведомлений. Затем вернитесь в приложение.', panel);
      button('Проверить снова', () => refresh(true), panel);
    } else if (status.registered) {
      element('p', 'Уведомления разрешены, устройство подключено к аккаунту. На уведомление можно нажать, чтобы открыть нужный заказ или чат.', panel);
      button('Готово', close, panel);
    } else {
      element('p', 'Разрешите уведомления о новых заказах, изменениях поездки и сообщениях в чате. Запрос iPhone появится после нажатия кнопки.', panel);
      const enable = button(busy ? 'Подключаем…' : status.permission === 'granted' ? 'Подключить уведомления' : 'Разрешить уведомления', async () => {
        if (busy) return;
        if (typeof window.intercityRequestWebPush !== 'function') { message = 'Приложение ещё загружается. Повторите через несколько секунд.'; render(lastStatus); return; }
        // Invoke immediately inside the user gesture; iOS rejects delayed permission requests.
        const pending = window.intercityRequestWebPush(); busy = true; render(lastStatus);
        try { const ok = await pending; message = ok ? '' : 'Не удалось подключить уведомления. Проверьте интернет и повторите попытку.'; } catch (_) { message = 'Не удалось подключить уведомления. Повторите попытку.'; }
        busy = false; refresh(true);
      }, panel); enable.disabled = busy;
      button('Позже', close, panel, true);
    }
    if (message) { const note = element('p', message, panel); note.setAttribute('role', 'status'); }
  }
  async function refresh(force = false) {
    if (force) forced = true;
    const id = ++sequence;
    if (!installed()) { render(); return; }
    if (typeof window.intercityWebPushStatus !== 'function') return;
    try { const status = await window.intercityWebPushStatus(); if (id === sequence) render(status); } catch (_) {}
  }
  window.intercityShowPwaHelp = () => { message = ''; refresh(true); };
  window.addEventListener('intercity-pwa-refresh', () => refresh());
  window.addEventListener('intercity-push-ready', () => refresh());
  window.addEventListener('hashchange', () => refresh());
  window.addEventListener('focus', () => refresh());
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
  matchMedia('(display-mode: standalone)').addEventListener?.('change', () => refresh());
  const start = () => setTimeout(() => refresh(), 1800);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
