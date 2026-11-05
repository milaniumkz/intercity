'use strict';
const root = document.querySelector('#main'),
    nav = document.querySelector('#nav');
let account = null,
    latest = null;
const labels = {
    NEW: 'Новое',
    IN_REVIEW: 'На проверке',
    CONFIRMED: 'Подтверждено',
    NOT_CONFIRMED: 'Не подтвердилось',
    RESOLVED: 'Устранено',
    SUCCESS: 'Успешно',
    FAILURE: 'Отказ/ошибка',
    PENDING: 'На этом этапе результат ещё не определён',
    UNKNOWN: 'Результат неизвестен',
    REVIEW: 'Ручная проверка',
    REJECT: 'Отклонено',
    ACCEPT: 'Принято',
    CRITICAL: 'Критическое',
    WARNING: 'Требует внимания',
    available: 'Доступно',
    unavailable: 'Недоступно',
    unknown: 'Нет данных',
    START: 'Начало',
    PROCESSING: 'Обработка после авторизации',
    FINISH: 'Результат',
    ABORTED: 'Соединение закрыто до завершения',
};
Object.assign(labels,{selfie:'Фото водителя',passport:'Удостоверение личности',driver_license:'Водительское удостоверение',tech_passport_front:'Техпаспорт, лицевая сторона',tech_passport_back:'Техпаспорт, оборотная сторона','identity-failed':'Отказы видеопроверок','topup-completed':'Завершённые пополнения','trip-review':'Проверка поездок',identity:'Видеопроверки',driver:'Документы водителей',topup:'Пополнения',payout:'Выплаты',complaint:'Обращения',technical:'Технические проблемы',DONE:'Обработано',ALL:'Все',ERROR:'Ошибка сервера',SECURITY:'Вход и доступ',FILE:'Файл или документ',DOMAIN:'Сбой рабочего процесса',INFO:'Информационное',CONSUMED:'Использована для восстановления',CANCELLED:'Отменён',COMPLETED:'Завершён',CREATED:'Создан',OPEN:'Поиск предложений',DRIVER_ASSIGNED:'Водитель выбран',IN_PROGRESS:'В пути',PASSENGER:'Пассажир',DRIVER:'Водитель',ADMIN:'Администратор',VERIFIED:'Пройдена',REJECTED:'Отклонена',FAILED:'Ошибка обработки',EXPIRED:'Срок истёк',READY:'Ожидает записи',PROCESSING:'Обрабатывается',ENROLL:'Первичная видеопроверка',RECOVERY:'Восстановление пароля',DRIVER_IDENTITY:'Удостоверение личности',VEHICLE:'Техпаспорт автомобиля',APPROVED:'Одобрен',ACTIVE:'Активен'});
const sections = [
    ['overview', 'Главная'],
    ['data','Данные и управление'],
    ['attention','Требуют внимания'],
    ['issues', 'Проблемы и ошибки'],
    ['activity','Действия пользователей'],
    ['events', 'Журнал запросов для специалиста'],
    ['users', 'Пользователи'],
    ['identity', 'Видеопроверки и отказы'],
    ['security', 'Безопасность'],
    ['domain', 'Отклонения процессов'],
    ['files', 'Файлы и фотографии'],
    ['services', 'Сервисы и фоновые задачи'],
    ['releases', 'Резервные копии и развёртывания'],
    ['notifications', 'Уведомления'],
    ['settings', 'Настройки правил и доступа'],
];
function el(tag, text, cls) {
    const e = document.createElement(tag);
    if (text !== undefined && text !== null) e.textContent = String(text);
    if (cls) e.className = cls;
    return e;
}
function message(text) {
    document.querySelector('#notice').textContent = text || '';
}
function button(text, fn) {
    const b = el('button', text);
    b.type = 'button';
    b.addEventListener('click', async () => {
        b.disabled = true;
        try {
            await fn();
        } catch (e) {
            message(e.message);
        } finally {
            b.disabled = false;
        }
    });
    return b;
}
function link(text, route) {
    const a = el('a', text);
    a.href = '#' + route;
    return a;
}
function pretty(value) {
    return el(
        'pre',
        JSON.stringify(
            value,
            (_, v) => (typeof v === 'bigint' ? String(v) : v),
            2,
        ),
    );
}
function details(value, title = 'Технические подробности') {
    const d = el('details');
    d.append(el('summary', title), pretty(value));
    return d;
}
function date(v) {
    return v ? new Date(v).toLocaleString('ru-RU') : 'Нет данных';
}
function name(v) {
    return labels[v] || v || 'Нет данных';
}
async function api(path, body) {
    const r = await fetch('/api/technical/' + path, {
        method: body === undefined ? 'GET' : 'POST',
        credentials: 'same-origin',
        headers:
            body === undefined
                ? {}
                : { 'Content-Type': 'application/json', 'X-Tech-Request': '1' },
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    const d = await r
        .json()
        .catch(() => ({ message: 'Некорректный ответ сервера' }));
    if (!r.ok) {
        if (r.status === 401 && path !== 'login') login();
        throw new Error(
            Array.isArray(d.message)
                ? d.message.join('; ')
                : d.message || 'Ошибка ' + r.status,
        );
    }
    return d;
}
function has(p) {
    return account?.permissions.includes(p);
}
function field(form, label, type = 'text', value = '') {
    const l = el('label', label),
        i = el(type === 'textarea' ? 'textarea' : 'input');
    if (type !== 'textarea') i.type = type;
    i.value = value;
    i.setAttribute('aria-label',label);
    l.append(i);
    form.append(l);
    return i;
}
function select(form, label, values, value) {
    const l = el('label', label),
        i = el('select');
    for (const [v, t] of values) {
        const o = el('option', t);
        o.value = v;
        i.append(o);
    }
    if (value) i.value = value;
    i.setAttribute('aria-label',label);
    l.append(i);
    form.append(l);
    return i;
}
function card(title, text) {
    const d = el('section', null, 'card');
    d.append(el('h2', title));
    if (text) d.append(el('p', text));
    return d;
}
function table(cols, rows) {
    const wrap = el('div', null, 'table-wrap'),
        t = el('table'),
        head = el('tr');
    for (const [title] of cols) head.append(el('th', title));
    t.append(head);
    for (const row of rows) {
        const tr = el('tr');
        for (const [, fn] of cols) {
            const td = el('td'),
                v = fn(row);
            td.append(
                v instanceof Node
                    ? v
                    : document.createTextNode(String(v ?? '—')),
            );
            tr.append(td);
        }
        t.append(tr);
    }
    if (!rows.length) wrap.append(el('p', 'Записей нет', 'empty'));
    wrap.append(t);
    return wrap;
}
function renderFilters(q, keys, route,parent) {
    const f=el('form',null,'filters'),inputs={};
    const options={status:(['issues','security','domain'].includes(route)?['NEW','IN_REVIEW','CONFIRMED','NOT_CONFIRMED','RESOLVED']:[]),severity:['CRITICAL','WARNING','INFO'],kind:['ERROR','SECURITY','FILE','DOMAIN'],result:['SUCCESS','FAILURE','PENDING','UNKNOWN'],stage:['START','PROCESSING','FINISH','ABORTED'],verdict:['ACCEPT','REVIEW','REJECT'],role:['PASSENGER','DRIVER','ADMIN'],platform:['android','ios','web'],blocked:['true','false'],acknowledged:['true','false'],pushSent:['true','false'],category:['identity','identity-failed','trip-review','driver','topup','topup-completed','payout','complaint','technical'],state:['OPEN','DONE','ALL'],unread:['true','false'],purpose:['ENROLL','RECOVERY','DRIVER_IDENTITY','VEHICLE']};
    const extras={issues:[['kind','Тип проблемы'],['severity','Критичность'],['userId','Пользователь'],['platform','Платформа']],security:[['severity','Критичность'],['userId','Пользователь']],domain:[['severity','Критичность']],users:[['role','Роль'],['blocked','Заблокирован'],['platform','Платформа']],events:[['result','Результат'],['stage','Этап'],['platform','Платформа']],activity:[['result','Результат'],['platform','Платформа'],['userId','Пользователь']],identity:[['purpose','Тип проверки'],['userId','Пользователь']],files:[['docType','Тип документа']],notifications:[['severity','Критичность'],['acknowledged','Подтверждено'],['pushSent','Push отправлен']]};
    const entries=[...keys];for(const entry of extras[route]||[])if(!entries.some(e=>e[0]===entry[0]))entries.push(entry);
    if(!entries.some(e=>e[0]==='from'))entries.push(['from','Начиная с','datetime-local'],['to','До','datetime-local']);
    const period=select(f,'Период',[['custom','Выбранные даты / всё время'],['today','Сегодня'],['24h','Последние сутки'],['week','Последние 7 дней'],['month','Последние 30 дней']],q.get('datePreset')||'custom');
    for(const [k,title,type]of entries){
      if(k==='userId'&&has('personal')){const wrapper=el('div'),search=field(wrapper,'Найти пользователя по имени или телефону'),picker=select(wrapper,'Пользователь',[['','Все пользователи']]);f.append(wrapper);inputs[k]=picker;let timer,seq=0;const load=async()=>{const generation=++seq;try{const rows=await api('data-lookups/User?search='+encodeURIComponent(search.value));if(generation!==seq)return;picker.replaceChildren();const all=el('option','Все пользователи');all.value='';picker.append(all);for(const row of rows){const option=el('option',row.label);option.value=row.id;picker.append(option);}if(q.get(k)&&!rows.some(r=>r.id===q.get(k))){const option=el('option','Выбранный пользователь из карточки');option.value=q.get(k);picker.append(option);}picker.value=q.get(k)||'';}catch(e){message(e.message)}};search.oninput=()=>{clearTimeout(timer);timer=setTimeout(load,300)};void load();continue;}
      if(options[k]?.length){inputs[k]=select(f,title,[['','Все'],...options[k].map(v=>[v,v==='true'?'Да':v==='false'?'Нет':dmLabel(v)])],q.get(k)||'');}
      else {let value=q.get(k)||'';if(type==='datetime-local'&&value){const d=new Date(value);if(Number.isFinite(d.getTime()))value=new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16);}inputs[k]=field(f,title,type||'text',value);}
      if(['version','docType'].includes(k)){const old=inputs[k],picker=select(f,title,[['','Все']],q.get(k)||'');old.parentElement.remove();inputs[k]=picker;void api('filter-options').then(data=>{for(const value of data[k==='version'?'versions':'docTypes']){const option=el('option',dmLabel(value));option.value=value;picker.append(option);}picker.value=q.get(k)||'';}).catch(e=>message(e.message));}
    }
    period.onchange=()=>{if(period.value==='custom')return;const now=new Date(),from=new Date(now);if(period.value==='today')from.setHours(0,0,0,0);else from.setTime(now.getTime()-({week:7,month:30}[period.value]||1)*86400000);for(const [key,d]of [['from',from],['to',now]])inputs[key].value=new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16);};
    f.append(button('Применить',()=>{for(const k in inputs){const v=inputs[k].value;if(v)q.set(k,['from','to'].includes(k)?new Date(v).toISOString():v);else q.delete(k);}q.set('datePreset',period.value);q.delete('page');q.delete('skip');location.hash=route+'?'+q;}),button('Сбросить',()=>location.hash=route));
    f.onsubmit=e=>e.preventDefault();parent.append(f);
}
function renderPager(q,total,route,parent){
 const offsetBased=['identity','activity','attention'].includes(route),size=offsetBased?30:50,page=offsetBased?Math.floor(Number(q.get('skip')||0)/size)+1:Number(q.get('page')||1),p=el('div',null,'pager');
 for(const [label,next,disabled]of [['← Назад',page-1,page<=1],['Далее →',page+1,page*size>=total]]){const btn=button(label,()=>{if(offsetBased)q.set('skip',String((next-1)*size));else q.set('page',String(next));location.hash=route+'?'+q;});btn.disabled=disabled;p.append(btn);}p.append(el('span',`Страница ${page} · записей ${total}`));parent.append(p);
}

