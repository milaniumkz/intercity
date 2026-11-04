/** Chat events are private user events; never publish them to public trip streams. */
export function notifyTripChat(realtime: any, push: any, data: {
    kind: 'CITY' | 'INTERCITY'; tripId: string; messageId: string;
    recipientUserId: string; recipientRole: 'DRIVER' | 'PASSENGER';
}) {
    const {kind,tripId,messageId,recipientUserId,recipientRole}=data;
    if (!recipientUserId) return;
    const id=encodeURIComponent(tripId);
    const route=recipientRole==='DRIVER'
        ? `/driver/home?${kind==='INTERCITY'?'intercityRequestId':'orderId'}=${id}&chat=1`
        : `${kind==='INTERCITY'?'/intercity/request/':'/order/searching/'}${id}?chat=1`;
    const chatRoute=route+`&chatMessageId=${encodeURIComponent(messageId)}`;
    const payload={type:'chat_message',kind,orderId:tripId,messageId,route:chatRoute,
        title:'Новое сообщение',body:recipientRole==='DRIVER'?'Пассажир написал вам в чате':'Водитель написал вам в чате'};
    try {realtime?.publish?.({type:'chat.message.created',entity:'user',entityId:recipientUserId,at:new Date().toISOString(),payload});} catch (_) { /* Persisted messages remain available through polling. */ }
    void Promise.resolve().then(()=>push?.sendToUser?.(recipientUserId,{title:payload.title,body:payload.body,data:payload})).catch(()=>false);
}
