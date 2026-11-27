const {test}=require('node:test'),assert=require('node:assert/strict');
const {IdentityEngine}=require('../dist/src/identity/identity-engine');
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const valid={verdict:'PASS',reason:'',model:'fixture',embedding:[1,...Array(127).fill(0)],reference:Buffer.from('face').toString('base64'),videoSignature:Array(32).fill('0123456789abcdef')};
test('identity engine serializes burst traffic without treating busy as a face failure',async()=>{
 const original=global.fetch;let active=0,maximum=0,posts=0;
 global.fetch=async(url,options)=>{
  if(String(url).endsWith('/health'))return Response.json({ready:true,liveness:true});
  posts++;active++;maximum=Math.max(maximum,active);await pause(3);active--;
  return Response.json(valid);
 };
 try{
  const engine=new IdentityEngine();
  for(let i=0;i<20;i++){
   const results=await Promise.all(Array.from({length:3},()=>engine.verify(Buffer.alloc(12000),['TURN_LEFT','BLINK'])));
   assert(results.every(r=>r.verdict==='PASS'));
  }
  assert.equal(maximum,1);assert.equal(posts,60);
  console.log(JSON.stringify({identityBurstRounds:20,completedVerifications:60,maximumConcurrentModelCalls:maximum}));
 }finally{global.fetch=original;}
});
test('explicit engine busy is retried and a completed verdict is consumed once',async()=>{
 const original=global.fetch;let posts=0;
 global.fetch=async url=>String(url).endsWith('/health')?Response.json({ready:true,liveness:true}):++posts===1?Response.json({error:'busy'},{status:503}):Response.json(valid);
 try{assert.equal((await new IdentityEngine().verify(Buffer.alloc(12000),['TURN_RIGHT','BLINK'])).verdict,'PASS');assert.equal(posts,2);}
 finally{global.fetch=original;}
});
test('bounded queue rejects excess work, releases on errors and never accepts a malformed model answer',async()=>{
 const original=global.fetch;let broken=false;
 global.fetch=async url=>{if(String(url).endsWith('/health'))return Response.json({ready:true,liveness:true});await pause(10);return Response.json(broken?{...valid,embedding:undefined}:valid);};
 try{
  const engine=new IdentityEngine(),results=await Promise.allSettled(Array.from({length:4},()=>engine.verify(Buffer.alloc(12000),['TURN_RIGHT','BLINK'])));
  assert.equal(results.filter(r=>r.status==='fulfilled').length,3);
  assert.equal(results.filter(r=>r.status==='rejected').length,1);
  broken=true;await assert.rejects(engine.verify(Buffer.alloc(12000),['TURN_RIGHT','BLINK']),/эталон/);
  broken=false;assert.equal((await engine.verify(Buffer.alloc(12000),['TURN_RIGHT','BLINK'])).verdict,'PASS');
 }finally{global.fetch=original;}
});
