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
    userAgent:options.ios ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17 Mobile/15 Safari/604.1' : 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/143 Mobile Safari/537.36'});
  const page=await context.newPage();
  page.on('pageerror',error=>errors.push(error.message));
  await page.clock.install({time:new Date('2026-11-06T15:00:00Z')});
  await page.addInitScript(options=>{
    const state=window.permissionFixture={signedIn:true,geo:'denied',push:'denied',geoCalls:0,pushCalls:0,reads:0,grants:0,...options};
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
      const snapshot={signedIn:state.signedIn,permission:state.push,registered:state.push==='granted'};
      if(state.holdNext){state.holdNext=false;return new Promise(resolve=>{state.releaseStatus=()=>resolve(snapshot)})}
      return Promise.resolve(snapshot);
    };
    window.intercityRequestWebPush=()=>{
      state.pushCalls++;state.pushActivation=!!navigator.userActivation?.isActive;
      if(state.throwPush)throw Error('not ready');
      state.push='granted';return Promise.resolve(true);
    };
    window.addEventListener('intercity-location-permission-granted',()=>state.grants++);
    if(state.dismissInstall!==false)localStorage.setItem('intercity.pwa.install.dismissedUntil',String(Date.now()+86400000));
    localStorage.setItem('intercity.pwa.push.dismissedUntil',String(Date.now()+86400000));
  }, options);
  await page.goto(`http://127.0.0.1:${server.address().port}/#${options.route || '/order'}`);
  await page.clock.fastForward(2000);
  return {context,page,prompt:page.locator('[data-kind="permissions"]')};
}
async function close(test){await test.context.close();}
async function run(round){
  // No permanent dismissal, no background native requests, and stable reading/focus.
  let t=await pageFor();await t.prompt.waitFor();
  await t.page.getByRole('button',{name:'Как разрешить геолокацию',exact:true}).click();
  assert.match(await t.prompt.innerText(),/браузер не показывает системный запрос повторно/);
  await t.page.evaluate(()=>document.querySelector('[data-kind="permissions"]').dataset.probe='kept');
  await t.page.clock.fastForward(600000);
  assert.equal(await t.prompt.getAttribute('data-probe'),'kept');
  assert.equal(await t.page.evaluate(()=>permissionFixture.geoCalls+permissionFixture.pushCalls),0);
  await t.page.getByRole('button',{name:'Закрыть напоминание на 30 секунд'}).click();
  assert.equal(await t.prompt.count(),0);await t.page.clock.fastForward(31000);await t.prompt.waitFor();
  assert.equal(await t.page.evaluate(()=>localStorage.getItem('intercity.pwa.permissions.dismissedUntil')),null);
  await close(t);

  // Explicit clicks grant both permissions and update the app without a reload.
  t=await pageFor({geo:'prompt',push:'default'});await t.prompt.waitFor();
  await t.page.getByRole('button',{name:'Разрешить геолокацию',exact:true}).click();
  await t.page.waitForFunction(()=>permissionFixture.grants===1);
  await t.page.getByRole('button',{name:'Разрешить уведомления',exact:true}).click();
  await t.page.waitForFunction(()=>!document.querySelector('[data-kind="permissions"]'));
  await t.page.clock.fastForward(600000);
  assert.equal(await t.prompt.count(),0);
  assert.deepEqual(await t.page.evaluate(()=>[permissionFixture.geoCalls,permissionFixture.pushCalls,permissionFixture.grants,permissionFixture.pushActivation]),[1,1,1,true]);
  await close(t);

  t=await pageFor({geo:'granted',push:'granted'});await t.page.clock.fastForward(60000);
  assert.equal(await t.prompt.count(),0);assert.equal(await t.page.evaluate(()=>permissionFixture.grants+permissionFixture.geoCalls+permissionFixture.pushCalls),0);await close(t);

  // Typed addresses, including Flutter shadow inputs, must not be obscured.
  t=await pageFor();await t.prompt.waitFor();
  await t.page.evaluate(()=>{const host=document.createElement('div');host.id='editing';host.attachShadow({mode:'open'}).innerHTML='<input>';document.body.append(host);host.shadowRoot.querySelector('input').focus()});
  await t.page.clock.fastForward(31000);assert.equal(await t.prompt.count(),0);
  await t.page.evaluate(()=>{document.getElementById('editing').shadowRoot.querySelector('input').blur();window.dispatchEvent(new Event('focus'))});
  await t.prompt.waitFor();
  for(const route of ['/identity','/forgot-password','/register/passenger','/login','/driver/verification/docs']){
    await t.page.evaluate(route=>location.hash=route,route);await t.page.clock.fastForward(6000);assert.equal(await t.prompt.count(),0,route);
  }
  await close(t);

  // iPhone web push instructions explain installation; closing is not a permanent opt-out.
  t=await pageFor({ios:true,geo:'granted',push:'unsupported'});await t.prompt.waitFor();
  await t.page.getByRole('button',{name:'Разрешить уведомления',exact:true}).click();
  assert.match(await t.page.locator('#intercity-pwa-prompt').innerText(),/На экран/);
  await t.page.getByRole('button',{name:'Закрыть подсказку'}).click();await t.page.clock.fastForward(31000);await t.prompt.waitFor();
  await close(t);

  // Permission changes are detected on return; hidden pages do not keep checking.
  t=await pageFor();await t.prompt.waitFor();
  await t.page.evaluate(()=>{permissionFixture.hidden=true;Object.defineProperty(document,'hidden',{get:()=>permissionFixture.hidden});document.dispatchEvent(new Event('visibilitychange'))});
  const reads=await t.page.evaluate(()=>permissionFixture.reads);await t.page.clock.fastForward(120000);
  assert.equal(await t.page.evaluate(()=>permissionFixture.reads),reads);
  await t.page.evaluate(()=>{permissionFixture.geo='granted';permissionFixture.push='granted';permissionFixture.hidden=false;document.dispatchEvent(new Event('visibilitychange'))});
  await t.page.waitForFunction(()=>!document.querySelector('[data-kind="permissions"]'));
  assert.equal(await t.page.evaluate(()=>permissionFixture.grants),1);
  await close(t);

  // Out-of-order permission reads never restore a stale denied prompt.
  t=await pageFor();await t.prompt.waitFor();
  await t.page.evaluate(()=>{permissionFixture.holdNext=true;window.dispatchEvent(new Event('intercity-pwa-refresh'))});
  await t.page.waitForFunction(()=>!!permissionFixture.releaseStatus);
  await t.page.evaluate(()=>{permissionFixture.geo='granted';permissionFixture.push='granted';window.dispatchEvent(new Event('intercity-pwa-refresh'))});
  await t.page.waitForFunction(()=>!document.querySelector('[data-kind="permissions"]'));
  await t.page.evaluate(()=>permissionFixture.releaseStatus());await t.page.clock.fastForward(1000);assert.equal(await t.prompt.count(),0);
  await close(t);

  // Safari without Permissions API and a blocked push bridge remain recoverable.
  t=await pageFor({geo:'prompt',push:'default',noPermissionsApi:true,throwPush:true});await t.prompt.waitFor();
  await t.page.getByRole('button',{name:'Разрешить геолокацию',exact:true}).click();await t.page.waitForFunction(()=>permissionFixture.grants===1);
  await t.page.getByRole('button',{name:'Разрешить уведомления',exact:true}).click();
  assert.match(await t.prompt.innerText(),/Не удалось запросить уведомления/);
  await t.page.clock.fastForward(60000);assert.equal(await t.page.evaluate(()=>permissionFixture.geoCalls),1);
  await close(t);

  // Existing installation hints still close for a day when no permission is required.
  t=await pageFor({signedIn:false,dismissInstall:false});await t.page.locator('#intercity-pwa-prompt').waitFor();
  assert.equal(await t.prompt.count(),0);await t.page.getByRole('button',{name:'Закрыть подсказку'}).click();
  await t.page.clock.fastForward(120000);assert.equal(await t.page.locator('#intercity-pwa-prompt').count(),0);
  await close(t);
  assert.deepEqual(errors,[]);console.log(`Permission reminder browser pass ${round}: 8 scenarios OK`);
}
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  browser=await chromium.launch({executablePath:process.env.INTERCITY_BROWSER_EXECUTABLE||(fs.existsSync('/usr/bin/chromium')?'/usr/bin/chromium':undefined),args:['--no-sandbox']});
  for(let round=1;round<=Number(process.env.INTERCITY_BROWSER_PASSES||5);round++)await run(round);
})().catch(error=>{console.error(error);process.exitCode=1}).finally(async()=>{await browser?.close();server.close()});
