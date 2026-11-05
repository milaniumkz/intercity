import {BadRequestException} from '@nestjs/common';
import {recordPage,recordDates} from '../admin/customer-records';
export function humanAction(action:string){
 const value=String(action||'');
 const rules:Array<[RegExp,string]>=[
 [/auth\/register/,'Регистрация аккаунта'],[/auth\/login/,'Вход в аккаунт'],[/auth\/(reset-password|identity\/reset-password)/,'Восстановление пароля'],
 [/auth\/identity\/.*\/video/,'Отправка видеозаписи'],[/auth\/identity\/enroll/,'Начало первичной видеопроверки'],[/auth\/identity\/recovery/,'Начало восстановления по лицу'],[/auth\/identity\/driver-consent/,'Согласие на сверку документов'],
 [/driver\/docs\/upload/,'Загрузка документа водителя'],[/driver\/docs\/(complete|compare)/,'Отправка документов на проверку'],[/driver\/.*service-modes/,'Выбор типов заказов'],[/driver\/profile/,'Заполнение анкеты водителя'],[/driver\/online/,'Выход на линию или завершение работы'],
 [/intercity\/requests.*offers/,'Предложение цены пассажиру'],[/intercity\/requests.*accept/,'Выбор водителя'],[/intercity\/requests.*cancel/,'Отмена междугородней заявки'],[/intercity\/requests.*status/,'Изменение этапа поездки'],[/intercity\/requests/,'Междугородняя заявка'],
 [/orders.*offers.*accept/,'Выбор предложения водителя'],[/orders.*offers/,'Предложение цены'],[/orders.*cancel/,'Отмена заказа'],[/orders.*(status|complete|arriv|start)/,'Изменение этапа поездки'],[/orders/,'Заказ поездки или доставки'],
 [/wallet.*topup/,'Пополнение кошелька'],[/wallet.*payout/,'Заявка на вывод средств'],[/wallet/,'Операция с кошельком'],[/(chat|messages)/,'Сообщение в чате'],[/driver.*location/,'Обновление местоположения'],[/auth\/change-password/,'Смена пароля'],[/screen|navigation|route\.view/,'Переход на экран приложения'],[/document\.quality/,'Проверка качества документа'],[/document\.review/,'Рассмотрение документа']
 ];
 return rules.find(([pattern])=>pattern.test(value))?.[1]||'Действие в приложении';
}
export function humanFailure(raw:any){
 const text=String(raw||'');
 if(/invalid credentials|неверн.*парол/i.test(text))return 'Не удалось войти: проверьте номер телефона и пароль';
 if(/already registered/i.test(text))return 'Аккаунт с таким номером уже зарегистрирован';
 if(/insufficient.*balance/i.test(text))return 'Недостаточно денег на балансе';
 if(/account unavailable/i.test(text))return 'Доступ к аккаунту ограничен';
 if(/[а-яё]/i.test(text))return text.slice(0,400);
 return 'Операция не выполнена. Подробности доступны в служебном журнале.';
}
export async function userActivity(db:any,q:any,personal:boolean){
 const page=recordPage(q),where:any={stage:{in:['FINISH','ABORTED']},AND:[{OR:[{action:{startsWith:'POST '}},{action:{startsWith:'PATCH '}},{action:{startsWith:'DELETE '}},{action:{startsWith:'screen.'}},{action:{startsWith:'client.'}},{result:'FAILURE'}]},{NOT:{OR:['/technical','/location','/push-token','/heartbeat','/auth/refresh'].map(path=>({action:{contains:path}}))}}]};
 const dates=recordDates(q);if(dates)where.at=dates;else if(q.period!=='all')where.at={gte:new Date(Date.now()-({week:7,month:30}[String(q.period)]||1)*86400000)};
 if(q.userId)where.userId=String(q.userId);
 if(q.failures==='true')where.OR=[{result:'FAILURE'},{status:{gte:400}}];
 const search=String(q.search||'').trim();
 if(search){if(!personal)throw new BadRequestException('Нет доступа к поиску персональных данных');const digits=search.replace(/\D/g,'');const users=await db.user.findMany({where:{OR:[{name:{contains:search.slice(0,100),mode:'insensitive'}},{phone:{contains:digits.length>=4?digits.slice(-10):search}}]},select:{id:true}});where.userId={in:users.map((u:any)=>u.id)};}
 const [events,total]=await Promise.all([db.techEvent.findMany({where,...page,orderBy:[{at:'desc'},{id:'desc'}],select:{id:true,at:true,userId:true,objectId:true,action:true,result:true,status:true,message:true,client:true}}),db.techEvent.count({where})]);
 const ids=[...new Set(events.map((e:any)=>e.userId).filter(Boolean))];
 const people=personal&&ids.length?await db.user.findMany({where:{id:{in:ids}},select:{id:true,name:true,phone:true}}):[];const byId=new Map(people.map((u:any)=>[u.id,u]));
 const attempts=events.filter((e:any)=>e.action.includes('/identity/')&&e.objectId).map((e:any)=>e.objectId);const checks=attempts.length?await db.biometricChallenge.findMany({where:{id:{in:attempts}},select:{id:true,status:true,reason:true}}):[];const byAttempt=new Map(checks.map((c:any)=>[c.id,c]));
 return{items:events.map((e:any)=>{const c:any=byAttempt.get(e.objectId);const failed=c?['REJECTED','FAILED','EXPIRED'].includes(c.status):e.result==='FAILURE'||e.status>=400;return{id:e.id,at:e.at,userId:personal?e.userId:null,user:byId.get(e.userId)||null,title:humanAction(e.action),resultLabel:c?({VERIFIED:'Проверка пройдена',REJECTED:'Проверка не пройдена',REVIEW:'Нужна ручная проверка',FAILED:'Ошибка обработки',EXPIRED:'Срок проверки истёк',PROCESSING:'Проверяем запись'}[c.status]||'Проверка начата'):failed?'Не выполнено':'Выполнено',failed,reason:failed?humanFailure(c?.reason||e.message):null,platform:({android:'Android',ios:'iPhone / iPad',web:'Веб-версия'}[String(e.client?.platform).toLowerCase()]||'Не определено')};}),total,...page};
}
