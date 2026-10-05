const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function main() {
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
      update: { ...city, isActive: true },
      create: city,
    });
  }

  const settings = [
    ['referralPercent', '10'],
    ['referralCommissionPercent', '25'],
    ['minPayoutAmount', '1000'],
    ['allowBonusRideIfBelowMin', 'true'],
    ['searchRadiusKm', '5'],
    ['dispatchTimeoutSec', '20'],
    ['minDriverLocationFreshSec', '60'],
    ['driverOfferAcceptSec', '30'],
    ['cityAutoAssignEnabled', 'false'],
    ['driverMinOnlineBalance', '100'],
  ];

  for (const [key, value] of settings) {
    await prisma.appSettings.upsert({
      where: { key },
      update: { value },
      create: { key, value },
    });
  }

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

  console.log('production bootstrap data ready');
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
