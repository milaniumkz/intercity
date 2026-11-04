// Explicit operator-requested reset. Never called by the application or migrations.
const {Prisma,PrismaClient}=require(require.resolve('@prisma/client',{paths:['/app',process.cwd(),process.cwd()+'/backend']}));
const assert=require('node:assert/strict'),crypto=require('node:crypto'),fs=require('node:fs/promises'),path=require('node:path');
const keepModels=new Set(['City','CarMake','CarModel','TariffCity','TariffCargo','TariffDelivery','AppSettings','AdminRole','AdminPermission','AdminRolePermission','PromoCode','NotificationCampaign','TechAccount','TechSession','TechAudit','TechRule','TechPush','TechNotification','TechIssue','TechComment','TechReport','TechLoginAttempt']);
const models=Prisma.dmmf.datamodel.models,byName=new Map(models.map(m=>[m.name,m]));
const delegate=m=>m.name[0].toLowerCase()+m.name.slice(1),pk=m=>m.fields.find(f=>f.isId)?.name;
const digest=x=>crypto.createHash('sha256').update(JSON.stringify(x)).digest('hex');
async function reset(db,commit=false){
 const all=await db.user.findMany({orderBy:{id:'asc'}}),roles=await db.adminUserRole.findMany();
 const adminIds=all.filter(u=>u.role==='ADMIN'||roles.some(r=>r.userId===u.id)).map(u=>u.id),users=all.filter(u=>!adminIds.includes(u.id)),ids=users.map(u=>u.id);
 assert(adminIds.length>0,'No protected administrative accounts');assert(all.some(u=>u.role==='ADMIN'&&!u.blockedAt),'No active administrator');
 const adminBefore=all.filter(u=>adminIds.includes(u.id)),adminWallets=await db.wallet.findMany({where:{userId:{in:adminIds}},orderBy:{id:'asc'}});
 const adminDrivers=await db.driverProfile.findMany({where:{userId:{in:adminIds}},orderBy:{id:'asc'}}),adminDriverIds=adminDrivers.map(d=>d.id);
 const adminPrincipals=[...adminIds,...adminDriverIds];
 const marks=new Map(),counts={};
 async function mark(name,where){
  assert(!keepModels.has(name),'Attempt to modify protected collection '+name);const m=byName.get(name);assert(m&&pk(m),'Unknown model '+name);
  const rows=await db[delegate(m)].findMany({where,select:{[pk(m)]:true}});let set=marks.get(name);if(!set){set=new Set();marks.set(name,set);}const old=set.size;for(const r of rows)set.add(r[pk(m)]);return set.size-old;
 }
 await mark('User',{id:{in:ids}});
 if(byName.has('BiometricChallenge'))await mark('BiometricChallenge',{userId:null});
 await mark('IntercityRequest',{OR:[{passengerId:{notIn:adminIds}},{selectedDriverId:{not:null,notIn:adminPrincipals}}]});
 await mark('IntercityOffer',{driverId:{notIn:adminPrincipals}});
 await mark('RideSharingTrip',{driverId:{notIn:adminPrincipals}});
 await mark('RideSharingBooking',{passengerId:{notIn:adminIds}});
 for(const name of ['RefreshToken','SavedPaymentCard','CardBinding'])await mark(name,{userId:{notIn:adminIds}});
 for(const name of ['TaxAccountingIdentity','TaxIncomeEntry','TaxRemittance','TaxPeriodBasis'])await mark(name,{ownerKey:{notIn:adminIds}});
 await mark('DriverDailyParticipation',{driverId:{notIn:adminDriverIds}});
 await mark('TripVerification',{OR:[{driverUserId:{notIn:adminIds}},{passengerId:{notIn:adminIds}},{driverId:{notIn:adminDriverIds}}]});
 await mark('TripCardPayment',{OR:[{passengerId:{notIn:adminIds}},{driverUserId:{notIn:adminIds}}]});
 await mark('TechFile',{userId:{in:ids}});
 await mark('TechEvent',{OR:[{userId:{in:ids}},{actorId:{in:ids}}]});
 // Collect all true foreign-key descendants before deleting anything.
 for(let turn=0;turn<models.length;turn++){
  let changed=0;
  for(const m of models){if(keepModels.has(m.name))continue;for(const rel of m.fields.filter(f=>f.kind==='object'&&f.relationFromFields?.length===1&&f.relationToFields?.length===1)){
   const parent=byName.get(rel.type),parentIds=marks.get(rel.type);if(!parentIds?.size)continue;
   assert.equal(rel.relationToFields[0],pk(parent),'Unexpected foreign key');
   changed+=await mark(m.name,{[rel.relationFromFields[0]]:{in:[...parentIds]}});
  }}
  const paymentIds=[...(marks.get('TripCardPayment')||[])];if(paymentIds.length)changed+=await mark('CardPaymentAttempt',{paymentId:{in:paymentIds}});
  if(!changed)break;assert(turn<models.length-1,'Dependency closure failed');
 }
 const objectIds=[...marks.values()].flatMap(s=>[...s]);
 await mark('AdminAuditLog',{targetId:{in:objectIds}});
 await mark('TechEvent',{objectId:{in:objectIds}});
 const techFiles=await db.techFile.findMany({where:{id:{in:[...(marks.get('TechFile')||[])]}},select:{path:true}});
 const dirs=new Set([...(marks.get('DriverProfile')||[]),...ids]);
 for(const job of await db.accountDeletionFileJob.findMany()){if(!adminPrincipals.includes(job.directory)){dirs.add(job.directory);await mark('AccountDeletionFileJob',{id:job.id});}}
 const catalog={};for(const name of keepModels){const m=byName.get(name);if(!m)continue;const rows=await db.$queryRawUnsafe(`SELECT count(*)::int AS count, md5(COALESCE(string_agg(row_to_json(t)::text,E'\\n' ORDER BY t."${pk(m)}"),'')) AS hash FROM "${m.dbName||name}" t`);catalog[name]=rows[0];}
 for(const dir of dirs)assert(/^[0-9a-f-]{36}$/i.test(dir),'Unexpected user directory');
 for(const file of techFiles)assert(/^[a-f0-9]{32}\.bin$/.test(file.path),'Unexpected private file path');
 const publicReport={usersBefore:all.length,administratorsRetained:adminIds.length,usersToDelete:ids.length,rowsToDelete:Object.fromEntries([...marks].map(([n,s])=>[n,s.size])),catalogs:Object.fromEntries(Object.entries(catalog).map(([n,x])=>[n,x.count])),privateFiles:techFiles.length,userDirectories:dirs.size};
 if(!commit)return publicReport;
 const visited=new Set();
 async function remove(name){if(visited.has(name))return;visited.add(name);for(const m of models){if(m.fields.some(f=>f.kind==='object'&&f.type===name&&f.relationFromFields?.length))await remove(m.name);}
  const values=marks.get(name);if(values?.size){assert(!keepModels.has(name));const m=byName.get(name);counts[name]=(await db[delegate(m)].deleteMany({where:{[pk(m)]:{in:[...values]}}})).count;}
 }
 for(const name of marks.keys())await remove(name);
 assert.deepEqual(await db.user.findMany({orderBy:{id:'asc'}}),adminBefore,'Administrative account changed');
 assert.deepEqual(await db.wallet.findMany({where:{userId:{in:adminIds}},orderBy:{id:'asc'}}),adminWallets,'Administrative balance changed');
 for(const [name,before]of Object.entries(catalog)){const m=byName.get(name),[after]=await db.$queryRawUnsafe(`SELECT count(*)::int AS count, md5(COALESCE(string_agg(row_to_json(t)::text,E'\\n' ORDER BY t."${pk(m)}"),'')) AS hash FROM "${m.dbName||name}" t`);assert.deepEqual(after,before,'Protected catalogue changed: '+name);}
 assert.equal(await db.user.count({where:{id:{notIn:adminIds}}}),0,'Nonadministrative account remains');
 await db.adminAuditLog.create({data:{adminId:adminBefore.find(u=>u.role==='ADMIN'&&!u.blockedAt).id,action:'OWNER_REQUEST_RESET_CUSTOMERS',targetType:'SYSTEM',status:'SUCCESS',details:{deletedUsers:ids.length,deletedRows:counts,protectedCatalogsUnchanged:true,backupRequired:true}}});
 return {...publicReport,committed:true,deletedRows:counts,catalogsUnchanged:true,adminsUnchanged:true,cleanup:{directories:[...dirs],identityDirectories:[...dirs],privateFiles:techFiles.map(f=>f.path)}};
}
async function cleanupFiles(cleanup,uploadRoot,privateRoot){
 let removed=0;
 for(const [root,dirs] of [[uploadRoot,cleanup.directories],[path.join(privateRoot,'identity'),cleanup.identityDirectories||[]]]){
  for(const dir of dirs){assert(/^[0-9a-f-]{36}$/i.test(dir));const full=path.resolve(root,dir);assert(full.startsWith(path.resolve(root)+path.sep));await fs.rm(full,{recursive:true,force:true});removed++;}
 }
 for(const file of cleanup.privateFiles){assert(/^[a-f0-9]{32}\.bin$/.test(file));await fs.rm(path.join(privateRoot,file),{force:true});removed++;}
 return removed;
}
module.exports={reset,cleanupFiles};
if(require.main===module){const p=new PrismaClient();(async()=>{const commit=process.argv.includes('--commit');const report=await p.$transaction(async tx=>{if(!commit)await tx.$executeRawUnsafe('SET TRANSACTION READ ONLY');return reset(tx,commit)},{maxWait:10000,timeout:120000,isolationLevel:'Serializable'});if(commit){if(process.env.RESET_MANIFEST)await fs.writeFile(process.env.RESET_MANIFEST,JSON.stringify(report.cleanup),{mode:0o600});const uploadRoot=process.env.UPLOAD_DIR||'/app/uploads',privateRoot=process.env.TECH_STORAGE_DIR||'/app/technical-data';const removed=await cleanupFiles(report.cleanup,uploadRoot,privateRoot);delete report.cleanup;report.filesCleanupCompleted=true;report.cleanupTargets=removed;}console.log(JSON.stringify(report));})().catch(e=>{console.error('Customer reset aborted: '+e.message);process.exitCode=1}).finally(()=>p.$disconnect());}
