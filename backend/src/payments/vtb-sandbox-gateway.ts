import { BadGatewayException, ServiceUnavailableException } from '@nestjs/common';

export const VTB_SANDBOX_REST_URL = 'https://vtbkz.rbsuat.com/payment/rest/';
export type VtbSandboxOptions = { userName: string; password: string };

export class VtbSandboxApiError extends BadGatewayException {
    constructor(readonly code: string) { super('ВТБ отклонил тестовую операцию (код ' + code + ')'); }
}

export class VtbSandboxGateway {
    constructor(private readonly options: VtbSandboxOptions, private readonly transport: typeof fetch = fetch) {}

    get configured() { return !!this.options.userName && !!this.options.password; }

    private async request(method: 'register.do' | 'getOrderStatusExtended.do' | 'refund.do' | 'reverse.do' | 'decline.do' | 'getBindings.do' | 'unBindCard.do' | 'paymentOrderBinding.do', values: Record<string, string>, acceptDuplicate = false) {
        if (!this.configured) throw new ServiceUnavailableException('Тестовая оплата ВТБ ещё не настроена');
        const body = new URLSearchParams({ ...values, userName: this.options.userName, password: this.options.password });
        let response: Response;
        try {
            response = await this.transport(new URL(method, VTB_SANDBOX_REST_URL), {
                method: 'POST', redirect: 'error',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
                body: body.toString(), signal: AbortSignal.timeout(15000),
            });
        } catch {
            throw new BadGatewayException('Нет ответа от тестового шлюза ВТБ. Проверьте статус операции перед повторной оплатой.');
        }
        if (!response.ok) throw new BadGatewayException('Тестовый шлюз ВТБ временно недоступен');
        let data: Record<string, any>;
        try {
            data = await response.json();
            if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error();
        } catch {
            throw new BadGatewayException('Некорректный ответ тестового шлюза ВТБ');
        }
        if ((('success' in data && data.success !== true) || ('errorCode' in data && String(data.errorCode) !== '0')) &&
            !(acceptDuplicate && method === 'register.do' && String(data.errorCode) === '1')) {
            const code = /^\d{1,3}$/.test(String(data.errorCode)) ? String(data.errorCode) : 'unknown';
            // Do not expose provider messages, request bodies or credentials.
            throw new VtbSandboxApiError(code);
        }
        return data;
    }

    async register(input: { orderNumber: string; amountMinor: number; returnUrl: string; clientId?: string; bindingId?: string; forceBinding?: boolean; callbackUrl?: string; acceptDuplicate?: boolean }) {
        if (!/^[A-Za-z0-9_-]{1,36}$/.test(input.orderNumber) ||
            !Number.isSafeInteger(input.amountMinor) || input.amountMinor < 100 || input.amountMinor > 1000000000) {
            throw new Error('Invalid sandbox payment parameters');
        }
        const returnUrl = new URL(input.returnUrl);
        if (returnUrl.protocol !== 'https:' || returnUrl.username || returnUrl.password) throw new Error('HTTPS return URL required');
        let data = await this.request('register.do', {
            orderNumber: input.orderNumber, amount: String(input.amountMinor),
            currency: '398', language: 'ru', returnUrl: returnUrl.toString(),
            description: 'InterCity: sandbox payment',
            sessionTimeoutSecs: '1200',
            ...(input.clientId ? { clientId: input.clientId } : {}),
            ...(input.bindingId ? { bindingId: input.bindingId } : {}),
            ...(input.forceBinding ? { features: 'FORCE_CREATE_BINDING' } : {}),
            ...(input.callbackUrl ? { dynamicCallbackUrl: input.callbackUrl } : {}),
        }, input.acceptDuplicate === true);
        if (input.acceptDuplicate && String(data.errorCode) === '1') {
            const existing = await this.statusByOrderNumber(input.orderNumber);
            const id = existing.attributes?.find((a: any) => a.name === 'mdOrder')?.value;
            if (existing.orderNumber !== input.orderNumber || existing.amount !== input.amountMinor || String(existing.currency) !== '398' || !/^[a-f0-9-]{36}$/i.test(id || '')) throw new BadGatewayException('Не удалось восстановить проверенную операцию ВТБ');
            // The current sandbox merchant uses this bank-hosted default form.
            const url = new URL('https://vtbkz.rbsuat.com/payment/merchants/ecom/payment.html');
            url.searchParams.set('mdOrder', id); url.searchParams.set('language', 'ru');
            data = { orderId: id, formUrl: url.toString() };
        }
        if (typeof data.orderId !== 'string' || !/^[a-f0-9-]{36}$/i.test(data.orderId) || typeof data.formUrl !== 'string') {
            throw new BadGatewayException('ВТБ не вернул реквизиты тестовой оплаты');
        }
        let formUrl: URL;
        try { formUrl = new URL(data.formUrl); } catch { throw new BadGatewayException('Некорректная ссылка тестовой оплаты ВТБ'); }
        if (formUrl.origin !== 'https://vtbkz.rbsuat.com' || !formUrl.pathname.startsWith('/payment/') || formUrl.username || formUrl.password) {
            throw new BadGatewayException('Недопустимый адрес тестовой оплаты ВТБ');
        }
        return { orderId: data.orderId as string, paymentUrl: formUrl.toString() };
    }

    bindings(clientId: string) { return this.request('getBindings.do', { clientId, language: 'ru' }); }
    unbind(bindingId: string) { return this.request('unBindCard.do', { bindingId }); }
    payBinding(orderId: string, bindingId: string) {
        return this.request('paymentOrderBinding.do', { mdOrder: orderId, bindingId, tii: 'U', language: 'ru' });
    }
    refund(orderId: string, amountMinor: number, refundId: string) {
        if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0 || !/^[a-f0-9-]{36}$/i.test(refundId)) throw new Error('Invalid refund');
        return this.request('refund.do', { orderId, amount: String(amountMinor), currency: '398', externalRefundId: refundId, language: 'ru' });
    }
    reverse(orderId: string) { return this.request('reverse.do', { orderId, language: 'ru' }); }
    decline(orderId: string, orderNumber: string) { return this.request('decline.do', { orderId, orderNumber, language: 'ru' }); }

    statusByOrderNumber(orderNumber: string) {
        if (!/^[A-Za-z0-9_-]{1,36}$/.test(orderNumber)) throw new Error('Invalid merchant order identifier');
        return this.request('getOrderStatusExtended.do', { orderNumber, language: 'ru' });
    }

    status(orderId: string) {
        if (!/^[a-f0-9-]{36}$/i.test(orderId)) throw new Error('Invalid bank order identifier');
        return this.request('getOrderStatusExtended.do', { orderId, language: 'ru' });
    }
}

export function verifiedVtbSandboxState(data: Record<string, any>, expected: { orderNumber: string; bankAmountMinor: number }) {
    if (!data || ('success' in data && data.success !== true) ||
        ('errorCode' in data && String(data.errorCode) !== '0') ||
        data.orderNumber !== expected.orderNumber || String(data.currency) !== '398' ||
        !Number.isSafeInteger(data.amount) || data.amount !== expected.bankAmountMinor) return 'UNVERIFIED';
    const status = Number(data.orderStatus);
    if (status === 2 && String(data.actionCode) === '0') return 'SUCCEEDED';
    if (status === 3 || status === 4) return 'CANCELLED';
    if (status === 6) return 'FAILED';
    return 'PENDING';
}
