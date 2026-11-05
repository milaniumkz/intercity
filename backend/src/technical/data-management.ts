import {BadRequestException,ConflictException,ForbiddenException,NotFoundException} from '@nestjs/common';
import {Prisma} from '@prisma/client';
import {createHash} from 'crypto';
import {customerEdit,editDriverRecord} from '../admin/customer-records';

const titles:Record<string,string>={User:'Пользователи',DriverProfile:'Анкеты водителей',Vehicle:'Автомобили',Order:'Городские заказы, доставка и грузовые',IntercityRequest:'Междугородние заявки',IntercityOffer:'Предложения водителей',OrderOffer:'Предложения по городским заказам',Wallet:'Кошельки',WalletTransaction:'Операции кошельков',City:'Города',TariffCity:'Городские тарифы',TariffCargo:'Грузовые тарифы',TariffDelivery:'Тарифы доставки',PromoCode:'Промокоды',PromoUsage:'Использование промокодов',Complaint:'Обращения и жалобы',DriverIntercityRoute:'Маршруты водителей',DriverOnline:'Водители на линии',DriverRating:'Рейтинг водителей',DriverPriorityFlags:'Шашки и брендирование',DriverServiceStats:'Активность водителей',DriverActivityEvent:'История активности',DriverPartnerFuelBonus:'Топливные бонусы',DriverDailyParticipation:'Участие водителей',TopupRequest:'Пополнения',PayoutRequest:'Вывод средств',RideEvent:'Этапы городских поездок',RideSharingTrip:'Совместные поездки',RideSharingBooking:'Бронирования мест',TripVerification:'Подтверждение поездок',TaxIncomeEntry:'Учёт доходов',TaxRemittance:'Налоговые платежи',TaxPeriodBasis:'Налоговые периоды',NotificationCampaign:'Рассылки',NotificationDispatchJob:'Задания рассылок',CarMake:'Марки автомобилей',CarModel:'Модели автомобилей'};
export const fieldTitles:Record<string,string>={id:'ID записи',publicId:'Публичный номер',name:'Имя / название',phone:'Телефон',role:'Роль',cityId:'Город',userId:'Пользователь',driverId:'Водитель',passengerId:'Пассажир',selectedDriverId:'Выбранный водитель',selectedOfferId:'Выбранное предложение',createdAt:'Создано',updatedAt:'Обновлено',completedAt:'Завершено',blockedAt:'Заблокирован с',status:'Состояние',money:'Денежный баланс, ₸',bonus:'Бонусы, ₸',moneyRub:'Денежный баланс, ₽',bonusRub:'Бонусы, ₽',lockedBonus:'Зарезервированные средства, ₸',lockedBonusRub:'Зарезервированные средства, ₽',referralMoney:'Реферальный баланс, ₸',refCode:'Код приглашения',referredBy:'Код пригласившего',refLink:'Реферальная ссылка',pushPlatform:'Платформа',mustChangePassword:'Обязательная смена пароля',carModel:'Марка и модель',carNumber:'Госномер',brand:'Марка',model:'Модель',year:'Год выпуска',plateNumber:'Госномер',color:'Цвет',isActive:'Включено',verificationStatus:'Проверка автомобиля',rejectionReason:'Причина отклонения',acceptCityFixed:'Город',acceptCityAuction:'Городской аукцион',acceptIntercity:'Межгород',acceptDelivery:'Доставка',acceptCargo:'Грузовые',price:'Стоимость',amount:'Сумма',currency:'Валюта',mode:'Режим',requestType:'Тип заказа',paymentMethod:'Оплата',fromAddress:'Откуда',toAddress:'Куда',fromCity:'Город отправления',toCity:'Город назначения',fromAddressLabel:'Адрес отправления',toAddressLabel:'Адрес назначения',date:'Дата отправления',scheduledFor:'Дата и время подачи',comment:'Комментарий',seats:'Количество мест',seatsTotal:'Всего мест',seatsAvailable:'Свободных мест',baggage:'Багаж',itemDescription:'Описание груза',recipientContact:'Контакт получателя',deliveryRecipientContact:'Контакт получателя',deliveryItemDescription:'Описание отправления',basePrice:'Базовая стоимость',minPrice:'Минимальная стоимость',pricePerKm:'За километр',pricePerMin:'За минуту',pricePerKg:'За килограмм',doorToDoorFee:'От двери до двери',countryCode:'Страна',region:'Регион',lat:'Широта',lng:'Долгота',fromLat:'Широта отправления',fromLng:'Долгота отправления',toLat:'Широта назначения',toLng:'Долгота назначения',walletId:'Кошелёк',orderId:'Заказ',intercityRequestId:'Междугородняя заявка',type:'Тип операции',direction:'Направление',balanceSource:'Источник средств',note:'Примечание',code:'Код',title:'Заголовок',text:'Текст',discountType:'Тип скидки',discountValue:'Размер скидки',minOrderAmount:'Минимальная сумма заказа',maxDiscount:'Максимальная скидка',usageLimit:'Лимит использований',perUserLimit:'Лимит на человека',startsAt:'Начало действия',expiresAt:'Окончание действия',vehicleClass:'Класс автомобиля',distanceKm:'Расстояние, км',durationMin:'Длительность, мин',commissionAmount:'Комиссия',bonusUsedAmount:'Оплачено бонусами',driverRating:'Оценка водителя',passengerRating:'Оценка пассажира',departureAt:'Отправление',acceptedAt:'Принято',isOnline:'На линии',lastLocationAt:'Обновление геопозиции',ratingAvg:'Средняя оценка',ratingCount:'Количество оценок',hasCheckers:'Есть шашки',hasBranding:'Есть брендирование'};
const edit:Record<string,string[]>={User:['name','phone','cityId'],DriverProfile:['carModel','carNumber','acceptCityFixed','acceptCityAuction','acceptIntercity','acceptDelivery','acceptCargo'],Order:['fromAddress','toAddress','fromLat','fromLng','toLat','toLng','comment','scheduledFor','price','deliveryRecipientContact','deliveryItemDescription'],IntercityRequest:['fromCity','toCity','fromAddressLabel','toAddressLabel','fromLat','fromLng','toLat','toLng','comment','date','price','baggage','itemDescription','recipientContact'],City:['name','aliases','region','countryCode','lat','lng','isActive'],TariffCity:['name','vehicleClass','basePrice','pricePerKm','pricePerMin','minPrice','isActive'],TariffCargo:['countryCode','name','basePrice','pricePerKm','pricePerKg','minPrice','isActive'],TariffDelivery:['countryCode','name','basePrice','pricePerKm','pricePerKg','minPrice','doorToDoorFee','isActive'],PromoCode:['title','discountType','discountValue','minOrderAmount','maxDiscount','usageLimit','perUserLimit','startsAt','expiresAt','isActive']};
// Credentials, biometric material, bank tokens and private document paths never enter the grid.
const hidden=/(password|secret|token|encrypted|template|signature|hash|paymentCardId|iin|Url$|Path$|authVersion)/i;
const models=Prisma.dmmf.datamodel.models.filter(m=>titles[m.name]);
const fingerprint=(row:any)=>createHash('sha256').update(JSON.stringify(row)).digest('hex');
function modelFor(name:string){const model=models.find(m=>m.name===name);if(!model)throw new NotFoundException('Раздел данных не найден');return model;}
function keyFor(name:string){return modelFor(name).fields.find(f=>f.isId)?.name||'id';}
function fieldsFor(name:string){return modelFor(name).fields.filter(f=>f.kind!=='object'&&!hidden.test(f.name));}
function delegate(db:any,name:string){modelFor(name);return db[name[0].toLowerCase()+name.slice(1)];}
const selection=(name:string)=>Object.fromEntries(fieldsFor(name).map(f=>[f.name,true]));
export function dataCatalog(){return models.map(m=>({name:m.name,key:keyFor(m.name),title:titles[m.name],editable:(edit[m.name]||[]).length>0,fields:fieldsFor(m.name).map(f=>({name:f.name,label:fieldTitles[f.name]||f.name,type:f.type,list:f.isList,nullable:!f.isRequired,editable:(edit[m.name]||[]).includes(f.name),options:f.kind==='enum'?Prisma.dmmf.datamodel.enums.find(e=>e.name===f.type)?.values.map(v=>v.name):undefined}))}));}
function typed(field:any,value:any){
 if(value===null){if(field.isRequired)throw new BadRequestException('Поле обязательно: '+(fieldTitles[field.name]||field.name));return null;}
 if(field.isList){if(!Array.isArray(value)||value.length>100||value.some(v=>typeof v!=='string'||v.length>500))throw new BadRequestException('Ожидается список строк');return value;}
 if(field.kind==='enum'){if(!Prisma.dmmf.datamodel.enums.find(e=>e.name===field.type)?.values.some(v=>v.name===value))throw new BadRequestException('Выберите значение из списка');return value;}
 if(field.type==='Boolean'){if(typeof value!=='boolean')throw new BadRequestException('Ожидается да или нет');return value;}
 if(['Int','Float','Decimal'].includes(field.type)){if(typeof value!=='number'||!Number.isFinite(value)||Math.abs(value)>1e12||field.type==='Int'&&!Number.isSafeInteger(value))throw new BadRequestException('Введите корректное число');return value;}
 if(field.type==='DateTime'){if(typeof value!=='string'||!Number.isFinite(new Date(value).getTime()))throw new BadRequestException('Введите дату и время');return new Date(value);}
 if(field.type==='Json'){if(JSON.stringify(value).length>10000)throw new BadRequestException('Слишком большой объект');return value;}
 if(typeof value!=='string'||value.length>10000)throw new BadRequestException('Введите текст до 10000 символов');return value;
}
export async function dataList(db:any,name:string,q:any){
 const fields=fieldsFor(name),where:any={},and:any[]=[],take=Math.min(100,Math.max(1,parseInt(q.take)||30)),skip=Math.min(1000000,Math.max(0,parseInt(q.skip)||0));
 if(name==='User')and.push({NOT:{phone:{startsWith:'erased:'}}});
 const search=String(q.search||'').trim().slice(0,150);if(search)and.push({OR:fields.filter(f=>f.type==='String'&&!f.isList).map(f=>({[f.name]:{contains:search,mode:'insensitive'}}))});
 let filters:any=[];try{filters=typeof q.filters==='string'?JSON.parse(q.filters):(q.filters||[]);}catch{throw new BadRequestException('Некорректные фильтры');}
 if(!Array.isArray(filters)||filters.length>20)throw new BadRequestException('Не более 20 условий');
 for(const filter of filters){const f=fields.find(f=>f.name===filter.field);if(!f)throw new BadRequestException('Неизвестное поле фильтра');const op=filter.op||'eq';let value=filter.value;
  if(op==='empty'){if(f.isRequired&&!f.isList)throw new BadRequestException('Это обязательное поле не бывает пустым');and.push({[f.name]:f.isList?{isEmpty:true}:null});continue;}
  if(op==='contains'){if(f.type!=='String'||f.isList)throw new BadRequestException('Поиск текста недоступен для этого поля');and.push({[f.name]:{contains:String(value).slice(0,200),mode:'insensitive'}});continue;}
  value=typed(f,value);if(op==='eq')and.push({[f.name]:value});else if(['gte','lte','gt','lt'].includes(op)&&['Int','Float','Decimal','DateTime'].includes(f.type))and.push({[f.name]:{[op]:value}});else throw new BadRequestException('Недопустимое условие фильтра');
 }
 if(and.length)where.AND=and;
 const sort=fields.find(f=>f.name===q.sort&&!f.isList&&f.type!=='Json')?.name||(fields.some(f=>f.name==='createdAt')?'createdAt':keyFor(name));
 const orderBy=[{[sort]:q.direction==='asc'?'asc':'desc'},...(sort===keyFor(name)?[]:[{[keyFor(name)]:'desc'}])];
 const api=delegate(db,name);const [items,total]=await Promise.all([api.findMany({where,select:selection(name),orderBy,take,skip}),api.count({where})]);return{items,total,take,skip};
}
export async function dataRecord(db:any,name:string,id:string){const row=await delegate(db,name).findUnique({where:{[keyFor(name)]:id},select:selection(name)});if(!row)throw new NotFoundException('Запись не найдена');return{record:row,version:fingerprint(row)};}
export async function editDataRecord(db:any,name:string,id:string,body:any,audit:(tx:any,data:any)=>Promise<any>){
 const fields=body.fields;if(!fields||typeof fields!=='object'||Array.isArray(fields)||!Object.keys(fields).length)throw new BadRequestException('Нет изменений');
 const allowed=edit[name]||[];const data:any={};for(const [key,value]of Object.entries(fields)){if(!allowed.includes(key))throw new ForbiddenException('Поле изменяется специальной операцией или доступно только для просмотра: '+(fieldTitles[key]||key));data[key]=typed(fieldsFor(name).find(f=>f.name===key),value);}
 return db.$transaction(async(tx:any)=>{
  await tx.$executeRaw(Prisma.sql`SELECT id FROM ${Prisma.raw('"'+modelFor(name).name+'"')} WHERE ${Prisma.raw('"'+keyFor(name)+'"')}=${id} FOR UPDATE`);
  const before=await dataRecord(tx,name,id);if(body.version!==before.version)throw new ConflictException('Запись уже изменилась. Обновите карточку и повторите изменение');
  if(name==='User'){
   if(before.record.role==='ADMIN')throw new ForbiddenException('Администратор изменяется в настройках доступа');
   const patch=customerEdit({fields,reason:body.reason}).data;if(patch.phone===before.record.phone){delete patch.phone;delete patch.authVersion;}await tx.user.update({where:{id},data:patch});if(patch.authVersion)await tx.refreshToken.deleteMany({where:{userId:id}});
  }else if(name==='DriverProfile')await editDriverRecord(tx,before.record.userId,{fields,reason:body.reason});
  else {
   if(['Order','IntercityRequest'].includes(name)){
    const open=name==='Order'?['CREATED','SEARCHING_DRIVER']:['OPEN'];
    if(!open.includes(before.record.status))throw new ConflictException('Маршрут, время и цену можно менять до выбора водителя. После назначения используйте управление поездкой');
    if(before.record.bonusUsedAmount>0||before.record.paidWithBonus)throw new ConflictException('Заказ уже оплачен бонусами. Прямое изменение недоступно');
    if(name==='IntercityRequest'&&await tx.intercityOffer.count({where:{requestId:id}}))throw new ConflictException('На заявку уже поступили предложения. Изменение маршрута и стоимости требует новой заявки');
   }
   for(const key of Object.keys(data))if(typeof data[key]==='number'&&!/^(lat|lng|fromLat|fromLng|toLat|toLng)$/.test(key)&&data[key]<0)throw new BadRequestException('Суммы и количества не могут быть отрицательными');
   for(const key of ['lat','fromLat','toLat'])if(data[key]!=null&&Math.abs(data[key])>90)throw new BadRequestException('Широта от −90 до 90');
   for(const key of ['lng','fromLng','toLng'])if(data[key]!=null&&Math.abs(data[key])>180)throw new BadRequestException('Долгота от −180 до 180');
   if(data.countryCode&&!['KZ','RU'].includes(data.countryCode))throw new BadRequestException('Страна: KZ или RU');
   if(name==='PromoCode'&&(data.discountType||before.record.discountType)==='PERCENT'&&(data.discountValue??before.record.discountValue)>100)throw new BadRequestException('Процент скидки не больше 100');
   await delegate(tx,name).update({where:{id},data});
  }
  const after=await dataRecord(tx,name,id);await audit(tx,{model:name,id,reason:body.reason,before:before.record,after:after.record});return after;
 });
}
const cents=(v:any)=>{if(typeof v!=='number'||!Number.isFinite(v)||v<0||v>1e9||Math.abs(v*100-Math.round(v*100))>1e-5)throw new BadRequestException('Сумма от 0 до 1 000 000 000, не более двух знаков после запятой');return Math.round(v*100);};
export async function adjustWallet(db:any,userId:string,body:any,actorId:string,audit:(tx:any,data:any)=>Promise<any>){
 const allowed=['money','bonus','moneyRub','bonusRub','referralMoney'];if(!allowed.includes(body.field))throw new BadRequestException('Выберите денежный или бонусный баланс');
 const target=cents(body.value),expected=(body.expected<0?-1:1)*cents(Math.abs(body.expected));if(typeof body.operationId!=='string'||!/^[a-f0-9-]{36}$/i.test(body.operationId))throw new BadRequestException('Некорректный номер операции');
 const key='technical-adjust:'+body.operationId,field=body.field,currency=field.endsWith('Rub')?'RUB':'KZT',source=field==='referralMoney'?'REFERRAL':field.startsWith('bonus')?'BONUS':'MONEY';
 return db.$transaction(async(tx:any)=>{
  await tx.$executeRaw(Prisma.sql`SELECT pg_advisory_xact_lock(hashtext(${key}))`);
  await tx.$executeRaw(Prisma.sql`SELECT id FROM "User" WHERE id=${userId} FOR UPDATE`);
  const user=await tx.user.findUnique({where:{id:userId},select:{id:true,role:true,phone:true}});if(!user||user.phone.startsWith('erased:'))throw new NotFoundException('Пользователь не найден');if(user.role==='ADMIN')throw new ForbiddenException('Нельзя корректировать кошелёк администратора');
  await tx.wallet.upsert({where:{userId},create:{userId},update:{}});
  const wallet=await tx.wallet.findUnique({where:{userId}});await tx.$executeRaw(Prisma.sql`SELECT id FROM "Wallet" WHERE id=${wallet.id} FOR UPDATE`);
  const previous=await tx.walletTransaction.findFirst({where:{idempotencyKey:key}});if(previous){const logged=await tx.techAudit.findFirst({where:{action:'wallet.adjustment',objectId:body.operationId}});if(previous.walletId!==wallet.id||previous.balanceSource!==source||previous.currency!==currency||logged?.data?.field!==field||Number(logged?.data?.after)!==target/100)throw new ConflictException('Номер операции уже использован');return{ok:true,repeated:true};}
  const current=await tx.wallet.findUnique({where:{id:wallet.id}}),before=Math.round(Number(current[field])*100);
  if(before!==expected)throw new ConflictException('Баланс уже изменился. Обновите карточку перед корректировкой');
  const locked=field==='money'?current.lockedBonus:field==='moneyRub'?current.lockedBonusRub:0;if(target<Math.round(locked*100))throw new ConflictException('Нельзя уменьшить баланс ниже зарезервированных средств');
  if(target===before)throw new BadRequestException('Новый баланс совпадает с текущим');
  await tx.wallet.update({where:{id:wallet.id},data:{[field]:target/100}});
  await tx.walletTransaction.create({data:{walletId:wallet.id,type:'TECHNICAL_BALANCE_ADJUSTMENT',direction:target>before?'CREDIT':'DEBIT',balanceSource:source,amount:Math.abs(target-before)/100,currency,note:'Корректировка технической панелью: '+body.reason,idempotencyKey:key}});
  await audit(tx,{userId,walletId:wallet.id,field,currency,before:before/100,after:target/100,delta:(target-before)/100,reason:body.reason,operationId:body.operationId});return{ok:true,before:before/100,after:target/100};
 });
}
