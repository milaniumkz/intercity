import { Injectable, ServiceUnavailableException } from '@nestjs/common';
export type IdentityResult = { verdict:'PASS'|'REVIEW'|'REJECT'; reason:string; model:string; embedding?:number[]; videoSignature?:string[]; reference?:string; checks?:Record<string,unknown> };
@Injectable()
export class IdentityEngine {
    private readonly url=process.env.IDENTITY_ENGINE_URL || 'http://identity:8080';
    async ready() {
        try {const r=await fetch(this.url+'/health',{signal:AbortSignal.timeout(3000)});const data=await r.json() as any;return r.ok && data.ready===true && data.liveness===true;}catch{return false;}
    }
    private processing=false;
    private readonly waiters:Array<()=>void>=[];
    private async acquire():Promise<()=>void> {
        if(this.processing){
            if(this.waiters.length>=2)throw new ServiceUnavailableException('Сейчас много проверок. Повторите отправку чуть позже.');
            await new Promise<void>((resolve,reject)=>{
                const resume=()=>{clearTimeout(timer);resolve();};
                const timer=setTimeout(()=>{const at=this.waiters.indexOf(resume);if(at>=0)this.waiters.splice(at,1);reject(new ServiceUnavailableException('Очередь проверки занята. Повторите чуть позже.'));},150000);
                this.waiters.push(resume);
            });
        } else this.processing=true;
        let released=false;
        return ()=>{if(released)return;released=true;const next=this.waiters.shift();if(next)next();else this.processing=false;};
    }
    async verify(video:Buffer,actions:string[]):Promise<IdentityResult> {
        const release=await this.acquire();
        try{return await this.verifyNow(video,actions);}finally{release();}
    }
    private async verifyNow(video:Buffer,actions:string[]):Promise<IdentityResult> {
        if(!await this.ready()) throw new ServiceUnavailableException('Видеопроверка временно недоступна. Повторите позже.');
        let response:Response|undefined;
        // A document scan or another API worker may currently hold the engine.
        // Retry only its explicit busy response; never repeat a completed verdict.
        const deadline=Date.now()+75000;
        do {
            response=await fetch(this.url+'/verify',{method:'POST',headers:{'Content-Type':'application/octet-stream','X-Identity-Actions':actions.join(',')},body:new Uint8Array(video),signal:AbortSignal.timeout(90000)});
            if(response.status!==503)break;
            await response.body?.cancel();
            if(Date.now()>=deadline)break;
            await new Promise(resolve=>setTimeout(resolve,1500));
        } while(true);
        if(!response.ok)throw new ServiceUnavailableException('Не удалось обработать видео. Повторите проверку.');
        const result=await response.json() as IdentityResult;
        if(!['PASS','REVIEW','REJECT'].includes(result.verdict)||!result.model||result.model.length>150)throw new ServiceUnavailableException('Некорректный ответ видеопроверки');
        if(result.verdict!=='REJECT' && (!result.embedding || result.embedding.length!==128 || !result.embedding.every(Number.isFinite) || !result.reference || result.reference.length>600000))throw new ServiceUnavailableException('Не удалось получить качественный эталон лица');
        if(result.verdict!=='REJECT'){const norm=result.embedding!.reduce((s,v)=>s+v*v,0);if(norm<.99||norm>1.01||result.embedding!.some(v=>Math.abs(v)>1))throw new ServiceUnavailableException('Не удалось проверить эталон лица');}
        if(result.verdict!=='REJECT'&&(!Array.isArray(result.videoSignature)||result.videoSignature.length<30||result.videoSignature.length>40||!result.videoSignature.every(x=>/^[a-f0-9]{16}$/.test(x))))throw new ServiceUnavailableException('Не удалось проверить целостность видеозаписи');
        return result;
    }
    async document(image:Buffer,kind:'face'|'vehicle') {
        if(image.length>10*1024*1024)throw new ServiceUnavailableException('Документ слишком большой');
        const response=await fetch(this.url+(kind==='face'?'/document-face':'/vehicle-text'),{method:'POST',headers:{'Content-Type':'application/octet-stream'},body:new Uint8Array(image),signal:AbortSignal.timeout(45000)});
        if(!response.ok)throw new ServiceUnavailableException('Проверка документов временно недоступна');
        const result=await response.json() as any;
        if(!result.reference || result.reference.length>3000000)throw new ServiceUnavailableException('Документ не удалось прочитать');
        if(result.embedding && (result.embedding.length!==128||!result.embedding.every(Number.isFinite)))throw new ServiceUnavailableException('Не удалось прочитать лицо в документе');
        return result;
    }

}
