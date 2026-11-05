const {test}=require('node:test'),assert=require('node:assert/strict');
const {humanAction,humanFailure,userActivity}=require('../dist/src/technical/activity-feed');
test('activity explains business operations and failures in Russian',()=>{
 assert.equal(humanAction('POST /api/auth/register'),'Регистрация аккаунта');
 assert.equal(humanAction('POST /api/intercity/requests/abc/accept'),'Выбор водителя');
 assert.equal(humanFailure('insufficient wallet balance'),'Недостаточно денег на балансе');
 assert.equal(humanFailure('Invalid credentials'),'Не удалось войти: проверьте номер телефона и пароль');
});
test('video business rejection remains visible even when the HTTP upload succeeded; personal data is permission-scoped',async()=>{
 const event={id:'event',at:new Date(),userId:'person',objectId:'check',action:'POST /api/auth/identity/challenge/check/video',result:'SUCCESS',status:200,client:{platform:'web'}};
 const db={techEvent:{findMany:async()=>[event],count:async()=>1},user:{findMany:async()=>[{id:'person',name:'Олег',phone:'+70000000000'}]},biometricChallenge:{findMany:async()=>[{id:'check',status:'REJECTED',reason:'Поместите лицо в овал'}]}};
 const privateResult=await userActivity(db,{},true);assert.equal(privateResult.items[0].failed,true);assert.equal(privateResult.items[0].user.name,'Олег');assert.equal(privateResult.items[0].reason,'Поместите лицо в овал');assert.equal(privateResult.items[0].resultLabel,'Проверка не пройдена');
 const restricted=await userActivity(db,{},false);assert.equal(restricted.items[0].user,null);assert.equal(restricted.items[0].userId,null);assert(!JSON.stringify(restricted).includes('+70000000000'));
 await assert.rejects(userActivity(db,{search:'Олег'},false),/Нет доступа/);
});
