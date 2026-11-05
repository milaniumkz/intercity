/** Public-service limits apply to the entire application, not each phone. */
export class GeoProviderGate {
    private readonly states = new Map<string, {next:number;blocked:number;tail:Promise<void>;waiting:number}>();
    constructor(private readonly clock=()=>Date.now(),private readonly wait=(ms:number)=>new Promise<void>(r=>setTimeout(r,ms))) {}
    async run(url:string, request:()=>Promise<Response>):Promise<Response> {
        const host=new URL(url).hostname.toLowerCase();
        const key=['router.project-osrm.org','routing.openstreetmap.de','valhalla1.openstreetmap.de'].includes(host)?'fossgis-routing':host;
        const limited=key==='fossgis-routing'||host==='nominatim.openstreetmap.org'||host==='photon.komoot.io';
        let state=this.states.get(key);
        if(!state){state={next:0,blocked:0,tail:Promise.resolve(),waiting:0};this.states.set(key,state);}
        if(state.blocked>this.clock()||state.waiting>=3)throw new Error('Geo provider temporarily unavailable');
        state.waiting++;
        const previous=state.tail;
        let release:()=>void;
        state.tail=new Promise<void>(r=>{release=r});
        try {
            await previous;
            if(state.blocked>this.clock())throw new Error('Geo provider cooldown');
            if(limited&&state.next>this.clock())await this.wait(state.next-this.clock());
            state.next=this.clock()+(limited?1100:0);
            try {
                const response=await request();
                if(response.status===429||response.status===403||response.status>=500){
                    const retry=response.headers.get('retry-after');
                    const seconds=retry&&/^\d+$/.test(retry)?Number(retry):retry?Math.ceil((Date.parse(retry)-this.clock())/1000):0;
                    state.blocked=this.clock()+1000*Math.max(response.status===429||response.status===403?60:15,Math.min(Number.isFinite(seconds)?seconds:0,600));
                }
                return response;
            }catch(error){state.blocked=this.clock()+15000;throw error;}
        }finally{state.waiting--;release!();}
    }
}
export function publicNominatim(url:string){return new URL(url).hostname.toLowerCase()==='nominatim.openstreetmap.org';}
export function routeProviderAllowed(url:string, explicitlyAllowed:unknown, operatorPermission?:unknown) {
    let host:string;
    try {const u=new URL(url);if(!['http:','https:'].includes(u.protocol))return false;host=u.hostname.toLowerCase();}catch{return false;}
    if(['router.project-osrm.org','routing.openstreetmap.de','valhalla1.openstreetmap.de'].includes(host))return explicitlyAllowed==='true' && typeof operatorPermission==='string' && operatorPermission.trim().length>0;
    // Existing owner-controlled local routing instances need no public-demo quota.
    const own=host==='localhost'||host==='[::1]'||host.startsWith('127.')||host.startsWith('10.')||host.startsWith('192.168.')||/^172\.(1[6-9]|2\d|3[01])\./.test(host)||!host.includes('.')||host.endsWith('.internal')||host.endsWith('.local');
    return own||explicitlyAllowed==='true';
}
