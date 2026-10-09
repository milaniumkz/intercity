import { PrismaClient } from '@prisma/client';
import { v5 as uuid } from 'uuid';
import { cityCatalog } from './combined-city-catalog';
const token = (name:string) => name.toLowerCase().replace(/ё/g,'е').replace(/[‐‑–—-]+/g,' ').replace(/\s+/g,' ').trim();
const distance = (a:any,b:any) => Math.hypot((a.lat-b.lat)*111,(a.lng-b.lng)*111*Math.cos(a.lat*Math.PI/180));
/** Add public settlements without replacing existing IDs, coordinates, activation or tariffs. */
export async function importCityCatalog(db:any, catalog=cityCatalog) {
    const major=catalog.filter(city=>(city.population || 0)>=100000).map(city=>({...city,keys:new Set([city.name,...city.aliases].map(token))}));
    return db.$transaction(async(tx:any)=>{
        await tx.$executeRawUnsafe('SELECT pg_advisory_xact_lock(69090701)');
        const existing:any[] = await tx.city.findMany();
        const original=new Map(existing.map(city=>[city.id,{name:city.name,aliases:city.aliases||[],region:city.region}]));
        const byName = new Map<string,any[]>();
        const remember = (city:any) => { for (const name of [city.name,...(city.aliases || [])]) {
            const key=city.countryCode+':'+token(name); const rows=byName.get(key)||[];
            if (!rows.includes(city)) rows.push(city); byName.set(key,rows);
        }};
        existing.forEach(city=>{city._canonicalDistance=Infinity;remember(city);});
        const additions:any[]=[];
        for (const city of catalog) {
            const candidates=[city.name,...city.aliases].flatMap(name=>byName.get(city.countryCode+':'+token(name)) || []);
            // Existing city centres may have been edited; newly imported places
            // remain separate even when their shared name is a few kilometres away.
            const isMajor=major.some(place=>distance(place,city)<20 && [city.name,...city.aliases].some(name=>place.keys.has(token(name))));
            const match=candidates.filter(row=>distance(row,city)<(isMajor ? 15 : row._insert?.id ? .25 : 5)).sort((a,b)=>distance(a,city)-distance(b,city))[0];
            if (match) {
                match.aliases=[...new Set([...(match.aliases||[]),match.name,city.name,...city.aliases])].filter(Boolean).sort();
                match.region=match.region || city.region || null;
                const d=distance(match,city);
                if (d<match._canonicalDistance) {match.name=city.name;match._canonicalDistance=d;}
                if(match._insert) Object.assign(match._insert,{name:match.name,aliases:match.aliases,region:match.region});
                remember(match);continue;
            }
            const row={id:uuid([city.countryCode,city.name,city.lat,city.lng].join(':'),uuid.URL),name:city.name,
                aliases:[...new Set([city.name,...city.aliases])].filter(Boolean).sort(),countryCode:city.countryCode,
                region:city.region||null,lat:city.lat,lng:city.lng,isActive:true};
            additions.push(row);remember({...row,_insert:row,_canonicalDistance:0});
        }
        let enriched=0;
        for(const match of existing) {
            const data={name:match.name,aliases:match.aliases,region:match.region};
            if(JSON.stringify(data)!==JSON.stringify(original.get(match.id))) {
                await tx.city.update({where:{id:match.id},data});enriched++;
            }
        }
        for(let i=0;i<additions.length;i+=500) await tx.city.createMany({data:additions.slice(i,i+500),skipDuplicates:true});
        return {source:catalog.length,added:additions.length,enriched,existing:existing.length};
    },{timeout:120000,maxWait:30000});
}
if (require.main===module) {
    const db=new PrismaClient();
    importCityCatalog(db).then(result=>console.log('Settlement catalog import',JSON.stringify(result)))
        .catch(()=>{console.error('Settlement catalog import failed');process.exitCode=1;}).finally(()=>db.$disconnect());
}
