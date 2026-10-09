import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createReadStream, createWriteStream, readFileSync } from 'fs';
import { access, mkdir, rename, unlink } from 'fs/promises';
import { join } from 'path';
import { tmpdir } from 'os';
import { createGunzip } from 'zlib';
import { createHash } from 'crypto';
import { pipeline } from 'stream/promises';
import { execFile } from 'child_process';
import { promisify } from 'util';

const execute = promisify(execFile);
const quote = (value: string) => `'${value.replaceAll("'", "''")}'`;
export function normalizeKzStreet(value: string) {
    const letters: Record<string,string> = {'ә':'а','ғ':'г','қ':'к','ң':'н','ө':'о','ұ':'у','ү':'у','һ':'х','і':'и','ё':'е','ь':'','ъ':''};
    const types = new Set(['улица','ул','проспект','пр','прт','переулок','пер','площадь','көшесі','көшесi','кошеси','даңғылы','дангылы','микрорайон','мкр','бульвар','шоссе']);
    return (value.normalize('NFKC').toLowerCase().match(/[\p{L}\p{N}]+/gu) || [])
        .filter(word => !types.has(word))
        .map(word => word.replace(/[әғқңөұүһіёьъ]/g, letter => letters[letter]).replace(/([ое]в)а$/, '$1').replaceAll('сатпаев','сатбаев')).join(' ');
}
const normalizeHouse = (value: string) => value.normalize('NFKC').toLowerCase().replaceAll('a','а').replace(/\s+/g,'');

@Injectable()
export class KazakhstanAddressIndex {
    private readonly asset = join(__dirname, 'data/kazakhstan-addresses.sqlite.gz');
    private readonly metadata: any;
    private ready?: Promise<string>;
    constructor(private readonly config: ConfigService) {
        this.metadata = JSON.parse(readFileSync(join(__dirname, 'data/kz-metadata.json'), 'utf8'));
    }
    info() {
        return {...this.metadata, licenseUrl:'https://opendatacommons.org/licenses/odbl/1-0/',
            downloadUrl:'/api/geo/data/kz/download'};
    }
    download() { return createReadStream(this.asset); }
    private prepare() {
        if (!this.ready) this.ready = this.unpack().catch(error => { this.ready = undefined; throw error; });
        return this.ready;
    }
    private async unpack() {
        const directory = join(tmpdir(), 'intercity-geodata');
        await mkdir(directory, {recursive:true});
        const path = join(directory, `${this.metadata.compressed_sha256}.sqlite`);
        try { await access(path); return path; } catch (_) { /* First use of this snapshot. */ }
        const temporary = `${path}.${process.pid}.partial`;
        try {
            const hash = createHash('sha256');
            const input = createReadStream(this.asset);
            input.on('data', chunk => hash.update(chunk));
            await pipeline(input, createGunzip(), createWriteStream(temporary));
            if (hash.digest('hex') !== this.metadata.compressed_sha256) throw new Error('Address index checksum mismatch');
            await rename(temporary, path);
            return path;
        } catch (error) {
            await unlink(temporary).catch(() => undefined);
            throw error;
        }
    }
    async search(query: string, context: {lat:number;lng:number;countryCode?:string}) {
        if (this.config.get('KZ_ADDRESS_INDEX_ENABLED') === 'false' || context.countryCode?.toUpperCase() !== 'KZ') return [];
        if (query.length > 160 || !Number.isFinite(context.lat) || !Number.isFinite(context.lng)) return [];
        let street = query.trim(), house = '';
        // Preserve fractional numbers and building letters. The last comma separates a house unambiguously.
        const comma = street.lastIndexOf(',');
        const last = comma >= 0 ? street.slice(comma+1).trim() : '';
        if (/^\d[\p{L}\p{N}\s/\-]*$/u.test(last)) {
            house = last; street = street.slice(0, comma);
        } else {
            const suffix = street.match(/(?:^|\s)(\d+[\p{L}]?(?:\/\d+[\p{L}]?)?(?:\s+(?:к|корпус|стр)\s*[\p{L}\d]+)?)$/iu);
            if (suffix) { house = suffix[1]; street = street.slice(0, suffix.index).trim(); }
        }
        const tokens = normalizeKzStreet(street).split(' ').filter(Boolean);
        if (!tokens.length || tokens.length > 12) return [];
        const match = tokens.map(token => `"${token}"*`).join(' AND ');
        const lat = context.lat, lng = context.lng;
        const latDelta = 50/111, lngDelta = 50/(111*Math.max(.25,Math.cos(lat*Math.PI/180)));
        const number = normalizeHouse(house);
        const houseCondition = number ? `AND (a.house_key=${quote(number)} OR a.house_key GLOB ${quote(number+'[a-zа-яё]*')})` : '';
        const sql = `SELECT a.street,a.house,a.city,a.lat,a.lng,a.osm_type,a.osm_id,a.house_key FROM street_search
            JOIN addresses a ON a.id=street_search.rowid
            WHERE street_search MATCH ${quote(match)} AND a.lat BETWEEN ${lat-latDelta} AND ${lat+latDelta}
            AND a.lng BETWEEN ${lng-lngDelta} AND ${lng+lngDelta} ${houseCondition}
            ORDER BY ${number ? `CASE WHEN a.house_key=${quote(number)} THEN 0 ELSE 1 END,` : ''}
                (a.lat-${lat})*(a.lat-${lat})+(a.lng-${lng})*(a.lng-${lng}) LIMIT 20`;
        const database = await this.prepare();
        const result = await execute(this.config.get('SQLITE3_BIN') || 'sqlite3', ['-json','-readonly',database,sql],
            {timeout:8000,maxBuffer:256*1024});
        const rows = JSON.parse(result.stdout || '[]');
        return rows.map((row: any) => ({displayName:[row.street,row.house,row.city,'Казахстан'].filter(Boolean).join(', '),
            lat:row.lat,lng:row.lng,houseNumber:row.house,road:row.street,
            source:`https://www.openstreetmap.org/${row.osm_type}/${row.osm_id}`,
            attribution:'© OpenStreetMap contributors', snapshot:this.metadata.snapshot}));
    }
}
