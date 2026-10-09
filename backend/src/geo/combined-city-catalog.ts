import { readFileSync } from 'fs';
import { join } from 'path';
import { cityCatalog as original } from './city-catalog';
// Kazakhstan uses the current OSM names plus all unmatched GeoNames settlements.
export const cityCatalog: Array<{name:string;aliases:string[];countryCode:string;region?:string;population?:number;lat:number;lng:number}> = [
    ...JSON.parse(readFileSync(join(__dirname, 'data/ru-cities.json'), 'utf8')),
    ...JSON.parse(readFileSync(join(__dirname, 'data/kz-cities.json'), 'utf8')),
];
