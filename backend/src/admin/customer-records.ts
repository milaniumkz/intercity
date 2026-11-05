import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';

export const customerSelect = {id:true,publicId:true,name:true,phone:true,role:true,cityId:true,blockedAt:true,createdAt:true,updatedAt:true,pushPlatform:true,city:{select:{id:true,name:true}},driverProfile:{select:{id:true,status:true,carModel:true,carNumber:true,rejectionReason:true,acceptCityFixed:true,acceptCityAuction:true,acceptIntercity:true,acceptDelivery:true,acceptCargo:true,createdAt:true,online:{select:{isOnline:true,lastLocationAt:true}},rating:true,priorityFlags:true,serviceStats:{select:{activityScore:true,activityBlockedUntil:true,serviceStartAt:true}},fuelBonus:{select:{bonusActiveUntil:true}}}},biometricProfile:{select:{status:true,enrolledAt:true}}} satisfies Prisma.UserSelect;
export function recordPage(q:any){return {take:Math.min(100,Math.max(1,Number.parseInt(q.take)||30)),skip:Math.max(0,Number.parseInt(q.skip)||0)};}
export function recordDates(q:any){
 const date=(v:any)=>{const d=new Date(String(v));if(!Number.isFinite(d.getTime()))throw new BadRequestException('Некорректная дата фильтра');return d;};
 const gte=q.from?date(q.from):undefined,lt=q.to?date(q.to):undefined;
 if(gte&&lt&&gte>=lt)throw new BadRequestException('Дата начала должна быть раньше окончания');
 return gte||lt?{gte,lt}:undefined;
}
export async function listCustomers(db:any,q:any){
 const page=recordPage(q),search=String(q.search||'').trim().slice(0,120),digits=search.replace(/\D/g,'');
 const where:any={role:{not:'ADMIN'},NOT:{phone:{startsWith:'erased:'}}};
 if(q.invitedBy)where.referredBy=String(q.invitedBy);
 if(q.kind==='driver')where.OR=[{role:'DRIVER'},{driverProfile:{isNot:null}}];
 if(q.kind==='passenger')Object.assign(where,{role:'PASSENGER',driverProfile:{is:null}});
 const dates=recordDates(q);if(dates&&q.hasOrders!=='true'&&q.profileCreated!=='true')where.createdAt=dates;
 if(q.profileCreated==='true')where.driverProfile={is:{createdAt:dates}};
 if(q.approved==='true')where.driverProfile={is:{status:{in:['APPROVED','ACTIVE']}}};
 if(q.hasOrders==='true'){const ids=await db.$queryRaw(Prisma.sql`SELECT DISTINCT "passengerId" FROM(SELECT "passengerId","createdAt" FROM "Order" UNION ALL SELECT "passengerId","createdAt" FROM "IntercityRequest") x WHERE (${dates?.gte??null}::timestamptz IS NULL OR "createdAt">=${dates?.gte??null}) AND (${dates?.lt??null}::timestamptz IS NULL OR "createdAt"<${dates?.lt??null})`);where.id={in:ids.map((x:any)=>x.passengerId)};}
 if(q.driverStatus){where.driverProfile={is:{status:q.driverStatus}};}
 if(q.online==='true')where.driverProfile={is:{...(where.driverProfile?.is||{}),online:{is:{isOnline:true}}}};
 if(search)where.AND=[{OR:[{name:{contains:search,mode:'insensitive'}},{phone:{contains:digits.length>=4?digits.slice(-10):search}},{driverProfile:{is:{OR:[{carNumber:{contains:search,mode:'insensitive'}},{carModel:{contains:search,mode:'insensitive'}}]}}}]}];
 const [items,total]=await Promise.all([db.user.findMany({where,select:customerSelect,orderBy:[{createdAt:'desc'},{id:'desc'}],...page}),db.user.count({where})]);
 return {items,total,...page};
}
export async function customerOverview(db:any,id:string,finance=false){
 const user=await db.user.findFirst({where:{id,NOT:{phone:{startsWith:'erased:'}}},select:customerSelect});if(!user)throw new NotFoundException('Пользователь не найден');
 const raw=await db.user.findUnique({where:{id},select:{refCode:true,referredBy:true}});
 const [invited,referrer,vehicles,wallet]=await Promise.all([
  db.user.count({where:{referredBy:raw.refCode,NOT:{phone:{startsWith:'erased:'}}}}),
  raw.referredBy?db.user.findFirst({where:{OR:[{refCode:raw.referredBy},{id:raw.referredBy}]},select:{id:true,name:true,phone:true}}):null,
  user.driverProfile?db.vehicle.findMany({where:{driverId:user.driverProfile.id},select:{id:true,brand:true,model:true,year:true,plateNumber:true,isActive:true,verificationStatus:true}}):[],
  finance?db.wallet.findUnique({where:{userId:id},select:{money:true,bonus:true,moneyRub:true,bonusRub:true,lockedBonus:true,lockedBonusRub:true,referralMoney:true}}):null]);
 return {user,vehicles,wallet,referrals:{code:raw.refCode,invited,referrer},permissions:{finance}};
}
export async function customerTransactions(db:any,id:string,q:any){const page=recordPage(q),where={wallet:{userId:id}};const [items,total]=await Promise.all([db.walletTransaction.findMany({where,orderBy:[{createdAt:'desc'},{id:'desc'}],...page,select:{id:true,type:true,direction:true,balanceSource:true,amount:true,currency:true,note:true,createdAt:true,orderId:true,intercityRequestId:true}}),db.walletTransaction.count({where})]);return{items,total,...page};}
export async function customerTrips(db:any,q:any){
 const page=recordPage(q),dates=recordDates(q);let filter=Prisma.sql`TRUE`;
 if(q.id)filter=Prisma.sql`${filter} AND t.id=${String(q.id)}`;
 if(q.userId)filter=Prisma.sql`${filter} AND (t."passengerId"=${q.userId} OR t."driverUserId"=${q.userId})`;
 if(dates?.gte)filter=Prisma.sql`${filter} AND t.${Prisma.raw(q.completedInPeriod==='true'?'"completedAt"':'"createdAt"')}>=${dates.gte}`;
 if(dates?.lt)filter=Prisma.sql`${filter} AND t.${Prisma.raw(q.completedInPeriod==='true'?'"completedAt"':'"createdAt"')}<${dates.lt}`;
 if(q.completedInPeriod==='true')filter=Prisma.sql`${filter} AND t.status='COMPLETED'`;
 if(q.status==='ACTIVE')filter=Prisma.sql`${filter} AND t.status NOT IN ('COMPLETED','CANCELLED','EXPIRED','REJECTED')`;
 else if(q.status==='EXPIRED_GROUP')filter=Prisma.sql`${filter} AND t.status IN ('EXPIRED','REJECTED')`;
 else if(q.status)filter=Prisma.sql`${filter} AND t.status=${String(q.status)}`;
 if(q.mode)filter=Prisma.sql`${filter} AND t.mode=${String(q.mode)}`;
 const rows=await db.$queryRaw(Prisma.sql`WITH trips AS (
 SELECT o.id,'ORDER' AS source,CASE WHEN o.mode='CARGO' THEN 'CARGO' WHEN o.mode='INTERCITY' THEN 'INTERCITY' WHEN o.mode='DELIVERY' THEN COALESCE(o."requestType",'DELIVERY_CITY') WHEN o."requestType"='CITY_AUCTION' THEN 'CITY_AUCTION' ELSE 'CITY_FIXED' END AS mode,o.status::text,o."createdAt",o."completedAt",o."passengerId",d."userId" AS "driverUserId",o."fromAddress" AS origin,o."toAddress" AS destination,o.price,o.currency,o."scheduledFor" AS departure
 FROM "Order" o LEFT JOIN "DriverProfile" d ON d.id=o."driverId"
 UNION ALL SELECT r.id,'MARKET',r."requestType",r.status,r."createdAt",r."completedAt",r."passengerId",r."selectedDriverId",COALESCE(r."fromAddressLabel",r."fromCity"),COALESCE(r."toAddressLabel",r."toCity"),COALESCE(f.price,r.price),r.currency,r.date FROM "IntercityRequest" r LEFT JOIN "IntercityOffer" f ON f.id=r."selectedOfferId"
 ), filtered AS(SELECT t.*,p.name AS "passengerName",p.phone AS "passengerPhone",u.name AS "driverName",u.phone AS "driverPhone" FROM trips t LEFT JOIN "User" p ON p.id=t."passengerId" LEFT JOIN "User" u ON u.id=t."driverUserId" WHERE ${filter}) SELECT json_build_object('total',(SELECT count(*)::int FROM filtered),'items',COALESCE((SELECT json_agg(x) FROM(SELECT * FROM filtered ORDER BY "createdAt" DESC,id DESC LIMIT ${page.take} OFFSET ${page.skip})x),'[]'::json)) AS data`);
 return {...rows[0].data,...page};
}
export function customerEdit(body:any){
 const reason=typeof body.reason==='string'?body.reason.trim():'';if(reason.length<5||reason.length>1000)throw new BadRequestException('Укажите причину изменения, от 5 до 1000 символов');
 const fields=body.fields;if(!fields||typeof fields!=='object'||Array.isArray(fields))throw new BadRequestException('Укажите изменяемые данные');
 const allowed=new Set(['name','phone','cityId','blocked']);for(const key of Object.keys(fields))if(!allowed.has(key))throw new BadRequestException('Поле нельзя изменять в карточке: '+key);
 const data:any={};
 if('name'in fields){if(typeof fields.name!=='string'||fields.name.trim().length<2||fields.name.length>100)throw new BadRequestException('Имя: от 2 до 100 символов');data.name=fields.name.trim();}
 if('phone'in fields){const digits=String(fields.phone).replace(/\D/g,'');if(!/^[78]\d{10}$/.test(digits))throw new BadRequestException('Телефон должен содержать 11 цифр и начинаться на +7 или 8');data.phone='+7'+digits.slice(1);}
 if('cityId'in fields){if(fields.cityId!==null&&typeof fields.cityId!=='string')throw new BadRequestException('Выберите город');data.cityId=fields.cityId||null;}
 if('blocked'in fields){if(typeof fields.blocked!=='boolean')throw new BadRequestException('Неверное значение блокировки');data.blockedAt=fields.blocked?new Date():null;}
 if(!Object.keys(data).length)throw new BadRequestException('Нет изменений');
 if('phone'in data||'blockedAt'in data)data.authVersion={increment:1};
 return {data,reason};
}

