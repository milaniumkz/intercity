import { BadGatewayException, ServiceUnavailableException } from '@nestjs/common';

export const VTB_SANDBOX_REST_URL = 'https://vtbkz.rbsuat.com/payment/rest/';
export type VtbSandboxOptions = { userName: string; password: string };

export class VtbSandboxGateway {
    constructor(private readonly options: VtbSandboxOptions, private readonly transport: typeof fetch = fetch) {}

    get configured() { return !!this.options.userName && !!this.options.password; }

    private async request(method: 'register.do' | 'getOrderStatusExtended.do', values: Record<string, string>) {
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
        if (('success' in data && data.success !== true) || ('errorCode' in data && String(data.errorCode) !== '0')) {
            const code = /^\d{1,3}$/.test(String(data.errorCode)) ? String(data.errorCode) : 'unknown';
            // Do not expose provider messages, request bodies or credentials.
            throw new BadGatewayException('ВТБ отклонил тестовую операцию (код ' + code + ')');
        }
        return data;
    }

    async register(input: { orderNumber: string; amountMinor: number; returnUrl: string }) {
        if (!/^[A-Za-z0-9_-]{1,36}$/.test(input.orderNumber) ||
            !Number.isSafeInteger(input.amountMinor) || input.amountMinor < 100 || input.amountMinor > 10000000) {
            throw new Error('Invalid sandbox payment parameters');
        }
        const returnUrl = new URL(input.returnUrl);
        if (returnUrl.protocol !== 'https:' || returnUrl.username || returnUrl.password) throw new Error('HTTPS return URL required');
        const data = await this.request('register.do', {
            orderNumber: input.orderNumber, amount: String(input.amountMinor),
            currency: '643', language: 'ru', returnUrl: returnUrl.toString(),
            description: 'InterCity: тестовая оплата в рублях',
            sessionTimeoutSecs: '1200',
        });
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

    statusByOrderNumber(orderNumber: string) {
        if (!/^[A-Za-z0-9_-]{1,36}$/.test(orderNumber)) throw new Error('Invalid merchant order identifier');
        return this.request('getOrderStatusExtended.do', { orderNumber, language: 'ru' });
    }

    status(orderId: string) {
        if (!/^[a-f0-9-]{36}$/i.test(orderId)) throw new Error('Invalid bank order identifier');
        return this.request('getOrderStatusExtended.do', { orderId, language: 'ru' });
    }
}

export function verifiedVtbSandboxState(data: Record<string, any>, expected: { orderNumber: string; amountMinor: number }) {
    if (!data || ('success' in data && data.success !== true) ||
        ('errorCode' in data && String(data.errorCode) !== '0') ||
        data.orderNumber !== expected.orderNumber || String(data.currency) !== '643' ||
        !Number.isSafeInteger(data.amount) || data.amount !== expected.amountMinor) return 'UNVERIFIED';
    const status = Number(data.orderStatus);
    if (status === 2 && String(data.actionCode) === '0') return 'SUCCEEDED';
    if (status === 3 || status === 4) return 'CANCELLED';
    if (status === 6) return 'FAILED';
    return 'PENDING';
}
