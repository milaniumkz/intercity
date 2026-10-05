import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();
const db = prisma as any;

async function main() {
    console.log('Seeding database...');

    const isProduction = process.env.NODE_ENV === 'production';
    const shouldSeedDefaultAdmin =
        !isProduction || process.env.SEED_DEFAULT_ADMIN === 'true';
    const seedAdminPhone = process.env.SEED_ADMIN_PHONE?.trim() || '+70000000000';
    const seedAdminPasswordRaw =
        process.env.SEED_ADMIN_PASSWORD?.trim() || '123456';

    let admin: { id: string; phone: string } | null = null;
    if (shouldSeedDefaultAdmin) {
        const adminPassword = await bcrypt.hash(seedAdminPasswordRaw, 10);
        admin = await prisma.user.upsert({
            where: { phone: seedAdminPhone },
            update: {},
            create: {
                phone: seedAdminPhone,
                password: adminPassword,
                name: 'Admin',
                role: 'ADMIN',
                refCode: 'ADMIN01',
                refLink: 'https://intercity.app/ref/ADMIN01',
            },
        });

        await prisma.wallet.upsert({
            where: { userId: admin.id },
            update: {},
            create: { userId: admin.id },
        });

        console.log('Admin user created:', admin.phone);
    } else {
        console.log(
            'Skipping default admin seed in production. Set SEED_DEFAULT_ADMIN=true to opt in explicitly.',
        );
    }

    const permissions = [
        ['dashboard.view', 'dashboard', 'view', 'Просмотр dashboard'],
        ['orders.view', 'orders', 'view', 'Просмотр заказов'],
        ['orders.manage', 'orders', 'manage', 'Управление заказами'],
        ['drivers.view', 'drivers', 'view', 'Просмотр водителей'],
        ['drivers.manage', 'drivers', 'manage', 'Управление водителями'],
        ['users.view', 'users', 'view', 'Просмотр клиентов'],
        ['users.manage', 'users', 'manage', 'Управление клиентами'],
        ['finance.view', 'finance', 'view', 'Просмотр финансов'],
        ['finance.manage', 'finance', 'manage', 'Управление выплатами и пополнениями'],
        ['tariffs.view', 'tariffs', 'view', 'Просмотр тарифов'],
        ['tariffs.manage', 'tariffs', 'manage', 'Управление тарифами'],
        ['vehicles.view', 'vehicles', 'view', 'Просмотр автопарка'],
        ['vehicles.manage', 'vehicles', 'manage', 'Управление автопарком'],
        ['promos.view', 'promos', 'view', 'Просмотр промокодов'],
        ['promos.manage', 'promos', 'manage', 'Управление промокодами'],
        ['support.view', 'support', 'view', 'Просмотр жалоб и обращений'],
        ['support.manage', 'support', 'manage', 'Управление жалобами и решениями'],
        ['notifications.view', 'notifications', 'view', 'Просмотр рассылок'],
        ['notifications.manage', 'notifications', 'manage', 'Управление рассылками'],
        ['settings.view', 'settings', 'view', 'Просмотр системных настроек'],
        ['settings.manage', 'settings', 'manage', 'Управление системными настройками'],
        ['collections.view', 'collections', 'view', 'Просмотр коллекций БД'],
        ['collections.manage', 'collections', 'manage', 'Изменение коллекций БД'],
        ['system.view', 'system', 'view', 'Просмотр системных логов и мониторинга'],
        ['system.manage', 'system', 'manage', 'Критические системные действия'],
        ['rbac.view', 'rbac', 'view', 'Просмотр ролей и прав'],
        ['rbac.manage', 'rbac', 'manage', 'Управление ролями и правами'],
    ] as const;

    for (const [key, module, action, description] of permissions) {
        await db.adminPermission.upsert({
            where: { key },
            update: { module, action, description },
            create: { key, module, action, description },
        });
    }

    const superAdminRole = await db.adminRole.upsert({
        where: { code: 'SUPER_ADMIN' },
        update: { name: 'Super Admin', description: 'Полный доступ', isSystem: true },
        create: {
            code: 'SUPER_ADMIN',
            name: 'Super Admin',
            description: 'Полный доступ',
            isSystem: true,
        },
    });

    const supportRole = await db.adminRole.upsert({
        where: { code: 'SUPPORT' },
        update: { name: 'Support', description: 'Поддержка и операционные задачи', isSystem: true },
        create: {
            code: 'SUPPORT',
            name: 'Support',
            description: 'Поддержка и операционные задачи',
            isSystem: true,
        },
    });

    const accountantRole = await db.adminRole.upsert({
        where: { code: 'ACCOUNTANT' },
        update: { name: 'Accountant', description: 'Финансовые операции', isSystem: true },
        create: {
            code: 'ACCOUNTANT',
            name: 'Accountant',
            description: 'Финансовые операции',
            isSystem: true,
        },
    });

    const allPermissions = await db.adminPermission.findMany({
        select: { id: true, key: true },
    });
    for (const permission of allPermissions) {
        await db.adminRolePermission.upsert({
            where: {
                roleId_permissionId: {
                    roleId: superAdminRole.id,
                    permissionId: permission.id,
                },
            },
            update: {},
            create: {
                roleId: superAdminRole.id,
                permissionId: permission.id,
            },
        });
    }

    const supportPermissionKeys = new Set([
        'dashboard.view',
        'orders.view',
        'orders.manage',
        'drivers.view',
        'drivers.manage',
        'users.view',
        'users.manage',
        'system.view',
        'support.view',
        'support.manage',
        'promos.view',
    ]);
    for (const permission of allPermissions.filter((p) => supportPermissionKeys.has(p.key))) {
        await db.adminRolePermission.upsert({
            where: {
                roleId_permissionId: {
                    roleId: supportRole.id,
                    permissionId: permission.id,
                },
            },
            update: {},
            create: {
                roleId: supportRole.id,
                permissionId: permission.id,
            },
        });
    }

    const accountantPermissionKeys = new Set([
        'dashboard.view',
        'finance.view',
        'finance.manage',
        'orders.view',
        'promos.view',
    ]);
    for (const permission of allPermissions.filter((p) => accountantPermissionKeys.has(p.key))) {
        await db.adminRolePermission.upsert({
            where: {
                roleId_permissionId: {
                    roleId: accountantRole.id,
                    permissionId: permission.id,
                },
            },
            update: {},
            create: {
                roleId: accountantRole.id,
                permissionId: permission.id,
            },
        });
    }

    if (admin) {
        await db.adminUserRole.upsert({
            where: {
                userId_roleId: {
                    userId: admin.id,
                    roleId: superAdminRole.id,
                },
            },
            update: {},
            create: {
                userId: admin.id,
                roleId: superAdminRole.id,
            },
        });
    }

    console.log('RBAC bootstrap completed');

    // Create sample cities
    const cities = [
        { name: 'Алматы', region: 'Алматинская область', lat: 43.2220, lng: 76.8512 },
        { name: 'Астана', region: 'Акмолинская область', lat: 51.1694, lng: 71.4491 },
        { name: 'Шымкент', region: 'Туркестанская область', lat: 42.3155, lng: 69.5869 },
        { name: 'Караганда', region: 'Карагандинская область', lat: 49.8019, lng: 73.1021 },
        { name: 'Актобе', region: 'Актюбинская область', lat: 50.2797, lng: 57.2072 },
    ];

    for (const city of cities) {
        await prisma.city.upsert({
            where: { name: city.name },
            update: {
                region: city.region,
                lat: city.lat,
                lng: city.lng,
                isActive: true,
            },
            create: {
                name: city.name,
                region: city.region,
                lat: city.lat,
                lng: city.lng,
            },
        });
    }

    console.log('Cities created');

    // Create default app settings
    const settings = [
        { key: 'referralPercent', value: '10' },
        { key: 'referralCommissionPercent', value: '25' },
        { key: 'minPayoutAmount', value: '1000' },
        { key: 'allowBonusRideIfBelowMin', value: 'true' },
        { key: 'searchRadiusKm', value: '5' },
        { key: 'dispatchTimeoutSec', value: '20' },
        { key: 'minDriverLocationFreshSec', value: '60' },
        { key: 'driverOfferAcceptSec', value: '30' },
        { key: 'cityAutoAssignEnabled', value: 'false' },
        { key: 'driverMinOnlineBalance', value: '100' },
    ];

    for (const setting of settings) {
        await prisma.appSettings.upsert({
            where: { key: setting.key },
            update: { value: setting.value },
            create: { key: setting.key, value: setting.value },
        });
    }

    console.log('Settings created');

    // Create default tariffs for Алматы
    const almaty = await prisma.city.findUnique({ where: { name: 'Алматы' } });
    if (almaty) {
        await prisma.tariffCity.upsert({
            where: { id: 'tariff-city-econom-default' },
            update: {},
            create: {
                id: 'tariff-city-econom-default',
                cityId: almaty.id,
                name: 'Эконом',
                basePrice: 400,
                pricePerKm: 50,
                pricePerMin: 5,
                minPrice: 500,
            },
        });

        await prisma.tariffCity.upsert({
            where: { id: 'tariff-city-comfort-default' },
            update: {},
            create: {
                id: 'tariff-city-comfort-default',
                cityId: almaty.id,
                name: 'Комфорт',
                basePrice: 600,
                pricePerKm: 70,
                pricePerMin: 7,
                minPrice: 800,
            },
        });
    }

    console.log('Tariffs created');
    console.log('Seed completed!');
}

main()
    .catch((e) => {
        console.error(e);
        process.exit(1);
    })
    .finally(async () => {
        await prisma.$disconnect();
    });
