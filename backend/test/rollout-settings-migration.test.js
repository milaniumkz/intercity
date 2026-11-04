const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),{PrismaClient}=require('@prisma/client');
const database=process.env.TARIFF_TEST_DATABASE_URL;
test('rollout migration is repeatable, preserves custom store URL and never changes accounting history',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.match(url.pathname,/^\/(ui_review_|dispatch_test)/);
 const db=new PrismaClient({datasources:{db:{url:database}}}),rollback=Error('rollback migration');
 const statements=fs.readFileSync(__dirname+'/../prisma/migrations/20261104120000_driver_tax_pause/migration.sql','utf8').replace(/^--.*$/gm,'').split(';').map(s=>s.trim()).filter(Boolean);
 try{await assert.rejects(db.$transaction(async tx=>{
  const before=await tx.taxIncomeEntry.count();
  await tx.appSettings.upsert({where:{key:'googlePlayUrl'},create:{key:'googlePlayUrl',value:'https://play.google.com/store/apps/details?id=operator.configured'},update:{value:'https://play.google.com/store/apps/details?id=operator.configured'}});
  for(let i=0;i<2;i++)for(const sql of statements)await tx.$executeRawUnsafe(sql);
  assert.equal((await tx.appSettings.findUnique({where:{key:'driverTaxIntegrationPaused'}})).value,'true');assert.equal((await tx.appSettings.findUnique({where:{key:'iosDistributionMode'}})).value,'web');assert.equal((await tx.appSettings.findUnique({where:{key:'googlePlayUrl'}})).value,'https://play.google.com/store/apps/details?id=operator.configured');assert.equal(await tx.taxIncomeEntry.count(),before);
  await tx.appSettings.update({where:{key:'googlePlayUrl'},data:{value:''}});for(const sql of statements)await tx.$executeRawUnsafe(sql);assert.match((await tx.appSettings.findUnique({where:{key:'googlePlayUrl'}})).value,/id=com.milanium.intercity$/);
  throw rollback;
 }),e=>e===rollback)}finally{await db.$disconnect()}
});
