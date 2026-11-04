export type OcrLine={text:string;confidence:number};
export type VehicleData={brand:string;model:string;year:number;plateNumber:string};
const fold=(v:string)=>v.toUpperCase().replace(/[АВСЕНКМОРТХУІ]/g,c=>({'А':'A','В':'B','С':'C','Е':'E','Н':'H','К':'K','М':'M','О':'O','Р':'P','Т':'T','Х':'X','У':'Y','І':'I'}[c]!));
export function normalizePlate(v:string){return fold(v).replace(/[^A-Z0-9]/g,'');}
export function validPlate(v:string){return /^[ABEKMHOPCTYX]\d{3}[ABEKMHOPCTYX]{2}\d{2,3}$/.test(v)||/^\d{3}[A-Z]{2,3}(?:0[1-9]|1\d|20)$/.test(v)||/^[A-Z]\d{3}[A-Z]{2,3}$/.test(v);}
export function validateVehicleData(value:any):VehicleData {
 if(typeof value?.brand!=='string'||typeof value?.model!=='string'||typeof value?.plateNumber!=='string')throw new Error('Укажите данные автомобиля');
 const data={brand:String(value?.brand||'').trim(),model:String(value?.model||'').trim(),year:Number(value?.year),plateNumber:normalizePlate(String(value?.plateNumber||''))};
 if(!data.brand||data.brand.length>80||!data.model||data.model.length>100||!Number.isInteger(data.year)||data.year<1900||data.year>new Date().getUTCFullYear()+1||!validPlate(data.plateNumber))throw new Error('Укажите марку, модель, год выпуска и госномер из техпаспорта');
 return data;
}
export function parseVehicleDocument(lines:OcrLine[],catalogue:{name:string;models:{name:string}[]}[]):VehicleData|null {
 const rows=lines.filter(r=>typeof r.text==='string'&&r.text.length<=500&&Number.isFinite(r.confidence));
 const window=(label:RegExp)=>rows.flatMap((r,i)=>{const group=rows.slice(i,i+3);return label.test(r.text)&&group.every(x=>x.confidence>=85)?group.map(x=>x.text):[];}).join(' ').toUpperCase();
 const plateText=fold(window(/ГОСУДАРСТВЕНН|РЕГИСТРАЦИОНН.*(?:ЗНАК|НОМЕР)|ТІРКЕУ.*НӨМІР|МЕМЛЕКЕТТІК.*НӨМІР|REGISTRATION.*(?:NO|NUMBER)/i));
 const plates=new Set((plateText.match(/\b[ABEKMHOPCTYX]\s*\d{3}\s*[ABEKMHOPCTYX]{2}\s*\d{2,3}\b|\b\d{3}\s*[A-Z]{2,3}\s*\d{2}\b|\b[A-Z]\s*\d{3}\s*[A-Z]{2,3}\b/g)||[]).map(normalizePlate).filter(validPlate));
 const yearText=window(/ГОД.*ВЫПУСК|ВЫПУСКА|ШЫҒАРЫЛҒАН.*ЖЫЛ|YEAR.*(?:MANUFACT|PRODUCTION)/i);
 const years=[...new Set(yearText.match(/\b(?:19|20)\d{2}\b/g)||[])].map(Number).filter(y=>y<=new Date().getUTCFullYear()+1);
 const modelText=fold(window(/МАРКА|МОДЕЛ|МАРКАСЫ|МОДЕЛІ|\bMAKE\b|\bMODEL\b/i));
 const escape=(v:string)=>v.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
 const has=(v:string)=>new RegExp('(?:^|[\\s,;:/])'+escape(fold(v))+'(?=$|[\\s,;:/])').test(modelText);
 const pairs=catalogue.flatMap(make=>has(make.name)?make.models.filter(model=>has(model.name)).map(model=>({brand:make.name,model:model.name})):[]);
 if(plates.size!==1||years.length!==1||pairs.length!==1)return null;
 try{return validateVehicleData({...pairs[0],year:years[0],plateNumber:[...plates][0]});}catch{return null;}
}
