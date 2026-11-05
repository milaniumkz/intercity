import {BadRequestException, Injectable, Logger, ServiceUnavailableException} from '@nestjs/common';
import {promises as fs} from 'node:fs';
import {join, resolve} from 'node:path';

export function tileKey(z: string, x: string, y: string) {
    if (![z,x,y].every(v => /^\d{1,7}$/.test(v))) throw new BadRequestException('Некорректный участок карты');
    const [zoom,col,row]=[z,x,y].map(Number);
    if (zoom>19 || col>=2**zoom || row>=2**zoom) throw new BadRequestException('Некорректный участок карты');
    return `${zoom}-${col}-${row}`;
}
const PNG=Buffer.from([137,80,78,71,13,10,26,10]);
type Entry={body:Buffer;expires:number;etag?:string;modified?:string;cacheControl?:string;staleAllowed?:boolean};
export class MapTileCache {
    private pending=new Map<string,Promise<Entry>>();
    private active=0;
    private writes=0;
    constructor(private root:string, private request:typeof fetch=fetch) {}
    async get(z:string,x:string,y:string):Promise<Entry> {
        const key=tileKey(z,x,y);
        if(this.pending.has(key)) return this.pending.get(key)!;
        if(this.pending.size>=128) throw new ServiceUnavailableException('Карта загружается. Повторите через несколько секунд.');
        const task=this.load(key,z,x,y).finally(()=>this.pending.delete(key));
        this.pending.set(key,task);
        return task;
    }
    private async load(key:string,z:string,x:string,y:string):Promise<Entry> {
        const file=join(this.root,key+'.json');
        let cached:Entry|undefined;
        try {const data=JSON.parse(await fs.readFile(file,'utf8'));const body=Buffer.from(data.body,'base64');if(body.subarray(0,8).equals(PNG))cached={...data,body};}catch{}
        if(cached && cached.expires>Date.now()) return cached;
        // Bound concurrent upstream requests without speculative tile prefetch.
        for(let n=0;this.active>=8 && n<100;n++)await new Promise(r=>setTimeout(r,50));
        if(this.active>=8)throw new ServiceUnavailableException('Сервис карты занят');
        this.active++;
        try {
            const headers:Record<string,string>={'User-Agent':'InterCity/1.0 (+https://intercity.89-207-255-27.sslip.io)','Accept':'image/png'};
            if(cached?.etag)headers['If-None-Match']=cached.etag;
            if(cached?.modified)headers['If-Modified-Since']=cached.modified;
            const response=await this.request(`https://tile.openstreetmap.org/${Number(z)}/${Number(x)}/${Number(y)}.png`,{headers,signal:AbortSignal.timeout(6000),redirect:'error'});
            if(!response.ok && response.status!==304)throw new Error(`upstream HTTP ${response.status}`);
            const policy=response.headers.get('cache-control')||cached?.cacheControl||'';
            const explicitAge=/(?:^|,)\s*max-age=(\d+)/i.exec(policy)?.[1];
            const expires=Date.parse(response.headers.get('expires')||'');
            const ttl=/no-cache|no-store/i.test(policy)?0:explicitAge!==undefined?Number(explicitAge):Number.isFinite(expires)?Math.max(0,(expires-Date.now())/1000):604800;
            const body=response.status===304&&cached?cached.body:Buffer.from(await response.arrayBuffer());
            if(body.length>512*1024 || !body.subarray(0,8).equals(PNG))throw new Error('invalid map image');
            const entry:Entry={body,expires:Date.now()+ttl*1000,etag:response.headers.get('etag')||cached?.etag,modified:response.headers.get('last-modified')||cached?.modified,cacheControl:policy,staleAllowed:!/no-cache|no-store|must-revalidate/i.test(policy)};
            if(/no-store/i.test(policy)){await fs.unlink(file).catch(()=>{});return entry;}
            await fs.mkdir(this.root,{recursive:true});
            const temp=file+'.tmp';
            await fs.writeFile(temp,JSON.stringify({...entry,body:body.toString('base64')}));
            await fs.rename(temp,file);
            if(++this.writes%64===0)void this.prune().catch(()=>{});
            return entry;
        }catch(error){
            // Previously fetched imagery remains useful during a short outage.
            if(cached && cached.staleAllowed!==false && cached.expires>Date.now()-86400000)return cached;
            throw error;
        }finally{this.active--;}
    }
    private async prune(){
        const names=(await fs.readdir(this.root)).filter(n=>/^\d+-\d+-\d+\.json$/.test(n));
        if(names.length<=3000)return;
        const files=await Promise.all(names.map(async name=>({name,at:(await fs.stat(join(this.root,name))).mtimeMs})));
        files.sort((a,b)=>a.at-b.at);
        await Promise.all(files.slice(0,files.length-3000).map(f=>fs.unlink(join(this.root,f.name)).catch(()=>{})));
    }
}
@Injectable()
export class MapTilesService {
    private readonly cache=new MapTileCache(join(resolve(process.env.TECH_STORAGE_DIR||join(process.cwd(),'technical-data')),'map-tiles'));
    private readonly logger=new Logger(MapTilesService.name);
    private lastWarning=0;
    async get(z:string,x:string,y:string) {
        tileKey(z,x,y);
        try{return await this.cache.get(z,x,y);}catch(error){
            if(Date.now()-this.lastWarning>60000){this.lastWarning=Date.now();this.logger.warn('Не удалось загрузить изображение карты: '+(error instanceof Error?error.message:'network failure'));}
            throw new ServiceUnavailableException('Не удалось загрузить карту. Повторите загрузку.');
        }
    }
}
