(() => {
  'use strict';
  const ios=/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1),android=/Android/i.test(navigator.userAgent);
  const installed=()=>navigator.standalone===true||matchMedia('(display-mode: standalone)').matches;
  const storageKey=kind=>`intercity.pwa.${kind}.dismissedUntil`;
  const read=key=>{try{return Number(localStorage.getItem(key)||0)}catch(_){return 0}};
  let panel,forced=false,busy=false,sequence=0,lastStatus={},message='',installPrompt;
  const element=(tag,text,parent)=>{const e=document.createElement(tag);if(text)e.textContent=text;parent?.append(e);return e};
  const button=(label,action,parent,secondary=false)=>{const e=element('button',label,parent);e.type='button';e.className=secondary?'pwa-secondary':'pwa-primary';e.onclick=action;return e};
  const close=()=>{try{localStorage.setItem(storageKey(installed()?'push':'install'),String(Date.now()+86400000))}catch(_){}forced=false;panel?.remove();panel=null};
  const copy=async()=>{try{await navigator.clipboard.writeText(location.href);message=ios?'Ссылка скопирована. Откройте её в Safari.':'Ссылка скопирована. Откройте её в Chrome.'}catch(_){message='Скопируйте адрес из адресной строки браузера.'}render(lastStatus)};
  async function requestInstall(){
    if(!installPrompt){forced=true;render(lastStatus);return;}
    const event=installPrompt;installPrompt=null;
    try{await event.prompt();const choice=await event.userChoice;message=choice.outcome==='accepted'?'Подтвердите установку и откройте InterCity по новой иконке.':'Вы можете установить приложение позднее через меню браузера.'}catch(_){message='Откройте меню браузера и выберите «Установить приложение» или «Добавить на главный экран».'}
    render(lastStatus);
  }
  function render(status={}){
    lastStatus=status;
    if(!forced&&document.activeElement?.matches('input,textarea,[contenteditable=true]')){panel?.remove();panel=null;return;}
    // Never cover a camera challenge or password recovery with install prompts.
    if(/^#\/(identity|forgot-password)(?:[/?]|$)/.test(location.hash)){panel?.remove();panel=null;return;}
    const standalone=installed(),kind=standalone?'push':'install';
    if(!forced&&(!ios&&!android||read(storageKey(kind))>Date.now()))return;
    if(standalone&&!forced&&(!status.signedIn||status.registered)){panel?.remove();panel=null;return;}
    panel?.remove();panel=element('section','',document.body);panel.id='intercity-pwa-prompt';panel.setAttribute('role','dialog');panel.setAttribute('aria-labelledby','intercity-pwa-title');
    const x=button('×',close,panel,true);x.className='pwa-close';x.setAttribute('aria-label','Закрыть подсказку');
    if(!forced&&!standalone){
      panel.className='pwa-compact';const h=element('h2','Установить InterCity',panel);h.id='intercity-pwa-title';element('p','Быстрый доступ по иконке на главном экране.',panel);button('Установить приложение',()=>{forced=true;render(status)},panel);return;
    }
    const h=element('h2',standalone?'Приложение и уведомления':'Установить InterCity',panel);h.id='intercity-pwa-title';
    if(!standalone){
      element('p','Иконка InterCity появится на главном экране. Веб-версия будет открываться как отдельное приложение.',panel);const list=element('ol','',panel);
      const steps=ios?['Нажмите «Поделиться» — квадрат со стрелкой вверх. В Chrome на iPhone откройте меню «Поделиться».','Выберите «На экран “Домой”» или «Добавить на главный экран».','Нажмите «Добавить», затем откройте InterCity по новой иконке.']:android?['Откройте меню браузера — три точки ⋮.','Выберите «Установить приложение» или «Добавить на главный экран».','Подтвердите «Установить» / «Добавить» и откройте InterCity по новой иконке.']:['Нажмите значок установки в адресной строке браузера.','Либо откройте меню Chrome / Edge и выберите «Установить InterCity».','Подтвердите установку и откройте приложение.'];
      steps.forEach(text=>element('li',text,list));
      if(ios){element('p','Если такого пункта нет, откройте эту же ссылку в Safari. Для push-уведомлений на iPhone нужна iOS 16.4 или новее и запуск по установленной иконке.',panel);button('Скопировать ссылку для Safari',copy,panel,true)}
      else {if(installPrompt)button('Установить InterCity',requestInstall,panel);element('p','Если пункта установки нет, откройте ссылку в Chrome. Во встроенном браузере мессенджера выберите «Открыть в браузере».',panel);button('Скопировать ссылку для браузера',copy,panel,true)}
      element('p','Если уже зарегистрировались, войдите в тот же аккаунт. Приглашение и бонусы сохраняются в аккаунте.',panel);button('Понятно',close,panel);
    } else if(!status.signedIn){element('p','Приложение уже добавлено на главный экран. Войдите, чтобы подключить уведомления о поездках и сообщениях.',panel);button('Войти',()=>{close();location.hash='/login'},panel)}
    else if(status.permission==='unsupported'||!('PushManager'in window)){element('p',ios?'Уведомления доступны начиная с iOS 16.4 при запуске по иконке главного экрана. Проверьте версию iOS.':'Этот браузер не поддерживает push-уведомления. Попробуйте открыть приложение в Chrome.',panel);button('Понятно',close,panel)}
    else if(status.permission==='denied'){element('p',ios?'Уведомления отключены. Откройте настройки iPhone → «Уведомления» → InterCity и включите их.':'Уведомления отключены. Откройте настройки сайта в браузере и разрешите уведомления.',panel);button('Понятно',close,panel)}
    else if(status.registered){element('p','Приложение установлено, уведомления подключены.',panel);button('Закрыть',close,panel)}
    else {element('p','Разрешите уведомления о новых заказах, сообщениях и изменениях поездки.',panel);const enable=button(busy?'Подключаем…':'Разрешить уведомления',async()=>{
      if(busy)return;if(typeof window.intercityRequestWebPush!=='function'){message='Приложение ещё загружается. Повторите через несколько секунд.';render(lastStatus);return;}
      const pending=window.intercityRequestWebPush();busy=true;render(lastStatus);
      try{message=await pending?'':'Не удалось подключить уведомления. Проверьте интернет и повторите.'}catch(_){message='Не удалось подключить уведомления. Повторите попытку.'}
      busy=false;refresh(true);
    },panel);enable.disabled=busy;button('Позже',close,panel,true)}
    if(message){const note=element('p',message,panel);note.setAttribute('role','status')}
  }
  async function refresh(force=false){if(force)forced=true;const id=++sequence;if(!installed()){render();return;}if(typeof window.intercityWebPushStatus!=='function'){render({});return;}try{const status=await window.intercityWebPushStatus();if(id===sequence)render(status)}catch(_){if(forced)render({})}}
  window.intercityShowPwaHelp=()=>{message='';refresh(true)};
  document.addEventListener('focusin',event=>{if(!forced&&event.target?.matches?.('input,textarea,[contenteditable=true]')){panel?.remove();panel=null}});
  window.addEventListener('beforeinstallprompt',event=>{event.preventDefault();installPrompt=event;refresh()});
  window.addEventListener('appinstalled',()=>{installPrompt=null;close()});
  for(const event of ['intercity-pwa-refresh','intercity-push-ready','hashchange','focus'])window.addEventListener(event,()=>refresh());
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});
  matchMedia('(display-mode: standalone)').addEventListener?.('change',()=>refresh());
  const start=()=>setTimeout(()=>refresh(),1800);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();
})();