export async function editDriverRecord(db:any,userId:string,body:any){
 const reason=typeof body.reason==='string'?body.reason.trim():'';if(reason.length<5||reason.length>1000)throw new BadRequestException('Укажите причину изменения, от 5 до 1000 символов');
 const fields=body.fields;if(!fields||typeof fields!=='object'||Array.isArray(fields))throw new BadRequestException('Укажите настройки водителя');
 const booleans=['acceptCityFixed','acceptCityAuction','acceptIntercity','acceptDelivery','acceptCargo'];
 const flagNames=['hasCheckers','hasBranding'];
 const allowed=new Set([...booleans,...flagNames,'carModel','carNumber']);const data:any={},flagData:any={};
 for(const key of Object.keys(fields)){if(!allowed.has(key))throw new BadRequestException('Недопустимое поле водителя');if(booleans.includes(key)||flagNames.includes(key)){if(typeof fields[key]!=='boolean')throw new BadRequestException('Настройка должна быть включена или выключена');if(flagNames.includes(key))flagData[key]=fields[key];else data[key]=fields[key];}}
 for(const key of ['carModel','carNumber'])if(key in fields){if(typeof fields[key]!=='string'||!fields[key].trim()||fields[key].length>100)throw new BadRequestException('Укажите модель и госномер автомобиля');data[key]=key==='carNumber'?fields[key].trim().toUpperCase():fields[key].trim();}
 if(!Object.keys(data).length&&!Object.keys(flagData).length)throw new BadRequestException('Нет изменений');
 await db.$executeRaw(Prisma.sql`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`);
 const before=await db.driverProfile.findUnique({where:{userId}});if(!before)throw new NotFoundException('Анкета водителя не найдена');
 const carChanged=('carModel'in data&&data.carModel!==before.carModel)||('carNumber'in data&&data.carNumber!==before.carNumber);
 if(carChanged){
  const active=await db.order.count({where:{driverId:before.id,status:{in:['DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS']}}});
  const market=await db.intercityRequest.count({where:{selectedDriverId:userId,status:{in:['ACCEPTED','DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','IN_PROGRESS']}}});
  if(active||market)throw new BadRequestException('Автомобиль нельзя менять во время активной поездки');
  await db.driverOnline.updateMany({where:{driverId:before.id},data:{isOnline:false}});
  data.status='PENDING';data.rejectionReason='Данные автомобиля изменены. Требуется повторная сверка документов';
  await db.vehicle.updateMany({where:{driverId:before.id,isActive:true},data:{verificationStatus:'PENDING'}});
 }
 if(Object.keys(flagData).length)await db.driverPriorityFlags.upsert({where:{driverId:before.id},create:{driverId:before.id,...flagData},update:flagData});
 const profile=await db.driverProfile.update({where:{id:before.id},data});return {profile,before,reason,carChanged};
}
