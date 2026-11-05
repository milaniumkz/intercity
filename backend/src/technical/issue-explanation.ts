import {humanAction} from './activity-feed';
export function explainFailure(message:any,status?:number){
 const text=String(message||'');
 const rules:Array<[RegExp,string]>=[[/ENOENT|no such file/i,'Сервер не нашёл нужный файл. Он мог быть удалён или не попасть в хранилище.'],[/ECONNREFUSED|connection refused/i,'Сервер не смог соединиться с зависимым сервисом: соединение отклонено.'],[/timeout|timed out|ETIMEDOUT/i,'Сервис не ответил за отведённое время.'],[/unique constraint|P2002/i,'Запись с таким уникальным значением уже существует.'],[/foreign key|P2003/i,'Не найдена связанная запись, необходимая для операции.'],[/column .*does not exist|P2022|relation .*does not exist/i,'Структура базы не соответствует запросу приложения. Требуется проверить применённые миграции.'],[/invalid.*(enum|argument|value)|P2009/i,'Сервер получил значение, которое не соответствует ожидаемому формату.'],[/ENOSPC|no space left/i,'На диске сервера закончилось свободное место.'],[/permission denied|EACCES/i,'Компонент сервера не получил доступ к файлу или ресурсу.'],[/invalid credentials/i,'Номер телефона или пароль не подошёл.'],[/insufficient.*balance/i,'На балансе недостаточно средств для операции.']];
 const known=rules.find(([pattern])=>pattern.test(text));if(known)return known[1];
 if(/[а-яё]/i.test(text))return text.slice(0,1000);
 if(status===401)return 'Запрос не прошёл авторизацию: сеанс мог истечь или данные входа не подошли.';
 if(status===403)return 'Запросу отказано в доступе. Проверьте права аккаунта и условия выполнения действия.';
 if(status===413)return 'Отправленный файл превышает допустимый размер.';
 if(status&&status>=500)return 'Сервер не смог завершить действие. Конкретная причина не записана в сообщении этого события.';
 return 'Подробное сообщение о причине не поступило. Для выяснения нужны связанные события и проверка сервиса.';
}
export function issueExplanation(issue:any,events:any[]){
 const relevant=events.filter(e=>e.stage==='FINISH'||e.stage==='ABORTED'),last=relevant[0]||events[0];
 return {action:last?humanAction(last.action):'Действие не определено',whatHappened:last?explainFailure(last.message,last.status):'У проблемы пока нет связанного события с описанием.',outcome:last?.status?'Сервер вернул код '+last.status: 'Итоговый HTTP-ответ не зафиксирован',confirmedCause:issue.confirmedCause||'Точная причина ещё не подтверждена',hypothesis:issue.hypothesis||null,firstAt:issue.firstAt,lastAt:issue.lastAt,count:issue.count,evidence:relevant.slice(0,10).map(e=>({id:e.id,at:e.at,title:humanAction(e.action),description:explainFailure(e.message,e.status),status:e.status,result:e.result,userId:e.userId}))};
}
