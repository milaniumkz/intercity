const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const {MapTileCache,tileKey}=require('../dist/src/geo/map-tiles');
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jfV0AAAAASUVORK5CYII=','base64');
test('tile address is bounded and cannot select an arbitrary host or file',()=>{
 for(const args of [['20','0','0'],['2','4','0'],['1','-1','0'],['../','0','0'],['1','0','https:']])assert.throws(()=>tileKey(...args));
 assert.equal(tileKey('16','47806','22234'),'16-47806-22234');
});
test('parallel tile requests coalesce and cached imagery survives offline restart',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'map-cache-'));let calls=0;
 try{
  const cache=new MapTileCache(root,async(url,options)=>{calls++;assert.equal(url,'https://tile.openstreetmap.org/16/47806/22234.png');assert.match(options.headers['User-Agent'],/InterCity/);await new Promise(r=>setTimeout(r,10));return new Response(png,{headers:{'content-type':'image/png','cache-control':'max-age=600','etag':'test'}})});
  const entries=await Promise.all(Array.from({length:12},()=>cache.get('16','47806','22234')));assert.equal(calls,1);assert(entries.every(e=>e.body.equals(png)));
  const offline=new MapTileCache(root,async()=>{throw Error('offline')});assert((await offline.get('16','47806','22234')).body.equals(png));
 }finally{await fs.rm(root,{recursive:true,force:true})}
});
test('expired tile revalidates with ETag and never caches an HTML error',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'map-cache-'));
 try{
  let calls=0;const cache=new MapTileCache(root,async(url,options)=>{calls++;if(calls===1)return new Response(png,{headers:{'cache-control':'max-age=0','etag':'v1'}});assert.equal(options.headers['If-None-Match'],'v1');return new Response(null,{status:304,headers:{'cache-control':'max-age=600'}})});
  await cache.get('1','0','0');assert((await cache.get('1','0','0')).body.equals(png));assert.equal(calls,2);
  const invalid=new MapTileCache(root,async()=>new Response('<html>error</html>'));await assert.rejects(invalid.get('1','1','1'),/invalid map/);await assert.rejects(fs.stat(path.join(root,'1-1-1.json')));
 }finally{await fs.rm(root,{recursive:true,force:true})}
});

test('tile imagery does not create a database audit record for every image',()=>{
 const {technicalMiddleware}=require('../dist/src/technical/technical-middleware');
 let forwarded=false;
 technicalMiddleware({begin(){throw Error('per-tile database write')}})({url:'/api/geo/tiles/16/47806/22234.png'}, {}, ()=>{forwarded=true});
 assert(forwarded);
});
test('upstream no-store is respected and stale cache is used only when permitted',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'map-cache-'));
 try {
  const noStore=new MapTileCache(root,async()=>new Response(png,{headers:{'cache-control':'no-store'}}));await noStore.get('1','0','1');await assert.rejects(fs.stat(path.join(root,'1-0-1.json')));
  const seed=new MapTileCache(root,async()=>new Response(png,{headers:{'cache-control':'max-age=0'}}));await seed.get('1','0','0');
  const offline=new MapTileCache(root,async()=>{throw Error('offline')});assert((await offline.get('1','0','0')).body.equals(png));
  const strict=new MapTileCache(root,async()=>new Response(png,{headers:{'cache-control':'no-cache, must-revalidate'}}));await strict.get('1','1','0');await assert.rejects(offline.get('1','1','0'),/offline/);
 }finally{await fs.rm(root,{recursive:true,force:true})}
});

test('an unwritable cache does not discard successfully downloaded imagery',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'map-cache-full-'));
 try {
  const file=path.join(root,'not-a-directory');await fs.writeFile(file,'occupied');
  const cache=new MapTileCache(file,async()=>new Response(png,{headers:{'cache-control':'max-age=600'}}));
  assert((await cache.get('1','0','0')).body.equals(png));
 }finally{await fs.rm(root,{recursive:true,force:true})}
});

test('tile rate limits stop new upstream requests until Retry-After expires',async()=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'map-cache-limit-'));
 try {
  let now=1000,calls=0;
  const cache=new MapTileCache(root,async()=>{calls++;return calls===1?new Response(null,{status:429,headers:{'retry-after':'120'}}):new Response(png);},()=>now);
  await assert.rejects(cache.get('1','0','0'),/429/);
  await assert.rejects(cache.get('1','1','0'),/недоступен/);
  assert.equal(calls,1);
  now+=120001;
  assert((await cache.get('1','1','0')).body.equals(png));assert.equal(calls,2);
 }finally{await fs.rm(root,{recursive:true,force:true})}
});
