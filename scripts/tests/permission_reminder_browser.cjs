// Run with INTERCITY_PLAYWRIGHT_MODULE pointing to an installed Playwright package.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {chromium} = require(process.env.INTERCITY_PLAYWRIGHT_MODULE || 'playwright');
const webRoot = path.resolve(__dirname, '../../apps/mobile_flutter/web');
const server = http.createServer((req, res) => {
  const name = req.url.split('?')[0];
  if (['/pwa-install.js', '/pwa-install.css'].includes(name)) {
    res.setHeader('Content-Type', name.endsWith('.js') ? 'text/javascript; charset=utf-8' : 'text/css; charset=utf-8');
    res.end(fs.readFileSync(path.join(webRoot, name.slice(1))));
  } else {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end('<!doctype html><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/pwa-install.css"><script src="/pwa-install.js" defer></script><body><main>InterCity</main></body>');
  }
});
let browser;
const errors=[];
async function pageFor(options={}) {
  const context = await browser.newContext({viewport:{width:393,height:852},isMobile:true,hasTouch:true,
    userAgent:options.ios ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17 Mobile/15 Safari/604.1' : 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/143 Mobile Safari/537.36'+(options.yandex?' YaBrowser/25.2.7.104.00':'' )});
  const page=await context.newPage();
  page.on('pageerror',error=>errors.push(error.message));
  await page.clock.install({time:new Date('2026-11-06T15:00:00Z')});
  await page.addInitScript(options=>{
    const state=window.permissionFixture={signedIn:true,geo:'denied',push:'granted',geoCalls:0,pushCalls:0,reads:0,grants:0,...options};
    const status=window.permissionGeoStatus=new EventTarget();
    Object.defineProperty(status,'state',{get:()=>state.geo});
    Object.defineProperty(navigator,'permissions',{value:{query:async()=>{if(state.noPermissionsApi)throw Error('unsupported');return status}}});
    Object.defineProperty(navigator,'geolocation',{value:{getCurrentPosition(success,failure){
      state.geoCalls++;
      if(state.hangGeo)return;
      queueMicrotask(()=>{if(state.geo==='denied')failure({code:1});else{state.geo='granted';success({coords:{latitude:49.97,longitude:82.61,accuracy:10}});status.dispatchEvent(new Event('change'))}});
    }}});
    Object.defineProperty(navigator,'standalone',{value:!!state.installed});
    window.intercityWebPushStatus=()=>{
      state.reads++;
      const snapshot={signedIn:state.signedIn,permission:state.push,registered:state.registered??state.push==='granted'};
      if(state.holdNext){state.holdNext=false;return new Promise(resolve=>{state.releaseStatus=()=>resolve(snapshot)})}
      return Promise.resolve(snapshot);
    };
    window.intercityRequestWebPush=()=>{
      state.pushCalls++;state.pushActivation=!!navigator.userActivation?.isActive;
      if(state.throwPush)throw Error('not ready');
      if(state.failToken)return Promise.resolve(false);state.registered=true;return Promise.resolve(true);
    };
    state.nativePushCalls=0;
    Object.defineProperty(window,'Notification',{value:class {
      static get permission(){return state.push}
      static requestPermission(callback){
        state.nativePushCalls++;state.nativeActivation=!!navigator.userActivation?.isActive;
        if(state.hangPush)return new Promise(()=>{});
        state.push=state.nativePushResult||'granted';
        callback?.(state.push);
        return state.callbackOnly?undefined:Promise.resolve(state.push);
      }
    }});
    window.addEventListener('intercity-location-permission-granted',()=>state.grants++);
    if(state.dismissInstall!==false)localStorage.setItem('intercity.pwa.install.dismissedUntil',String(Date.now()+86400000));
    if(state.dismissPush!==false)localStorage.setItem('intercity.pwa.push.dismissedUntil',String(Date.now()+86400000));
  }, options);
  await page.goto(`http://127.0.0.1:${server.address().port}/#${options.route || '/order'}`);
  await page.clock.fastForward(2000);
  return {context,page,prompt:page.locator('[data-kind="permissions"]')};
}
async function close(test){await test.context.close();}
async function run(round){
  // A denied site is gated: it cannot be dismissed or bypassed by typing/chat.
  let t=await pageFor();await t.prompt.waitFor();
  assert.equal(await t.prompt.getAttribute('aria-modal'),'true');
  assert.equal(await t.page.getByRole('button',{name:/Закрыть/}).count(),0);
  assert.equal(await t.page.locator('main').evaluate(e=>e.inert),true);
  assert.match(await t.prompt.innerText(),/GPS телефона и разрешение для сайта/);
  await t.page.keyboard.press('Escape');await t.page.clock.fastForward(600000);await t.prompt.waitFor();
  assert.equal(await t.page.evaluate(()=>permissionFixture.geoCalls+permissionFixture.pushCalls),0);
  await t.page.evaluate(()=>{const input=document.createElement('input');document.querySelector('main').append(input);input.focus();window.intercityPermissionUiDepth=1;window.dispatchEvent(new Event('focus'))});
  await t.page.clock.fastForward(6000);assert.equal(await t.prompt.count(),1);
  await t.page.getByRole('button',{name:'Проверить доступ к геолокации',exact:true}).click();
  await t.page.waitForFunction(()=>document.querySelector('[role=status]')?.textContent.includes('Доступ для сайта запрещён'));
  assert.equal(await t.page.evaluate(()=>permissionFixture.geoCalls),1);
  await t.page.clock.fastForward(60000);assert.equal(await t.prompt.count(),1);
  await close(t);

  // One approval removes the gate, even if notifications are denied.
  t=await pageFor({geo:'prompt',push:'granted'});await t.prompt.waitFor();
  await t.page.getByRole('button',{name:'Разрешить местоположение',exact:true}).click();
  await t.page.waitForFunction(()=>permissionFixture.grants===1);
  await t.page.waitForFunction(()=>!document.querySelector('[data-kind="permissions"]'));
  await t.page.clock.fastForward(600000);
  assert.equal(await t.prompt.count(),0);assert.equal(await t.page.locator('main').evaluate(e=>e.inert),false);
  assert.deepEqual(await t.page.evaluate(()=>[permissionFixture.geoCalls,permissionFixture.pushCalls,permissionFixture.grants]),[1,0,1]);
  await close(t);

  // Previously granted permission never opens a new system prompt or gate.
  t=await pageFor({geo:'granted',push:'granted'});await t.page.clock.fastForward(600000);
  await t.page.evaluate(()=>window.dispatchEvent(new CustomEvent('intercity-location-access',{detail:'denied'})));await t.page.clock.fastForward(6000);
  assert.equal(await t.prompt.count(),0);assert.equal(await t.page.evaluate(()=>permissionFixture.grants+permissionFixture.geoCalls+permissionFixture.pushCalls),0);
  await t.page.reload();await t.page.clock.fastForward(6000);assert.equal(await t.prompt.count(),0);await close(t);

  // Registration and identity verification remain available before GPS setup.
  t=await pageFor();await t.prompt.waitFor();
  for(const route of ['/identity','/forgot-password','/register/passenger','/login','/driver/verification/docs']){
    await t.page.evaluate(route=>location.hash=route,route);await t.page.clock.fastForward(6000);
    assert.equal(await t.prompt.count(),0,route);assert.equal(await t.page.locator('main').evaluate(e=>e.inert),false);
  }
  await t.page.evaluate(()=>location.hash='/driver/active-order');await t.page.clock.fastForward(6000);await t.prompt.waitFor();await close(t);

  // iPhone unsupported web push must not lock users who have GPS access.
  t=await pageFor({ios:true,geo:'granted',push:'unsupported'});await t.page.clock.fastForward(600000);
  assert.equal(await t.prompt.count(),0);assert.equal(await t.page.locator('main').evaluate(e=>e.inert),false);await close(t);

  // Settings changes are detected on return; hidden pages do not poll.
  t=await pageFor();await t.prompt.waitFor();
  await t.page.evaluate(()=>{permissionFixture.hidden=true;Object.defineProperty(document,'hidden',{get:()=>permissionFixture.hidden});document.dispatchEvent(new Event('visibilitychange'))});
  const reads=await t.page.evaluate(()=>permissionFixture.reads);await t.page.clock.fastForward(120000);
  assert.equal(await t.page.evaluate(()=>permissionFixture.reads),reads);
  await t.page.evaluate(()=>{permissionFixture.geo='granted';permissionFixture.hidden=false;document.dispatchEvent(new Event('visibilitychange'))});
  await t.page.waitForFunction(()=>!document.querySelector('[data-kind="permissions"]'));
  assert.equal(await t.page.evaluate(()=>permissionFixture.grants),1);await close(t);

  // Out-of-order reads cannot restore the old denied gate.
  t=await pageFor();await t.prompt.waitFor();
  await t.page.evaluate(()=>{permissionFixture.holdNext=true;window.dispatchEvent(new Event('intercity-pwa-refresh'))});
  await t.page.waitForFunction(()=>!!permissionFixture.releaseStatus);
  await t.page.evaluate(()=>{permissionFixture.geo='granted';window.dispatchEvent(new Event('intercity-pwa-refresh'))});
  await t.page.waitForFunction(()=>!document.querySelector('[data-kind="permissions"]'));
  await t.page.evaluate(()=>permissionFixture.releaseStatus());await t.page.clock.fastForward(1000);assert.equal(await t.prompt.count(),0);await close(t);

  // Native GPS success is authoritative, including Safari without Permissions API.
  t=await pageFor({noPermissionsApi:true});await t.prompt.waitFor();
  await t.page.evaluate(()=>window.dispatchEvent(new CustomEvent('intercity-location-access',{detail:'granted'})));
  await t.page.waitForFunction(()=>!document.querySelector('[data-kind="permissions"]'));
  await t.page.clock.fastForward(600000);assert.equal(await t.prompt.count(),0);assert.equal(await t.page.evaluate(()=>permissionFixture.grants),1);await close(t);

  // GPS timeout is not a denial; revocation later restores the mandatory gate.
  t=await pageFor({geo:'prompt'});await t.prompt.waitFor();
  await t.page.evaluate(()=>{navigator.geolocation.getCurrentPosition=(ok,fail)=>{permissionFixture.geoCalls++;fail({code:3})}});
  await t.page.getByRole('button',{name:'Разрешить местоположение',exact:true}).click();
  await t.page.waitForFunction(()=>!document.querySelector('[data-kind="permissions"]'));
  await t.page.clock.fastForward(60000);assert.equal(await t.prompt.count(),0);
  await t.page.evaluate(()=>{permissionFixture.geo='denied';permissionGeoStatus.dispatchEvent(new Event('change'))});
  await t.prompt.waitFor();assert.equal(await t.page.locator('main').evaluate(e=>e.inert),true);await close(t);

  // A browser approval cannot keep blocking because of an old cached denial.
  t=await pageFor();await t.prompt.waitFor();
  await t.page.evaluate(()=>{navigator.geolocation.getCurrentPosition=success=>{permissionFixture.geoCalls++;success({coords:{latitude:49.97,longitude:82.61}})}});
  await t.page.getByRole('button',{name:'Проверить доступ к геолокации',exact:true}).click();
  await t.page.waitForFunction(()=>permissionFixture.grants===1);assert.equal(await t.prompt.count(),0);await close(t);

  t=await pageFor({signedIn:false,dismissInstall:false});await t.page.locator('#intercity-pwa-prompt').waitFor();
  assert.equal(await t.prompt.count(),0);await t.page.getByRole('button',{name:'Закрыть подсказку'}).click();
  await t.page.clock.fastForward(120000);assert.equal(await t.page.locator('#intercity-pwa-prompt').count(),0);await close(t);
  // Yandex: native notification request is synchronous in the trusted click.
  for(const callbackOnly of [false,true]){
    t=await pageFor({yandex:true,geo:'granted',push:'default',dismissPush:false,callbackOnly});
    await t.page.getByRole('button',{name:'Включить уведомления',exact:true}).click();
    await t.page.waitForFunction(()=>permissionFixture.pushCalls===1);
    assert.deepEqual(await t.page.evaluate(()=>[permissionFixture.nativePushCalls,permissionFixture.nativeActivation]),[1,true]);
    await t.page.clock.fastForward(60000);assert.equal(await t.page.locator('[data-kind=push]').count(),0);assert.equal(await t.prompt.count(),0);assert.equal(await t.page.locator('main').evaluate(e=>e.inert),false);await close(t);
  }
  t=await pageFor({yandex:true,geo:'granted',push:'denied',dismissPush:false});
  await t.page.getByRole('button',{name:'Включить уведомления',exact:true}).click();
  assert.match(await t.prompt.innerText(),/Яндекс Браузере[\s\S]*Уведомления от сайтов/);
  assert.equal(await t.page.locator('main').evaluate(e=>e.inert),true);assert.equal(await t.page.getByRole('button',{name:/Закрыть/}).count(),0);
  assert.equal(await t.page.evaluate(()=>permissionFixture.nativePushCalls+permissionFixture.pushCalls),0);await close(t);

  // Browser-wide block/default return gives useful feedback instead of a dead button.
  t=await pageFor({yandex:true,geo:'granted',push:'default',dismissPush:false,nativePushResult:'default'});
  await t.page.getByRole('button',{name:'Включить уведомления',exact:true}).click();
  await t.page.waitForFunction(()=>document.querySelector('[role=status]')?.textContent.includes('Запрос не подтверждён'));
  await t.page.clock.fastForward(600000);
  assert.deepEqual(await t.page.evaluate(()=>[permissionFixture.nativePushCalls,permissionFixture.pushCalls]),[1,0]);await close(t);

  // An FCM connection failure is distinct from the OS permission request.
  t=await pageFor({yandex:true,geo:'granted',push:'granted',registered:false,dismissPush:false,failToken:true});
  await t.page.getByRole('button',{name:'Подключить уведомления',exact:true}).click();
  await t.page.waitForFunction(()=>document.querySelector('[role=status]')?.textContent.includes('Разрешение получено. Не удалось подключить уведомления'));
  assert.equal(await t.page.evaluate(()=>permissionFixture.nativePushCalls),0);await close(t);

  // Approving push cannot bypass the required GPS gate.
  t=await pageFor({yandex:true,push:'default'});await t.prompt.waitFor();
  await t.page.getByRole('button',{name:'Включить уведомления',exact:true}).click();
  await t.page.waitForFunction(()=>permissionFixture.pushCalls===1);await t.prompt.waitFor();
  assert.equal(await t.page.locator('main').evaluate(e=>e.inert),true);await close(t);
  assert.deepEqual(errors,[]);console.log(`Permission gate browser pass ${round}: 16 scenario groups OK`);
}
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  browser=await chromium.launch({executablePath:process.env.INTERCITY_BROWSER_EXECUTABLE||(fs.existsSync('/usr/bin/chromium')?'/usr/bin/chromium':undefined),args:['--no-sandbox']});
  for(let round=1;round<=Number(process.env.INTERCITY_BROWSER_PASSES||5);round++)await run(round);
})().catch(error=>{console.error(error);process.exitCode=1}).finally(async()=>{await browser?.close();server.close()});
