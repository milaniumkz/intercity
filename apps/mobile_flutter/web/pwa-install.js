(() => {
  'use strict';
  const ios=/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1),android=/Android/i.test(navigator.userAgent);
  const installed=()=>navigator.standalone===true||matchMedia('(display-mode: standalone)').matches;
  const storageKey=kind=>`intercity.pwa.${kind}.dismissedUntil`;
  const read=key=>{try{return Number(localStorage.getItem(key)||0)}catch(_){return 0}};
  let panel,forced=false,busy=false,sequence=0,lastStatus={},message='',installPrompt;
  let permissionInfo='',geoStatus,geoConfirmed=false,geoDenied=false,lastGeo;
  const gatedElements=new Map();
  const protectedRoute=()=>/^#\/(identity|forgot-password|register|login|startup|onboarding|driver\/verification|privacy|terms)(?:[/?]|$)/.test(location.hash);
  const appRoute=()=>!protectedRoute();
  const missingPermissions=status=>status.signedIn&&appRoute()&&status.locationPermission!=='granted';
  function gateContent(blocked){
    if(!blocked){for(const [node,inert] of gatedElements)node.inert=inert;gatedElements.clear();return;}
    for(const node of document.body.children){
      if(node===panel||node.matches('script,style,link'))continue;
      if(!gatedElements.has(node)){gatedElements.set(node,node.inert);node.inert=true;}
    }
  }
  const isEditing=()=>{let active=document.activeElement;while(active?.shadowRoot?.activeElement)active=active.shadowRoot.activeElement;return active?.matches?.('input,textarea,[contenteditable=true]')};
  const element=(tag,text,parent)=>{const e=document.createElement(tag);if(text)e.textContent=text;parent?.append(e);return e};
  const button=(label,action,parent,secondary=false)=>{const e=element('button',label,parent);e.type='button';e.className=secondary?'pwa-secondary':'pwa-primary';e.onclick=action;return e};
  const close=()=>{if(missingPermissions(lastStatus)){render(lastStatus);return;}try{localStorage.setItem(storageKey(installed()?'push':'install'),String(Date.now()+86400000))}catch(_){}forced=false;panel?.remove();panel=null};
  const copy=async()=>{try{await navigator.clipboard.writeText(location.href);message=ios?'Ссылка скопирована. Откройте её в Safari.':'Ссылка скопирована. Откройте её в Chrome.'}catch(_){message='Скопируйте адрес из адресной строки браузера.'}render(lastStatus)};
  async function requestInstall(){
    if(!installPrompt){forced=true;render(lastStatus);return;}
    const event=installPrompt;installPrompt=null;
    try{await event.prompt();const choice=await event.userChoice;message=choice.outcome==='accepted'?'Подтвердите установку и откройте InterCity по новой иконке.':'Вы можете установить приложение позднее через меню браузера.'}catch(_){message='Откройте меню браузера и выберите «Установить приложение» или «Добавить на главный экран».'}
    render(lastStatus);
  }
  const geoChanged=()=>{geoConfirmed=false;geoDenied=false;refresh()};
  async function locationPermission(recheck=false){
    if(!navigator.geolocation)return 'unsupported';
    try{
      if(recheck&&geoStatus){geoStatus.removeEventListener?.('change',geoChanged);geoStatus=null;}
      if(!geoStatus){geoStatus=await navigator.permissions.query({name:'geolocation'});geoStatus.addEventListener?.('change',geoChanged);}
      return geoConfirmed||geoStatus.state==='granted'?'granted':geoDenied?'denied':geoStatus.state;
    }catch(_){return geoConfirmed?'granted':geoDenied?'denied':'unknown'}
  }
  function requestLocation(){
    if(busy)return;
    if(!navigator.geolocation){permissionInfo='geo';message='Этот браузер не поддерживает геолокацию. Откройте сайт в Chrome или Safari.';render(lastStatus);return;}
    permissionInfo='geo';
    busy=true;message=lastStatus.locationPermission==='denied'?'Проверяем разрешение для этого сайта…':'Подтвердите доступ в окне браузера.';render(lastStatus);
    let finished=false;
    const finish=text=>{if(finished)return;finished=true;clearTimeout(deadline);busy=false;message=text;refresh()};
    const deadline=setTimeout(()=>finish('Если запрос не появился, откройте настройки сайта и разрешите местоположение.'),15000);
    try{navigator.geolocation.getCurrentPosition(()=>{geoDenied=false;geoConfirmed=true;finish('');refresh()},error=>{
      if(error.code===1){geoConfirmed=false;geoDenied=true;permissionInfo='geo';finish('Доступ для сайта запрещён. Включённого GPS телефона недостаточно: разрешите местоположение именно для InterCity в настройках браузера.');}
      else {geoDenied=false;geoConfirmed=true;finish('Доступ разрешён, но координаты пока не получены. Проверьте, что GPS включён.');}
    },{enableHighAccuracy:false,timeout:8000,maximumAge:0})}catch(_){finish('Не удалось запросить геолокацию. Откройте настройки сайта.')}
  }
  async function requestNotifications(){
    if(busy)return;
    if(lastStatus.permission==='denied'){permissionInfo='push';render(lastStatus);return;}
    if(lastStatus.permission==='unsupported'||!('PushManager'in window)){
      if(ios&&!installed()){forced=true;render(lastStatus)}else{permissionInfo='push';render(lastStatus)}
      return;
    }
    if(typeof window.intercityRequestWebPush!=='function'){message='Приложение ещё загружается. Повторите через несколько секунд.';render(lastStatus);return;}
    // Keep the native permission call in the trusted click, before any await.
    let pending;try{pending=window.intercityRequestWebPush()}catch(_){message='Не удалось запросить уведомления. Повторите попытку.';render(lastStatus);return;}busy=true;message='';render(lastStatus);
    let deadline;
    try{
      const connected=await Promise.race([pending,new Promise(resolve=>{deadline=setTimeout(()=>resolve(false),20000)})]);
      if(!connected)message='Проверьте разрешение уведомлений и подключение к интернету.';
    }catch(_){message='Не удалось подключить уведомления. Повторите попытку.'}
    finally{clearTimeout(deadline);busy=false;refresh()}
  }
  function renderPermissions(status){
    const signature=JSON.stringify([status.locationPermission,busy,message]);
    if(panel?.dataset.kind==='permissions'&&panel.dataset.signature===signature){gateContent(true);return;}
    const hadFocus=panel?.contains(document.activeElement);
    panel?.remove();panel=element('section','',document.body);panel.id='intercity-pwa-prompt';panel.className='pwa-permission-gate';panel.dataset.kind='permissions';panel.dataset.signature=signature;
    panel.setAttribute('role','alertdialog');panel.setAttribute('aria-modal','true');panel.setAttribute('aria-labelledby','intercity-pwa-title');panel.tabIndex=-1;
    const card=element('div','',panel);card.className='pwa-gate-card';
    element('h2','Разрешите местоположение',card).id='intercity-pwa-title';
    element('p','Для продолжения работы InterCity нужен доступ к местоположению. Разрешите его один раз — после этого окно больше не появится, пока доступ включён.',card);
    element('p','Включённый GPS телефона и разрешение для сайта — разные настройки.',card);
    const blocked=status.locationPermission==='denied';
    if(blocked){
      element('p',ios?'Откройте настройки сайта в Safari / Chrome и разрешите местоположение. Также проверьте: Настройки iPhone → Конфиденциальность и безопасность → Службы геолокации → ваш браузер.':'Нажмите значок настроек слева от адреса сайта → «Разрешения» → «Местоположение» → «Разрешить». В настройках телефона также разрешите геолокацию вашему браузеру.',card);
      element('p','После запрета браузер не открывает системный запрос повторно. Измените разрешение в настройках и нажмите кнопку ниже.',card);
    }
    if(status.locationPermission==='unsupported')element('p','Этот браузер не поддерживает геолокацию. Откройте InterCity в Chrome или Safari.',card);
    const action=button(busy?'Проверяем доступ…':blocked?'Проверить доступ к геолокации':'Разрешить местоположение',requestLocation,card);action.disabled=busy;
    if(message){const note=element('p',message,card);note.setAttribute('role','status');note.setAttribute('aria-live','polite')}
    gateContent(true);if(!hadFocus)panel.focus({preventScroll:true});
  }
  function render(status={}){
    lastStatus=status;
    // Geolocation is mandatory, including while a chat or input is open.
    if(protectedRoute()){gateContent(false);panel?.remove();panel=null;return;}
    if(missingPermissions(status)){renderPermissions(status);return;}
    gateContent(false);
    if(panel?.dataset.kind==='permissions'){panel.remove();panel=null;permissionInfo='';message='';}
    if(!forced&&isEditing()){panel?.remove();panel=null;return;}
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
  async function refresh(force=false,recheck=false){
    if(document.hidden)return;
    if(force)forced=true;
    const id=++sequence;
    let status={...lastStatus};
    try{if(typeof window.intercityWebPushStatus==='function')status=await window.intercityWebPushStatus()}catch(_){}
    if(status.signedIn&&appRoute())status={...status,locationPermission:await locationPermission(recheck)};
    if(id!==sequence)return;
    if((permissionInfo==='geo'&&status.locationPermission==='granted')||(permissionInfo==='push'&&status.permission==='granted')){permissionInfo='';message='';}
    if(status.locationPermission==='granted'&&lastGeo&&lastGeo!=='granted')window.dispatchEvent(new Event('intercity-location-permission-granted'));
    if(status.locationPermission)lastGeo=status.locationPermission;
    render(status);
  }
  window.addEventListener('intercity-location-access',event=>{
    if(event.detail==='granted'){geoConfirmed=true;geoDenied=false;}
    else if(event.detail==='denied'){geoConfirmed=false;geoDenied=true;}
    else return;
    refresh();
  });
  document.addEventListener('keydown',event=>{
    if(panel?.dataset.kind!=='permissions')return;
    if(event.key==='Escape'){event.preventDefault();event.stopImmediatePropagation();}
    if(event.key==='Tab'){
      const items=panel.querySelectorAll('button:not(:disabled)');
      if(!items.length){event.preventDefault();panel.focus();return;}
      if(event.shiftKey&&(document.activeElement===items[0]||document.activeElement===panel)){event.preventDefault();items[items.length-1].focus();}
      else if(!event.shiftKey&&(document.activeElement===items[items.length-1]||document.activeElement===panel)){event.preventDefault();items[0].focus();}
    }
  },true);
  window.intercityShowPwaHelp=()=>{message='';refresh(true)};
  document.addEventListener('focusin',event=>{if(panel?.dataset.kind!=='permissions'&&!forced&&(isEditing()||event.composedPath().some(item=>item?.matches?.('input,textarea,[contenteditable=true]')))){panel?.remove();panel=null}});
  window.addEventListener('beforeinstallprompt',event=>{event.preventDefault();installPrompt=event;refresh()});
  window.addEventListener('appinstalled',()=>{installPrompt=null;close()});
  for(const event of ['intercity-pwa-refresh','intercity-push-ready'])window.addEventListener(event,()=>refresh());
  for(const event of ['hashchange','focus'])window.addEventListener(event,()=>{refresh(false,true)});
  document.addEventListener('visibilitychange',()=>{if(!document.hidden){refresh(false,true)}});
  matchMedia('(display-mode: standalone)').addEventListener?.('change',()=>refresh());
  setInterval(()=>refresh(),5000);
  const start=()=>setTimeout(()=>refresh(),1800);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();
})();