function login() {
    account = null;
    nav.replaceChildren();
    document.querySelector('#identity').textContent = '';
    document.querySelector('#logout').hidden = true;
    root.replaceChildren();
    const f = el('form', null, 'login');
    f.append(
        el('h1', 'Технический доступ'),
        el(
            'p',
            'Отдельная учётная запись. Доступ обычного администратора здесь не действует.',
            'muted',
        ),
    );
    const user = field(f, 'Логин'),
        password = field(f, 'Пароль', 'password');
    user.autocomplete = 'username';
    password.autocomplete = 'current-password';
    const submit = el('button', 'Войти');
    submit.type = 'submit';
    f.append(submit);
    f.addEventListener('submit', async (e) => {
        e.preventDefault();
        submit.disabled = true;
        try {
            await api('login', { login: user.value, password: password.value });
            password.value = '';
            await start();
        } catch (e) {
            message(e.message);
        } finally {
            submit.disabled = false;
        }
    });
    root.append(f);
}
async function start() {
    account = await api('me');
    message('');
    document.querySelector('#identity').textContent = account.login;
    document.querySelector('#logout').hidden = false;
    nav.replaceChildren();
    const advanced=el('details');advanced.className='advanced-navigation';advanced.append(el('summary','Для специалиста'));
    for (const [id, title] of sections) {
        if (
            (['users','identity'].includes(id) && !has('personal')) ||
            (id === 'settings' && !has('settings'))
        )
            continue;
        const item=link(title,id);
        if(['overview','data','attention','users','identity','activity','issues','notifications','settings'].includes(id))nav.append(item);else advanced.append(item);
    }
    nav.append(advanced);
    await render();
}
function eventColumns() {
    return [
        ['Когда', (e) => date(e.at)],
        [
            'Кто',
            (e) =>
                e.userId
                    ? link(
                          e.details?.identity?.name
                              ? e.details.identity.name +
                                    ' · ' +
                                    e.details.identity.role
                              : e.userId,
                          'users/' + e.userId,
                      )
                    : e.actorId
                      ? 'Технический сотрудник ' + e.actorId
                      : 'Не установлен',
        ],
        ['Действие', (e) => link(e.action, 'events/' + e.id)],
        ['Результат', (e) => name(e.result) + ' · ' + name(e.stage)],
        ['Сообщение', (e) => e.message || '—'],
        ['Запрос', (e) => e.requestId],
    ];
}
async function render() {
    if (!account) return;
    message('');
    const root=el('div');document.querySelector('#main').replaceChildren(root);
    const filters=(q,keys,route)=>renderFilters(q,keys,route,root);
    const pager=(q,total,route)=>renderPager(q,total,route,root);
    const raw = location.hash.slice(1) || 'overview';
    const [path, query] = raw.split('?');
    const [section, id] = path.split('/');
    const q = new URLSearchParams(query);
    root.replaceChildren(
        el(
            'h1',
            sections.find((x) => x[0] === section)?.[1] || 'Техническая панель',
        ),
    );
    for (const a of nav.querySelectorAll('a'))
        a.classList.toggle('active', a.hash === '#' + section);
    try {
        if(section==='attention'){
            filters(q,[['category','Категория'],['severity','Критичность'],['state','Состояние'],['unread','Только непрочитанные']],'attention');const d=await api('attention?'+q);root.append(el('p','Найдено: '+d.total));for(const a of d.items){const box=card(a.title,a.body);if(a.pushError)box.append(el('p',a.pushError,'human-reason'));box.append(el('p',date(a.createdAt)+' · '+name(a.severity)+' · '+(a.resolvedAt?'Обработано':'Требует внимания')),link('Открыть',a.technicalRoute),button(a.read?'Прочитано':'Отметить прочитанным',async()=>{await api('attention/'+a.id+'/read',{});await render();}));root.append(box);}pager(q,d.total,'attention');return;
        }
        if(section==='data'){await dmPanel(id,q,root);return;}
        if (['overview', 'services', 'releases'].includes(section)) {
            const d = (latest = await api('overview'));
            if(section==='overview'){
                root.append(el('p','Найдите человека, посмотрите его проверки и действия. Служебные запросы находятся в разделе «Для специалиста».','muted'));
                const shortcuts=el('div',null,'quick-grid');
                for(const [title,text,target]of [['Пользователи','Найти по имени или телефону, открыть данные и действия','users'],['Видеопроверки','Посмотреть записи и понятные причины отказов','identity'],['Действия пользователей','Что сделал человек и чем закончилось действие','activity'],['Ошибки','Что требует внимания администратора','issues']]){const a=link('',target);a.className='quick-link';a.append(el('strong',title),el('span',text));shortcuts.append(a);}root.append(shortcuts);
            }
            root.append(el('p', 'Проверено: ' + date(d.checkedAt), 'muted'));
            if (section === 'releases') {
                root.append(
                    el(
                        'p',
                        'Только отчёты, записанные скриптами обслуживания. Если отчёта нет, результат неизвестен.',
                    ),
                );
                root.append(
                    table(
                        [
                            ['Тип', (x) => x.kind],
                            ['Результат', (x) => x.status],
                            ['Когда', (x) => date(x.at)],
                            ['Версия', (x) => x.version],
                            ['Сведения', (x) => details(x.details)],
                        ],
                        d.reports,
                    ),
                );
                return;
            }
            const grid = el('div', null, 'grid');
            for (const [title, value] of [
                ['API', d.api],
                ['База данных', d.database],
                ['Закрытое хранилище', d.storage],
                ['Приложение', d.application],
            ]) {
                const c = card(title, name(value.status));
                c.append(
                    el(
                        'small',
                        value.reason ||
                            'Последняя успешная проверка: ' +
                                date(value.lastSuccessAt),
                    ),
                );
                grid.append(c);
            }
            root.append(grid);
            if (d.counts)
                root.append(
                    table(
                        [
                            [
                                'За последние 24 часа / текущее состояние',
                                (x) => link(x[0],x[0].includes('видеопроверки')?'identity':x[0].includes('ошибки')?'events?statusMin=500':'issues'),
                            ],
                            ['Количество', (x) => x[1]],
                        ],
                        Object.entries(d.counts).map(([k, v]) => [
                            {
                                failedIdentity:'Неудачные видеопроверки за 24 часа',
                                errors: 'Серверные ошибки за 24 часа',
                                affectedUsers:
                                    'Пользователи с отказами за 24 часа',
                                newIssues: 'Новые проблемы',
                                fileProblems: 'Файлы, требующие внимания',
                            }[k],
                            v,
                        ]),
                    ),
                );
            root.append(
                card(
                    'Сбор событий',
                    `Последний успех: ${date(d.collector.lastSuccessAt)}. Сбоев в текущем процессе: ${d.collector.failures}`,
                ),
                details(d.resources, 'Ресурсы процесса и контейнера'),
                details(d.storage, 'Свободное место'),
                details(d.jobs, 'Фоновые задачи и Web Push'),
                card('Установленная версия', d.version),
            );
            if (!d.reports.length)
                root.append(
                    card(
                        'Резервное копирование и развёртывания',
                        'Отчёты ещё не поступали. Дата и результат неизвестны.',
                    ),
                );
            else root.append(link('Открыть отчёты', 'releases'));
            return;
        }
        if (section === 'events' && !id) {
            filters(
                q,
                [
                    ['from', 'С', 'datetime-local'],
                    ['to', 'По', 'datetime-local'],
                    ['userId', 'ID пользователя'],
                    ['sessionId', 'ID сеанса'],
                    ['requestId', 'ID запроса'],
                    ['objectId', 'ID объекта'],
                    ['result', 'Результат'],
                    ['version', 'Версия'],
                    ['search', 'Действие'],
                ],
                'events',
            );
            const d = await api('events?' + q);
            root.append(
                el('p', d.gaps, 'muted'),
                details(d.scope, 'Область показанной истории'),
                table(eventColumns(), d.items),
            );
            pager(q, d.total, 'events');
            return;
        }
        if (section === 'events' && id) {
            const d = await api('events/' + id),
                e = d.event;
            root.append(
                card(
                    e.action,
                    `${date(e.at)} · ${name(e.result)} · ${e.message || 'Без сообщения'}`,
                ),
            );
            const actions = el('div', null, 'actions');
            if (e.userId) {
                actions.append(
                    link('Карточка пользователя', 'users/' + e.userId),
                    link(
                        'Порядок действий пользователя',
                        'events?userId=' + e.userId + '&order=asc',
                    ),
                );
                if (e.sessionId)
                    actions.append(
                        link(
                            'История пользователя в этом сеансе',
                            'events?userId=' +
                                e.userId +
                                '&sessionId=' +
                                e.sessionId +
                                '&order=asc',
                        ),
                    );
            }
            actions.append(
                link(
                    'Все стадии этого запроса',
                    'events?requestId=' + e.requestId + '&order=asc',
                ),
            );
            if (e.objectId)
                actions.append(
                    link(
                        'События объекта (все участники)',
                        'events?objectId=' + e.objectId,
                    ),
                );
            if (e.issueId)
                actions.append(
                    link('Связанная проблема', 'issues/' + e.issueId),
                );
            root.append(
                actions,
                details(e),
                fileList('Файлы именно этого действия', d.actionFiles),
                fileList(
                    'Остальные материалы объекта (другие действия и авторы)',
                    d.otherObjectFiles,
                ),
            );
            return;
        }
        if (['issues', 'security', 'domain'].includes(section) && !id) {
            if (section === 'security') q.set('kind', 'SECURITY');
            if (section === 'domain') q.set('kind', 'DOMAIN');
            filters(
                q,
                [
                    ['status', 'Статус'],
                    ['search', 'Описание'],
                ],
                section,
            );
            const d = await api('issues?' + q);
            root.append(
                el(
                    'p',
                    'Срабатывание правила — повод проверить факты, а не доказательство нарушения.',
                    'muted',
                ),
                table(
                    [
                        ['Проблема', (x) => link(x.title, 'issues/' + x.id)],
                        ['Статус', (x) => name(x.status)],
                        ['Важность', (x) => name(x.severity)],
                        ['Повторения', (x) => x.count],
                        ['Впервые', (x) => date(x.firstAt)],
                        ['Последний раз', (x) => date(x.lastAt)],
                    ],
                    d.items,
                ),
            );
            pager(q, d.total, section);
            return;
        }
        if (section === 'issues' && id) {
            const d = await api('issues/' + id),
                i = d.issue;
            const why=d.explanation;
            if(why){root.append(card('Что произошло',why.whatHappened),card('Что делал пользователь',why.action+' · '+why.outcome),card('Подтверждённая причина',why.confirmedCause));if(why.hypothesis)root.append(card('Предположение, требует проверки',why.hypothesis));for(const e of why.evidence){const evidence=card(date(e.at)+' · '+e.title,e.description);evidence.append(link('Открыть событие','events/'+e.id));if(e.userId)evidence.append(link('Пользователь','users/'+e.userId));root.append(evidence);}}
            root.append(
                card(
                    i.title,
                    `${name(i.severity)} · ${name(i.status)} · повторений: ${i.count}`,
                ),
                el('p', d.recommendation),
                details(i, 'Сведения о проблеме и проверке'),
            );
            for (const u of d.affectedUsers)
                root.append(
                    link(
                        'Порядок действий пользователя ' + u,
                        'events?userId=' + u + '&order=asc',
                    ),
                    el('br'),
                );
            root.append(table(eventColumns(), d.events));
            const f = el('form');
            const status = select(
                    f,
                    'Статус',
                    [
                        'NEW',
                        'IN_REVIEW',
                        'CONFIRMED',
                        'NOT_CONFIRMED',
                        'RESOLVED',
                    ].map((v) => [v, name(v)]),
                    i.status,
                ),
                assigned = field(
                    f,
                    'ID ответственного',
                    'text',
                    i.assignedTo || '',
                ),
                cause = field(
                    f,
                    'Подтверждённая причина',
                    'textarea',
                    i.confirmedCause || '',
                ),
                hypothesis = field(
                    f,
                    'Предположение',
                    'textarea',
                    i.hypothesis || '',
                ),
                verification = field(
                    f,
                    'Результат проверки',
                    'textarea',
                    i.verification || '',
                ),
                version = field(
                    f,
                    'Исправляющая версия',
                    'text',
                    i.fixedVersion || '',
                ),
                comment = field(f, 'Комментарий', 'textarea'),
                muted = field(
                    f,
                    'Приглушить на минуты (критические события не приглушаются)',
                    'number',
                    '0',
                );
            f.append(
                button('Сохранить проверку', async () => {
                    await api('issues/' + id, {
                        status: status.value,
                        assignedTo: assigned.value,
                        confirmedCause: cause.value,
                        hypothesis: hypothesis.value,
                        verification: verification.value,
                        fixedVersion: version.value,
                        comment: comment.value,
                        mutedMinutes: Number(muted.value),
                    });
                    await render();
                }),
            );
            root.append(
                f,
                el('h2', 'Комментарии'),
                ...d.comments.map((c) =>
                    card(date(c.createdAt) + ' · ' + c.actorId, c.text),
                ),
            );
            return;
        }
        if(section==='activity'){
            filters(q,[['search','Имя или телефон']],'activity');
            const period=select(root,'Период',[['24h','Последние сутки'],['week','Последние 7 дней'],['month','Последние 30 дней'],['all','Вся доступная история']],q.get('period')||'24h');
            period.addEventListener('change',()=>{q.set('period',period.value);q.delete('skip');location.hash='activity?'+q});
            const d=await api('activity?'+q);root.append(el('p','Найдено действий: '+d.total,'muted'));
            if(q.has('userId'))root.append(link('Показать всех пользователей','activity'));
            for(const row of d.items){const box=card(row.title);box.classList.add('activity-card');const badge=el('span',row.resultLabel,row.failed?'badge danger':'badge success');box.append(badge,el('p',date(row.at)+' · '+row.platform));
                if(row.user)box.append(link(row.user.name+' · '+row.user.phone,'users/'+row.user.id));else box.append(el('p','Пользователь не установлен или персональные данные недоступны','muted'));
                if(row.reason)box.append(el('p',row.reason,'human-reason'));
                const technical=el('details');technical.append(el('summary','Служебные подробности'),link('Открыть запись журнала','events/'+row.id));box.append(technical);root.append(box);
            }
            if(!d.items.length)root.append(el('p','За выбранный период действий не найдено. Попробуйте другой период или уберите поиск.'));
            root.append(el('p','Показываются действия, которые приложение передало на сервер. Работа без соединения может не отобразиться.','muted'));pager(q,d.total,'activity');return;
        }
        if(section==='identity'){
            filters(q,[['search','Имя или телефон']],'identity');
            const status=select(root,'Показать',[['FAILURES','Неудачные попытки'],['ALL','Все попытки'],['REVIEW','Нужна ручная проверка'],['VERIFIED','Пройденные'],['FAILED','Ошибки обработки'],['REJECTED','Не пройдены'],['EXPIRED','Срок истёк'],['CONSUMED','Использованы для сброса']],q.get('status')||'ALL');
            status.addEventListener('change',()=>{q.set('status',status.value);q.delete('skip');location.hash='identity?'+q});
            if(!q.has('status'))q.set('status','ALL');
            const d=await api('identity-attempts?'+q);
            root.append(el('p','Новые неудачные записи хранятся зашифрованными до 7 дней. Старые отказные видео могли не сохраняться. Просмотр материалов фиксируется в журнале.','muted'));
            for(const row of d.items){
                const box=card((row.user?.name||'Аккаунт не определён')+' · '+(row.user?.phone||''));
                box.append(el('p',name(row.purpose)+' · '+name(row.status)+' · '+date(row.createdAt)),el('p',row.reason||'Ошибки не зафиксированы'));
                if(row.userId)box.append(link('Открыть пользователя','users/'+row.userId));
                if(row.hasVideo&&has('originals'))box.append(button('Посмотреть видео',()=>showIdentityVideo(row.id)));
                else box.append(el('p',row.hasVideo?'Видео сохранено, но у этого технического аккаунта нет разрешения на просмотр оригиналов':row.videoMessage||'Видео для этой попытки не сохранялось','muted'));
                root.append(box);
            }
            if(!d.items.length)root.append(el('p','Проверок по выбранным условиям нет.'));
            pager(q,d.total,'identity');return;
        }
        if (section === 'users' && !id) {
            filters(q, [['search', 'Имя, телефон или ID']], 'users');
            const d = await api('users?' + q);
            root.append(
                table(
                    [
                        ['Пользователь', (x) => link(x.name, 'users/' + x.id)],
                        ['Телефон', (x) => x.phone],
                        ['Роль', (x) => name(x.role)],
                        ['Город', (x) => x.city?.name],
                        [
                            'Состояние',
                            (x) =>
                                x.blockedAt
                                    ? 'Заблокирован'
                                    : x.mustChangePassword
                                      ? 'Нужна смена пароля'
                                      : 'Доступен',
                        ],
                    ],
                    d.items,
                ),
            );
            pager(q, d.total, 'users');
            return;
        }
        if (section === 'users' && id) {
            const d = await api('users/' + id);
            root.append(
                card(d.user.name, d.user.phone + ' · ' + name(d.user.role)),
                details(d.user, 'Служебные сведения об аккаунте'),
                link('Видеопроверки пользователя','identity?userId='+id+'&status=ALL'),
                link(
                    'Порядок действий пользователя',
                    'activity?userId=' + id + '&period=all',
                ),
                el(
                    'p',
                    `Записей обновления токенов: ${d.sessions}. ${d.sessionLimitation}`,
                ),
                link('Все действия этого пользователя','activity?userId='+id+'&period=all'),
            );
            const profile=card('Сведения о пользователе');profile.append(el('p','Город: '+(d.user.city?.name||'Не указан')),el('p','Зарегистрирован: '+date(d.user.createdAt)),el('p','Состояние: '+(d.user.blockedAt?'Заблокирован':'Доступен')));root.append(profile);
            try{const trips=await api('users/'+id+'/trips?take=30');const box=card('Заказы и поездки: '+trips.total);box.append(table([['Дата',x=>date(x.createdAt)],['Откуда',x=>x.origin],['Куда',x=>x.destination],['Состояние',x=>name(x.status)],['Стоимость',x=>x.price+' '+(x.currency==='RUB'?'₽':'₸')]],trips.items));if(!trips.items.length)box.append(el('p','Заказов пока нет.'));root.append(box);}catch(e){root.append(el('p','Не удалось загрузить историю заказов: '+e.message));}
            if(has('users'))await dmWallet(id,root);
            root.append(link('Все данные пользователя и фильтры','data/User?record='+id));
            if (d.user.driverProfile) {
                const docs = card(
                    'Текущие документы профиля: не файлы выбранного события',
                    'Для старых файлов автор и время загрузки не установлены.',
                );
                for (const type of [
                    'selfieUrl',
                    'passportUrl',
                    'driverLicenseUrl',
                    'techPassportFrontUrl',
                    'techPassportBackUrl',
                ]) {
                    const url = d.user.driverProfile[type];
                    if (!url) continue;
                    if (url.startsWith('/api/driver/docs/files/'))
                        docs.append(
                            link(({selfieUrl:'Фото водителя',passportUrl:'Удостоверение личности',driverLicenseUrl:'Водительское удостоверение',techPassportFrontUrl:'Техпаспорт — лицевая сторона',techPassportBackUrl:'Техпаспорт — оборотная сторона'})[type], 'files/' + url.split('/').pop()),
                            el('br'),
                        );
                    else if (has('originals'))
                        docs.append(
                            button('Открыть ' + ({selfieUrl:'фото водителя',passportUrl:'удостоверение личности',driverLicenseUrl:'водительское удостоверение',techPassportFrontUrl:'техпаспорт — лицевая сторона',techPassportBackUrl:'техпаспорт — оборотная сторона'})[type], () =>
                                showOriginal(
                                    null,
                                    '/api/technical/users/' +
                                        id +
                                        '/documents/' +
                                        type,
                                ),
                            ),
                        );
                }
                root.append(docs);
            }
            if (has('users') && has('danger')) {
                const f = el('form');
                f.append(el('h2', 'Действия с аккаунтом'));
                const op = select(f, 'Что сделать', [
                        ['revoke-sessions', 'Выйти из аккаунта на всех устройствах'],
                        ['edit-profile','Изменить имя и телефон'],
                    ['delete-account','Удалить аккаунт'],
                    ['block', 'Заблокировать'],
                        ['unblock', 'Разблокировать'],
                        ['temporary-password', 'Установить временный пароль'],
                    ]),
                    reason = field(f, 'Причина', 'textarea'),
                    temp = field(
                        f,
                        'Новый временный пароль (только для установки)',
                        'password',
                    ),
                    pw = field(
                        f,
                        'Ваш технический пароль для подтверждения',
                        'password',
                    ),
                    check = field(
                        f,
                        'Подтверждаю выполнение операции',
                        'checkbox',
                    );
                const editName=field(f,'Имя пользователя','text',d.user.name),editPhone=field(f,'Телефон пользователя','tel',d.user.phone);
                const updateFields=()=>{temp.parentElement.hidden=op.value!=='temporary-password';editName.parentElement.hidden=editPhone.parentElement.hidden=op.value!=='edit-profile';};
                op.addEventListener('change',updateFields);updateFields();
                f.append(el('p','Удаление очищает персональные данные и файлы. Активные поездки и незавершённые выплаты нужно сначала урегулировать.','muted'));
                f.append(
                    button('Выполнить', async () => {
                        await api('users/' + id + '/' + op.value, {
                            reason: reason.value,
                            confirm: check.checked,
                            password: pw.value,
                            temporaryPassword: temp.value,
                            ...(op.value==='edit-profile'?{fields:{name:editName.value,phone:editPhone.value}}:{}),
                        });
                        pw.value = '';
                        temp.value = '';
                        if(op.value==='delete-account')location.hash='users';else await render();
                        message(
                            op.value==='delete-account'?'Аккаунт удалён. Персональные файлы очищаются автоматически.':'Изменения сохранены.',
                        );
                    }),
                );
                root.append(f);
            }
            return;
        }
        if (section === 'files' && !id) {
            filters(
                q,
                [
                    ['userId', 'ID автора'],
                    ['objectId', 'ID объекта'],
                    ['requestId', 'ID действия'],
                    ['verdict', 'Результат проверки'],
                ],
                'files',
            );
            const d = await api('files?' + q);
            root.append(
                el('p', d.history, 'muted'),
                table(
                    [
                        ['Документ', (x) => link(x.docType, 'files/' + x.id)],
                        ['Автор', (x) => link(x.userId, 'users/' + x.userId)],
                        ['Когда', (x) => date(x.createdAt)],
                        ['Проверка', (x) => name(x.verdict)],
                        ['Причина', (x) => x.reason],
                        [
                            'Оригинал',
                            (x) =>
                                x.deletedAt
                                    ? 'Удалён по сроку хранения'
                                    : 'Учтён в хранилище',
                        ],
                    ],
                    d.items,
                ),
            );
            pager(q, d.total, 'files');
            return;
        }
        if (section === 'files' && id) {
            const f = await api('files/' + id);
            root.append(
                card(f.docType, `${name(f.verdict)} · ${f.reason}`),
                details(f, 'Формат, размер, SHA-256, алгоритм и связи'),
                link('События загрузки', 'events?requestId=' + f.requestId),
            );
            if (f.deletedAt)
                root.append(el('p', 'Оригинал удалён по сроку хранения'));
            else if (has('originals')) {
                const image = el('img');
                image.src = '/api/technical/files/' + id + '/original';
                image.alt = 'Оригинал документа целиком';
                image.className = 'document';
                image.addEventListener('error', () =>
                    message(
                        'Оригинал не удалось загрузить. Проверьте доступ и хранилище.',
                    ),
                );
                root.append(
                    image,
                    button('Оригинал и увеличение', () => showOriginal(id)),
                );
            } else
                root.append(
                    el(
                        'p',
                        'Для просмотра оригинала требуется отдельное разрешение',
                    ),
                );
            return;
        }
        if (section === 'notifications') {
            filters(q,[],'notifications');
            const d = await api('notifications?' + q);
            root.append(
                button('Включить браузерные уведомления', () =>
                    enablePush(d.vapidPublicKey),
                ),
                el(
                    'p',
                    'При разрешении браузера Service Worker принимает push и после закрытия вкладки. Работа зависит от браузера, ОС и сети; внутренний центр сохраняет уведомления независимо от push.',
                    'muted',
                ),
                table(
                    [
                        ['Когда', (n) => date(n.createdAt)],
                        ['Важность', (n) => name(n.severity)],
                        [
                            'Проблема',
                            (n) =>
                                link('Открыть проблему', 'issues/' + n.issueId),
                        ],
                        [
                            'Получение',
                            (n) =>
                                n.acknowledgedAt
                                    ? date(n.acknowledgedAt)
                                    : button('Подтвердить', async () => {
                                          await api(
                                              'notifications/' + n.id + '/ack',
                                              {},
                                          );
                                          await render();
                                      }),
                        ],
                        [
                            'Push',
                            (n) =>
                                n.pushAt
                                    ? 'Отправлен push-провайдеру'
                                    : `Не отправлен; попыток ${n.attempts}`,
                        ],
                    ],
                    d.items,
                ),
            );
            pager(q, d.total, 'notifications');
            return;
        }
        if (section === 'settings') {
            const d = await api('settings');
            const own = el('form');
            own.append(el('h2', 'Сменить свой технический пароль'));
            const current = field(own, 'Текущий пароль', 'password'),
                replacement = field(
                    own,
                    'Новый пароль (от 14 символов)',
                    'password',
                );
            own.append(
                button('Сменить пароль и выйти', async () => {
                    await api('me/password', {
                        currentPassword: current.value,
                        newPassword: replacement.value,
                    });
                    current.value = '';
                    replacement.value = '';
                    login();
                    message('Пароль изменён. Войдите с новым паролем.');
                }),
            );
            root.append(own);
            root.append(
                button('Показать аудит технических действий', async () => {
                    const audit = await api('audit');
                    root.append(
                        table(
                            [
                                ['Когда', (x) => date(x.at)],
                                ['Сотрудник', (x) => x.actorId],
                                ['Действие', (x) => x.action],
                                ['Объект', (x) => x.objectId],
                                ['Сведения', (x) => details(x.data)],
                            ],
                            audit.items,
                        ),
                    );
                }),
            );
            root.append(
                details(d.accounts, 'Технические учётные записи'),
                button('Проверить цепочку аудита', async () => {
                    const result = await api('audit/verify', {});
                    root.append(pretty(result));
                }),
            );
            for (const [key, def] of Object.entries(d.defaults)) {
                const f = el('form');
                f.append(
                    el(
                        'h2',
                        {
                            image: 'Качество изображений',
                            retention: 'Сроки хранения',
                            security: 'Правило повторных отказов',
                        }[key],
                    ),
                );
                const value = field(
                        f,
                        'Правило в JSON',
                        'textarea',
                        JSON.stringify(
                            d.rules.find((r) => r.key === key)?.value || def,
                            null,
                            2,
                        ),
                    ),
                    pw = field(f, 'Ваш технический пароль', 'password');
                f.append(
                    button('Сохранить правило', async () => {
                        await api('settings/rules/' + key, {
                            value: JSON.parse(value.value),
                            password: pw.value,
                        });
                        pw.value = '';
                        message('Правило сохранено.');
                    }),
                );
                root.append(f);
            }
            if (has('danger')) {
                const f = el('form');
                f.append(el('h2', 'Создать / изменить технический доступ'));
                const id = field(f, 'ID записи (пусто для новой)'),
                    login = field(f, 'Логин'),
                    permissions = field(
                        f,
                        'Разрешения через запятую',
                        'text',
                        'events',
                    ),
                    newpw = field(
                        f,
                        'Новый пароль (14–72 символа)',
                        'password',
                    ),
                    disabled = field(f, 'Отключена', 'checkbox'),
                    pw = field(f, 'Ваш технический пароль', 'password');
                f.append(
                    el(
                        'p',
                        'Разрешения: events, personal, originals, users, danger, settings',
                    ),
                    button('Сохранить доступ', async () => {
                        await api('settings/accounts', {
                            id: id.value || undefined,
                            login: login.value,
                            permissions: permissions.value
                                .split(',')
                                .map((x) => x.trim())
                                .filter(Boolean),
                            newPassword: newpw.value || undefined,
                            disabled: disabled.checked,
                            password: pw.value,
                        });
                        newpw.value = '';
                        pw.value = '';
                        await render();
                    }),
                );
                root.append(f);
            }
            return;
        }
        root.append(el('p', 'Раздел не найден'));
    } catch (e) {
        if(root.isConnected)message(e.message);
    }
}
function fileList(title, files) {
    const c = card(title);
    if (!files.length) c.append(el('p', 'Связанных файлов не записано'));
    for (const f of files)
        c.append(
            link(
                `${f.docType} · ${date(f.createdAt)} · автор ${f.userId}`,
                'files/' + f.id,
            ),
            el('br'),
        );
    return c;
}
async function showOriginal(id, path) {
    const r = await fetch(path || '/api/technical/files/' + id + '/original', {
        credentials: 'same-origin',
    });
    if (!r.ok) {
        const d = await r.json();
        throw new Error(d.message || 'Оригинал недоступен');
    }
    const url = URL.createObjectURL(await r.blob()),
        image = el('img');
    image.src = url;
    image.alt = 'Оригинал документа целиком';
    image.className = 'document';
    const modal = document.querySelector('#modal'),
        content = document.querySelector('#modal-content');
    content.replaceChildren(
        button('Масштаб 1:1 / по ширине', () => image.classList.toggle('zoom')),
        image,
    );
    modal.addEventListener('close', () => URL.revokeObjectURL(url), {
        once: true,
    });
    modal.showModal();
}
async function enablePush(key) {
    if (!key) throw new Error('Серверные VAPID-ключи не настроены');
    if (!('serviceWorker' in navigator) || !('PushManager' in window))
        throw new Error('Браузер не поддерживает Web Push');
    if ((await Notification.requestPermission()) !== 'granted')
        throw new Error('Разрешение на уведомления не предоставлено');
    const reg = await navigator.serviceWorker.register(
        '/api/technical/panel/sw.js',
        { scope: '/api/technical/' },
    );
    await navigator.serviceWorker.ready;
    const base64 = (key + '='.repeat((4 - (key.length % 4)) % 4))
            .replace(/-/g, '+')
            .replace(/_/g, '/'),
        bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    const sub =
        (await reg.pushManager.getSubscription()) ||
        (await reg.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: bytes,
        }));
    await api('push', sub.toJSON());
    message('Подписка на браузерные уведомления сохранена.');
}
document.querySelector('#logout').addEventListener('click', async () => {
    try {
        await api('logout', {});
        login();
    } catch (e) {
        message(e.message);
    }
});
document
    .querySelector('#close-modal')
    .addEventListener('click', () => document.querySelector('#modal').close());
