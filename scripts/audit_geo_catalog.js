#!/usr/bin/env node
// Read-only audit of the deployed city database and public OSM house samples.
const fs=require('fs'),path=require('path'),zlib=require('zlib');
const base=(process.env.BASE_URL || 'https://api.intercity.89-207-255-27.sslip.io/api').replace(/\/$/,'');
const data=process.env.CATALOG_DIR || path.join(__dirname,'../backend/src/geo/data');
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const distance=(a,b)=>{const rad=v=>v*Math.PI/180;const lat=rad(b.lat-a.lat),lng=rad(b.lng-a.lng);return 12742*Math.asin(Math.min(1,Math.sqrt(Math.sin(lat/2)**2+Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(lng/2)**2)));};
const house=value=>String(value).normalize('NFKC').toLowerCase().replaceAll('a','а').replace(/\s+/g,'');
async function request(parameters){
 const url=base+'/geo/search?'+new URLSearchParams(parameters);
 for(let attempt=0;attempt<2;attempt++){
  try{const response=await fetch(url,{signal:AbortSignal.timeout(15000)});if(!response.ok)throw Error('HTTP '+response.status);const rows=await response.json();if(!Array.isArray(rows))throw Error('Non-list response');return rows;}
  catch(error){if(attempt)throw error;await pause(500);}
 }
}
async function pool(items,task){let next=0;await Promise.all(Array.from({length:2},async()=>{while(next<items.length)await task(items[next++]);}));}
(async()=>{
 const started=Date.now();const inventoryResponse=await fetch(base+'/geo/cities',{signal:AbortSignal.timeout(30000)});
 if(!inventoryResponse.ok)throw Error('City inventory HTTP '+inventoryResponse.status);
 const inventory=await inventoryResponse.json();if(!Array.isArray(inventory)||inventory.length<1000)throw Error('Incomplete database catalog');
 const groups=new Map();for(const city of inventory){const values=groups.get(city.name)||[];values.push(city);groups.set(city.name,values);}
 const failures=[];let cityChecked=0;const countries={};
 await pool([...groups],async([query,expected])=>{
  try{const rows=await request({q:query,type:'city'});
   for(const city of expected){const matched=rows.some(row=>row.id===city.id&&row.countryCode===city.countryCode&&distance(city,row)<.2);
    if(!matched)failures.push({kind:'city',query,id:city.id,country:city.countryCode});
    cityChecked++;countries[city.countryCode]=(countries[city.countryCode]||0)+1;
   }
  }catch(error){cityChecked+=expected.length;failures.push({kind:'city',query,error:String(error)});}
  if(cityChecked%1000<expected.length)console.log('Cities checked',cityChecked,'failures',failures.length);
 });
 const fixtures=JSON.parse(zlib.gunzipSync(fs.readFileSync(path.join(data,'kz-audit-samples.json.gz'))));
 const addresses=fixtures.flatMap(fixture=>fixture.addresses.map(address=>({...address,locality:fixture.city.name})));
 let addressChecked=0;
 await pool(addresses,async(address)=>{
  try{const rows=await request({q:address.street+', '+address.house,lat:String(address.lat),lng:String(address.lng)});
   const matched=rows.some(row=>distance(address,row)<.2 && (row.houseNumber ? house(row.houseNumber)===house(address.house) :
       String(row.displayName).split(',').some(part=>house(part)===house(address.house))));
   if(!matched)failures.push({kind:'address',query:address.street+', '+address.house,city:address.locality});
  }catch(error){failures.push({kind:'address',city:address.locality,error:String(error)});}
  addressChecked++;if(addressChecked%100===0)console.log('Addresses checked',addressChecked,'failures',failures.length);
 });
 const report={base,checkedAt:new Date().toISOString(),cities:cityChecked,countries,addresses:addressChecked,
   sampledLocalities:fixtures.filter(f=>f.addresses.length).length,failures,seconds:Math.round((Date.now()-started)/1000)};
 if(process.env.OUTPUT_PATH)fs.writeFileSync(process.env.OUTPUT_PATH,JSON.stringify(report,null,2));
 console.log('GEO_AUDIT_RESULT',JSON.stringify(report));if(failures.length)process.exitCode=1;
})().catch(error=>{console.error('GEO_AUDIT_FAILED',String(error));process.exitCode=1;});
