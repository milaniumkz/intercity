// Dedicated non-operational account for bank certification; never reuses a person's phone.
const {PrismaClient}=require('@prisma/client');
const {randomBytes}=require('crypto');
const bcrypt=require('bcrypt');
(async()=>{
 const p=new PrismaClient();
 try {
  const phone='+70000000001',marker='KASPI_INTEGRATION_TEST';
  const password=await bcrypt.hash(randomBytes(48).toString('base64url'),12);
  await p.$transaction(async tx=>{
   await tx.$executeRaw`SELECT pg_advisory_xact_lock(741302099)`;
   const existing=await tx.user.findUnique({where:{phone},include:{wallet:true,driverProfile:true}});
   if(existing){if(existing.publicId!==marker||!existing.wallet||!existing.driverProfile)throw Error('Reserved account collision; refusing to modify existing user');return;}
   await tx.user.create({data:{phone,name:'Kaspi — технический тестовый водитель',publicId:marker,password,role:'DRIVER',refCode:'KASPI_QA_70000000001',refLink:'',wallet:{create:{}},driverProfile:{create:{status:'PENDING',acceptCityFixed:false,acceptCityAuction:false,acceptIntercity:false,acceptDelivery:false,acceptCargo:false}}}});
  });
  const {KaspiService}=require('../dist/src/wallet/kaspi.service');
  const check=await new KaspiService(p).process({command:'check',txn_id:'1',account:'70000000001',sum:'ignored'});
  if(check.result!==0)throw Error('Kaspi test account check failed');
  console.log('Kaspi certification account provisioned and check verified: 70000000001. No payment or credit created.');
 }finally{await p.$disconnect();}
})().catch(e=>{console.error(e.message);process.exitCode=1});
