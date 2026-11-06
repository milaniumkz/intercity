const {test}=require('node:test'),assert=require('node:assert/strict');
const {RoadRouterQueue}=require('../dist/src/geo/road-router-queue');
test('queue limits waiting and expired work is never sent to the worker',async()=>{
 const q=new RoadRouterQueue(1,20);let finish,called=0;
 const first=q.run(()=>new Promise(r=>{finish=r}));
 await new Promise(r=>setImmediate(r));
 const second=q.run(async()=>{called++;});
 await assert.rejects(q.run(async()=>{}),/full/);
 await assert.rejects(second,/wait exceeded/);
 finish();await first;assert.equal(called,0);
 assert.equal(await q.run(async()=>42),42);
});
test('failed work releases the worker for the next route',async()=>{
 const q=new RoadRouterQueue();
 const first=q.run(async()=>{throw Error('offline')});
 const second=q.run(async()=>7);
 await assert.rejects(first,/offline/);assert.equal(await second,7);
});
