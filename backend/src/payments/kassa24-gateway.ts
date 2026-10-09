import { BadGatewayException, ServiceUnavailableException } from '@nestjs/common';

export class Kassa24Gateway {
    constructor(private readonly options: { baseUrl: string; login: string; password: string; demo: boolean }, private readonly transport: typeof fetch = fetch) { }
    async request(path: string, body?: Record<string, unknown>) {
        if (!this.options.login || !this.options.password) throw new ServiceUnavailableException('Оплата картой пока недоступна');
        const url = new URL(path, `${this.options.baseUrl.replace(/\/+$/, '')}/`);
        if (url.protocol !== 'https:') throw new ServiceUnavailableException('Платёжный шлюз должен использовать HTTPS');
        const response = await this.transport(url, {method:body ? 'POST' : 'GET',headers:{Authorization:`Basic ${Buffer.from(`${this.options.login}:${this.options.password}`).toString('base64')}`,'Content-Type':'application/json'},body:body ? JSON.stringify(body) : undefined,signal:AbortSignal.timeout(8000)});
        const data = await response.json().catch(()=>null);
        if (!response.ok) {
            // Never include provider responses, credentials or token values in logs/errors.
            if (path==='payment/create' && [400,401,403,422].includes(response.status)) return {requestRejected:true};
            if (response.status===404) return {notFound:true};
            if (response.status===409) return {duplicate:true};
            throw new BadGatewayException(`Платёжный шлюз недоступен (${response.status})`);
        }
        if (data==null) throw new BadGatewayException('Не удалось проверить ответ платёжного шлюза');
        return data;
    }
    create(body: Record<string,unknown>) { return this.request('payment/create',{...body,merchantId:this.options.login,demo:this.options.demo}); }
    status(orderId: string) { return this.request(`payment/status?orderid=${encodeURIComponent(orderId)}`); }
    tokens(phone: string) { return this.request(`card/tokens?phone=${encodeURIComponent(phone)}`); }
    remove(id: string) { return this.request('card/tokens/remove',{id}); }
    cancel(orderId: string) { return this.request('payment/kill',{order_id:orderId}); }
}
export function confirmedPayment(status: any, orderId: string, amount: number, merchantId: string, demo: boolean) {
    return status && String(status.orderId)===orderId && String(status.merchantId)===merchantId && Number(status.amount)===Math.round(amount*100) && status.demo===demo;
}