window.addEventListener('hashchange', () => void render());
setInterval(() => {
    if (
        account &&
        ['overview', 'services'].includes(location.hash.slice(1) || 'overview')
    )
        void render();
}, 30000);
start().catch(() => login());

async function showIdentityVideo(id){
 const response=await fetch('/api/technical/identity-attempts/'+encodeURIComponent(id)+'/video',{credentials:'same-origin'});
 if(!response.ok)throw new Error('Запись недоступна: нет права просмотра, файл отсутствует или истёк срок хранения.');
 const url=URL.createObjectURL(await response.blob()),video=el('video');video.controls=true;video.playsInline=true;video.preload='auto';video.src=url;video.style.width='100%';video.style.maxHeight='70vh';
 const modal=document.querySelector('#modal'),status=el('p','Загружаем видеозапись…');status.setAttribute('role','status');video.addEventListener('loadeddata',()=>status.textContent='Видео загружено. Нажмите воспроизведение.');video.addEventListener('error',()=>status.textContent='Браузер не смог воспроизвести эту запись. Попробуйте актуальный Chrome или Safari.');document.querySelector('#modal-content').replaceChildren(el('h2','Запись видеопроверки'),status,video);modal.addEventListener('close',()=>{video.pause();video.removeAttribute('src');video.load();URL.revokeObjectURL(url)},{once:true});modal.showModal();
}

let attentionLast;
setInterval(async()=>{if(!account)return;try{const d=await api('attention?unread=true&take=1');let indicator=document.querySelector('#attention-indicator');if(!indicator){indicator=link('','attention');indicator.id='attention-indicator';document.querySelector('header').append(indicator);}indicator.textContent='Требуют внимания: '+d.total;if(attentionLast&&d.items[0]?.id&&d.items[0].id!==attentionLast)message('Новое уведомление: '+d.items[0].title);attentionLast=d.items[0]?.id;}catch(_){}},5000);
