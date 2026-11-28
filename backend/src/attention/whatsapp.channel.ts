import { ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { PrismaService } from '../prisma.service';

const host = 'http://whatsapp:3000';
export async function channelRequest(path: string, body?: object) {
    const key = process.env.WHATSAPP_CHANNEL_KEY;
    if (!key) throw new ServiceUnavailableException('Канал WhatsApp ещё не настроен');
    const response = await fetch(host + path, {
        method: body ? 'POST' : 'GET',
        headers: {'X-Api-Key':key,'Content-Type':'application/json','Accept':'application/json'},
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new ServiceUnavailableException('Канал WhatsApp временно недоступен');
    const content = await response.text();
    return content.trim() ? JSON.parse(content) : null;
}

export async function channelState() {
    const sessions = await channelRequest('/api/sessions?all=true');
    if (!Array.isArray(sessions)) throw new ServiceUnavailableException('Не удалось проверить канал');
    return sessions.find(s => s.name === 'default')?.status || 'STOPPED';
}

export async function monitorWhatsapp(db: PrismaService) {
    if (!process.env.WHATSAPP_CHANNEL_KEY) return;
    const state = await channelState().catch(() => 'UNREACHABLE');
    await db.$transaction(async tx => {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(17031687)`;
        const previous = await tx.appSettings.findUnique({where:{key:'whatsapp.channel.state'}});
        const wasOnline = previous?.value === 'WORKING';
        if (state === 'WORKING') {
            await tx.adminAttention.updateMany({where:{category:'whatsapp-channel',resolvedAt:null},data:{resolvedAt:new Date()}});
        } else if (wasOnline || (previous?.value === 'UNREACHABLE' && state === 'SCAN_QR_CODE')) {
            const needsQr = state === 'SCAN_QR_CODE' || state === 'STOPPED' || state === 'FAILED';
            await tx.adminAttention.create({data:{eventKey:'whatsapp:'+randomUUID(),category:'whatsapp-channel',severity:'WARNING',
                title:needsQr?'WhatsApp требует подключения':'Канал WhatsApp недоступен',
                body:needsQr?'Откройте канал в админке и проверьте, нужен ли новый QR-код.':'Проверьте состояние серверного канала.',
                permission:'settings.manage',adminRoute:'/whatsapp',technicalRoute:'attention',sourceId:'default'}});
        }
        if (previous?.value !== state) await tx.appSettings.upsert({where:{key:'whatsapp.channel.state'},create:{key:'whatsapp.channel.state',value:state},update:{value:state}});
    });
}

export async function sendRecoveryCode(db: PrismaService, digits: string, code: string, attemptId: string, test = false) {
    try {
        await channelRequest('/api/sendText',{session:'default',chatId:digits+'@c.us',text:(test?'Тестовый код InterCity: ':'Код восстановления InterCity: ')+code+'. Никому его не сообщайте.'});
    } catch {
        await db.adminAttention.upsert({where:{eventKey:'whatsapp-send:'+attemptId},update:{},create:{
            eventKey:'whatsapp-send:'+attemptId,category:'whatsapp-send',severity:'WARNING',sourceId:attemptId,
            title:'Не отправлен код восстановления',body:'WhatsApp не подтвердил отправку кода. Проверьте канал в админке.',
            permission:'settings.manage',adminRoute:'/whatsapp',technicalRoute:'attention'}});
        throw new ServiceUnavailableException('Не удалось отправить код. Попробуйте позже или обратитесь к администратору');
    }
}
