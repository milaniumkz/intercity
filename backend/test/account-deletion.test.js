const {test}=require('node:test');const assert=require('node:assert/strict');const {PrismaClient}=require('@prisma/client');const bcrypt=require('bcrypt');const {randomUUID}=require('node:crypto');const fs=require('node:fs/promises');const os=require('node:os');const path=require('node:path');
const {AccountDeletionService}=require('../dist/src/auth/account-deletion.service');const {AuthService}=require('../dist/src/auth/auth.service');
const database=process.env.DISPATCH_TEST_DATABASE_URL;
test('self deletion removes the original account, credentials, driver documents and cards while preserving anonymous ledger',{skip:!database},async()=>{
 const url=new URL(database);assert.equal(url.hostname,'127.0.0.1');assert.equal(url.pathname,'/dispatch_test');
 const p=new PrismaClient({datasources:{db:{url:database}}});const root=await fs.mkdtemp(path.join(os.tmpdir(),'account-erasure-'));const oldRoot=process.env.UPLOAD_DIR;process.env.UPLOAD_DIR=root;
 const password='delete-test-password';const phone='+7'+String(Date.now()).slice(-10);let user,peer,profile,order,archiveId,replacement;
 try {
  user=await p.user.create({data:{phone,name:'Private Name',password:await bcrypt.hash(password,4),refCode:randomUUID(),refLink:'private-link',pushToken:'private-push',wallet:{create:{money:123,bonus:15}}},include:{wallet:true}});
  peer=await p.user.create({data:{phone:'peer:'+randomUUID(),name:'Peer',password:'test',refCode:randomUUID(),refLink:'test',referredBy:user.refCode}});
  profile=await p.driverProfile.create({data:{userId:user.id,status:'APPROVED',selfieUrl:'private-document',carNumber:'PRIVATE',online:{create:{isOnline:true,lastLat:49.9,lastLng:82.6}},rating:{create:{}},serviceStats:{create:{}},vehicles:{create:{brand:'Toyota',model:'Camry',plateNumber:'PRIVATE'}}}});
  await fs.mkdir(path.join(root,profile.id));await fs.writeFile(path.join(root,profile.id,'selfie.jpg'),'private-document');
  order=await p.order.create({data:{passengerId:user.id,status:'COMPLETED',fromLat:49.9,fromLng:82.6,toLat:50,toLng:83,fromAddress:'Private pickup',toAddress:'Private destination',comment:'Private note'}});
  await p.orderChatMessage.create({data:{orderId:order.id,senderId:user.id,text:'Private chat'}});
  await p.rideEvent.create({data:{orderId:order.id,toStatus:'COMPLETED',actorUserId:user.id,payload:{phone}}});
  await p.walletTransaction.create({data:{walletId:user.wallet.id,type:'TOPUP',direction:'CREDIT',amount:123,note:phone,actorUserId:user.id}});
  await p.refreshToken.create({data:{userId:user.id,token:'refresh:'+user.id,expiresAt:new Date(Date.now()+60000)}});
  await p.savedPaymentCard.create({data:{userId:user.id,phone,tokenEncrypted:'private-token',tokenHash:randomUUID(),last4:'1234',acquiringId:1,demo:true}});
  await p.cardBinding.create({data:{userId:user.id,phone,acquiringId:1,demo:true}});
  await p.taxProfile.create({data:{userId:user.id,kind:'SELF_EMPLOYED',status:'VERIFIED',iinEncrypted:'encrypted-test-identity',iinHash:'test:'+user.id,iinLast4:'1234',activities:['49320'],consentVersion:'test',consentAt:new Date()}});
  await p.taxAccountingIdentity.create({data:{ownerKey:user.id,iinEncrypted:'encrypted-test-identity',iinHash:'test:'+user.id,iinLast4:'1234',firstIncomeAt:new Date()}});
  await p.taxIncomeEntry.create({data:{ownerKey:user.id,taxpayerKey:'test:'+user.id,eventKey:'tax-erasure:'+user.id,sourceKind:'CITY',sourceId:order.id,currency:'KZT',occurredAt:new Date(),period:'2026-10',profileKind:'SELF_EMPLOYED',status:'ACCOUNTED',gross:1000,opv:10,opvr:10,so:10,osms:10,withheld:40}});
  const service=new AccountDeletionService(p);
  await assert.rejects(service.deleteOwnAccount(user.id,'wrong-password'));assert.ok(await p.user.findUnique({where:{id:user.id}}));
  await p.order.update({where:{id:order.id},data:{status:'IN_PROGRESS'}});await assert.rejects(service.deleteOwnAccount(user.id,password));assert.ok(await p.savedPaymentCard.findFirst({where:{userId:user.id}}));
  await p.order.update({where:{id:order.id},data:{status:'COMPLETED'}});
  await fs.writeFile(path.join(root,'blocked-root'),'blocked');process.env.UPLOAD_DIR=path.join(root,'blocked-root');
  const deletion=await service.deleteOwnAccount(user.id,password);assert.equal(deletion.deleted,true);assert.equal(deletion.filesPending,true);
  assert.equal(await p.accountDeletionFileJob.count({where:{directory:profile.id}}),1);
  process.env.UPLOAD_DIR=root;await service.cleanupFiles();
  assert.equal(await p.user.findUnique({where:{id:user.id}}),null);assert.equal(await p.user.findUnique({where:{phone}}),null);assert.equal(await p.driverProfile.findUnique({where:{id:profile.id}}),null);
  assert.equal(await p.refreshToken.count({where:{userId:user.id}}),0);assert.equal(await p.savedPaymentCard.count({where:{userId:user.id}}),0);assert.equal(await p.cardBinding.count({where:{userId:user.id}}),0);assert.equal(await p.orderChatMessage.count({where:{orderId:order.id}}),0);
  await assert.rejects(fs.access(path.join(root,profile.id)));assert.equal(await p.accountDeletionFileJob.count({where:{directory:profile.id}}),0);
  const erased=await p.order.findUnique({where:{id:order.id}});archiveId=erased.passengerId;assert.notEqual(archiveId,user.id);assert.equal(erased.fromAddress,'Удалено');assert.equal(erased.fromLat,0);
  assert.equal(await p.taxProfile.findUnique({where:{userId:user.id}}),null);
  assert.equal((await p.taxIncomeEntry.findUnique({where:{eventKey:'tax-erasure:'+user.id}})).ownerKey,archiveId);
  assert.equal(await p.taxAccountingIdentity.findUnique({where:{ownerKey:user.id}}),null);
  assert.ok(await p.taxAccountingIdentity.findUnique({where:{ownerKey:archiveId}}));
  const owner=await p.user.findUnique({where:{id:archiveId}});assert.equal(owner.password,'');assert.notEqual(owner.phone,phone);assert.equal(owner.pushToken,null);
  const ledger=await p.walletTransaction.findFirst({where:{walletId:user.wallet.id}});assert.equal(ledger.amount,123);assert.equal(ledger.note,null);assert.equal(ledger.actorUserId,null);assert.equal((await p.user.findUnique({where:{id:peer.id}})).referredBy,null);
  const auth=new AuthService(p,{}, {}, {get:()=>undefined});assert.equal(await auth.validateUser(user.id),null);await assert.rejects(auth.refreshToken('refresh:'+user.id));
  replacement=await p.user.create({data:{phone,name:'New account',password:'test',refCode:randomUUID(),refLink:'test'}});assert.notEqual(replacement.id,user.id);
  await assert.rejects(service.deleteOwnAccount(user.id,password));
 } finally {
  if(oldRoot===undefined)delete process.env.UPLOAD_DIR;else process.env.UPLOAD_DIR=oldRoot;
  if(order){await p.orderChatMessage.deleteMany({where:{orderId:order.id}});await p.rideEvent.deleteMany({where:{orderId:order.id}});await p.order.deleteMany({where:{id:order.id}});}
  if(profile){await p.accountDeletionFileJob.deleteMany({where:{directory:profile.id}});await p.vehicle.deleteMany({where:{driverId:profile.id}});await p.driverOnline.deleteMany({where:{driverId:profile.id}});await p.driverRating.deleteMany({where:{driverId:profile.id}});await p.driverServiceStats.deleteMany({where:{driverId:profile.id}});await p.driverProfile.deleteMany({where:{id:profile.id}});}
  await p.taxIncomeEntry.deleteMany({where:{ownerKey:{in:[user?.id,archiveId].filter(Boolean)}}});
  await p.taxAccountingIdentity.deleteMany({where:{ownerKey:{in:[user?.id,archiveId].filter(Boolean)}}});
  if(user){await p.refreshToken.deleteMany({where:{userId:user.id}});await p.savedPaymentCard.deleteMany({where:{userId:user.id}});await p.cardBinding.deleteMany({where:{userId:user.id}});await p.walletTransaction.deleteMany({where:{walletId:user.wallet.id}});await p.wallet.deleteMany({where:{id:user.wallet.id}});await p.user.deleteMany({where:{id:user.id}});}
  for(const id of [archiveId,peer?.id,replacement?.id].filter(Boolean))await p.user.deleteMany({where:{id}});
  await p.$disconnect();await fs.rm(root,{recursive:true,force:true});
 }
});
