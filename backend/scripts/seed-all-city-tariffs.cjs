const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {PrismaClient} = require('@prisma/client');

const defaults = {
  KZ: {basePrice:400,pricePerKm:90,pricePerMin:15,minPrice:700},
  RU: {basePrice:90,pricePerKm:18,pricePerMin:4,minPrice:150},
};
const valid = tariff => Number.isFinite(tariff.basePrice) && tariff.basePrice>=0 &&
  Number.isFinite(tariff.pricePerKm) && tariff.pricePerKm>0 &&
  Number.isFinite(tariff.pricePerMin) && tariff.pricePerMin>=0 &&
  Number.isFinite(tariff.minPrice) && tariff.minPrice>0;

async function seedAllCityTariffs(db, where = {countryCode:{in:['KZ','RU']}}) {
  return db.$transaction(async tx => {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(6100629)`;
    await tx.$executeRawUnsafe('LOCK TABLE "TariffCity" IN SHARE ROW EXCLUSIVE MODE');
    const cities = await tx.city.findMany({where,include:{tariffs:{orderBy:{id:'asc'}}},orderBy:{id:'asc'}});
    const originals = cities.flatMap(c=>c.tariffs);
    const originalIds = new Set(originals.map(t=>t.id));
    const rows = [];
    const result = {KZ:{cities:0,created:0},RU:{cities:0,created:0}};
    for (const city of cities) {
      assert(defaults[city.countryCode], 'Unsupported tariff country');
      result[city.countryCode].cities++;
      const active = city.tariffs.filter(t=>t.isActive);
      assert(active.every(valid), 'Existing invalid active tariff requires review: '+city.name);
      if (active.length) continue;
      rows.push({id:randomUUID(),cityId:city.id,name:'Эконом — базовый тариф',...defaults[city.countryCode],isActive:true});
      result[city.countryCode].created++;
    }
    for (let offset=0; offset<rows.length; offset+=500) {
      const batch = rows.slice(offset,offset+500);
      assert.equal((await tx.tariffCity.createMany({data:batch})).count,batch.length);
    }
    const after = await tx.city.findMany({where,include:{tariffs:{orderBy:{id:'asc'}}},orderBy:{id:'asc'}});
    assert.equal(JSON.stringify(after.flatMap(c=>c.tariffs.filter(t=>originalIds.has(t.id)))),JSON.stringify(originals),'Existing tariffs changed');
    assert.equal(JSON.stringify(after.map(({tariffs,...city})=>city)),JSON.stringify(cities.map(({tariffs,...city})=>city)),'City settings changed');
    for (const city of after) assert(city.tariffs.some(t=>t.isActive&&valid(t)), 'Missing tariff: '+city.name);
    return {...result,preservedTariffs:originals.length,remainingWithoutTariff:0,defaults};
  }, {timeout:120000});
}
module.exports = {seedAllCityTariffs};
if (!module.parent) {
  const db = new PrismaClient();
  seedAllCityTariffs(db).then(result=>console.log(JSON.stringify(result)))
    .catch(error=>{console.error(error.message);process.exitCode=1})
    .finally(()=>db.$disconnect());
}
