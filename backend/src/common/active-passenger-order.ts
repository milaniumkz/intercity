import { ConflictException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';

// Serialize both creation paths on the same account until creation commits.
export async function requireNoActivePassengerOrder(tx: Prisma.TransactionClient, passengerId: string) {
    const users = await tx.$queryRaw<Array<{ id: string }>>`
        SELECT id FROM "User" WHERE id = ${passengerId} FOR UPDATE
    `;
    if (users.length !== 1) throw new NotFoundException('User not found');
    const order = await tx.order.findFirst({
        where: { passengerId, status: { notIn: ['COMPLETED', 'CANCELLED'] } },
        select: { id: true },
    });
    const request = order ? null : await tx.intercityRequest.findFirst({
        where: { passengerId, status: { notIn: ['COMPLETED', 'CANCELLED'] } },
        select: { id: true },
    });
    if (order || request) throw new ConflictException({
        message: 'У вас уже есть активный заказ. Завершите или отмените его перед созданием нового.',
        code: 'ACTIVE_ORDER_EXISTS',
        activeOrderId: (order || request).id,
        activeOrderType: order ? 'CITY' : 'INTERCITY',
    });
}
