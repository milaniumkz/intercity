import { BadRequestException, Injectable, Logger, Optional, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma.service';
import { KazakhstanAddressIndex } from './kz-address-index';
import { verifiedAddresses } from './verified-addresses';
import { cityCatalog } from './combined-city-catalog';
import { currencyForCountry, countryCodeFromRegion } from '../common/currency';

@Injectable()
export class GeoService {
    private static readonly fallbackCities: Array<{ name: string; region: string; lat: number; lng: number }> = [
        { name: 'Алматы', region: 'Казахстан', lat: 43.238949, lng: 76.889709 },
        { name: 'Астана', region: 'Казахстан', lat: 51.169392, lng: 71.449074 },
        { name: 'Шымкент', region: 'Казахстан', lat: 42.341684, lng: 69.590101 },
        { name: 'Караганда', region: 'Казахстан', lat: 49.804683, lng: 73.109383 },
        { name: 'Актобе', region: 'Казахстан', lat: 50.283933, lng: 57.166978 },
        { name: 'Тараз', region: 'Казахстан', lat: 42.899731, lng: 71.377963 },
        { name: 'Павлодар', region: 'Казахстан', lat: 52.287303, lng: 76.967402 },
        { name: 'Усть-Каменогорск', region: 'Казахстан', lat: 49.948986, lng: 82.627945 },
        { name: 'Семей', region: 'Казахстан', lat: 50.411117, lng: 80.2275 },
        { name: 'Атырау', region: 'Казахстан', lat: 47.094495, lng: 51.923837 },
        { name: 'Костанай', region: 'Казахстан', lat: 53.219808, lng: 63.635423 },
        { name: 'Кызылорда', region: 'Казахстан', lat: 44.848831, lng: 65.482268 },
        { name: 'Уральск', region: 'Казахстан', lat: 51.227821, lng: 51.386543 },
        { name: 'Актау', region: 'Казахстан', lat: 43.641097, lng: 51.198511 },
        { name: 'Петропавловск', region: 'Казахстан', lat: 54.87279, lng: 69.143 },
        { name: 'Кокшетау', region: 'Казахстан', lat: 53.28333, lng: 69.38333 },
        { name: 'Туркестан', region: 'Казахстан', lat: 43.29733, lng: 68.25175 },
        { name: 'Талдыкорган', region: 'Казахстан', lat: 45.017711, lng: 78.380441 },
        { name: 'Жезказган', region: 'Казахстан', lat: 47.78333, lng: 67.76667 },
        { name: 'Рудный', region: 'Казахстан', lat: 52.9729, lng: 63.11677 },
        { name: 'Экибастуз', region: 'Казахстан', lat: 51.72978, lng: 75.32663 },
        { name: 'Москва', region: 'Россия', lat: 55.755864, lng: 37.617698 },
        { name: 'Санкт-Петербург', region: 'Россия', lat: 59.938955, lng: 30.315644 },
        { name: 'Новосибирск', region: 'Россия', lat: 55.030204, lng: 82.92043 },
        { name: 'Екатеринбург', region: 'Россия', lat: 56.838011, lng: 60.597465 },
        { name: 'Казань', region: 'Россия', lat: 55.796127, lng: 49.106414 },
        { name: 'Нижний Новгород', region: 'Россия', lat: 56.326887, lng: 44.005986 },
        { name: 'Челябинск', region: 'Россия', lat: 55.164441, lng: 61.436843 },
        { name: 'Самара', region: 'Россия', lat: 53.195878, lng: 50.100202 },
        { name: 'Омск', region: 'Россия', lat: 54.989342, lng: 73.368212 },
        { name: 'Ростов-на-Дону', region: 'Россия', lat: 47.222078, lng: 39.720349 },
        { name: 'Уфа', region: 'Россия', lat: 54.734853, lng: 55.957864 },
        { name: 'Красноярск', region: 'Россия', lat: 56.010563, lng: 92.852572 },
        { name: 'Пермь', region: 'Россия', lat: 58.010455, lng: 56.229443 },
        { name: 'Воронеж', region: 'Россия', lat: 51.660781, lng: 39.200296 },
        { name: 'Волгоград', region: 'Россия', lat: 48.707103, lng: 44.516939 },
        { name: 'Краснодар', region: 'Россия', lat: 45.03547, lng: 38.975313 },
        { name: 'Саратов', region: 'Россия', lat: 51.533557, lng: 46.034257 },
        { name: 'Тюмень', region: 'Россия', lat: 57.152985, lng: 65.541227 },
        { name: 'Тольятти', region: 'Россия', lat: 53.507836, lng: 49.420393 },
        { name: 'Ижевск', region: 'Россия', lat: 56.852744, lng: 53.211396 },
        { name: 'Барнаул', region: 'Россия', lat: 53.348115, lng: 83.779836 },
        { name: 'Владивосток', region: 'Россия', lat: 43.115536, lng: 131.885485 },
        { name: 'Хабаровск', region: 'Россия', lat: 48.480223, lng: 135.071917 },
        { name: 'Иркутск', region: 'Россия', lat: 52.286974, lng: 104.305018 },
        { name: 'Оренбург', region: 'Россия', lat: 51.768199, lng: 55.096955 },
        { name: 'Калининград', region: 'Россия', lat: 54.710426, lng: 20.452214 },
        { name: 'Сочи', region: 'Россия', lat: 43.585472, lng: 39.723098 },
        { name: 'Астрахань', region: 'Россия', lat: 46.347869, lng: 48.033574 },
        { name: 'Махачкала', region: 'Россия', lat: 42.984913, lng: 47.504646 },
    ];

    private readonly logger = new Logger(GeoService.name);

    private async fetchGeo(input: string, options: RequestInit = {}, timeoutMs = 4000) {
        try {
            const response = await fetch(input, { ...options, signal: AbortSignal.timeout(timeoutMs) });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            return response;
        } catch (error) {
            const reason = error instanceof Error && /^HTTP \d+$/.test(error.message) ? error.message : 'network/timeout';
            this.logger.warn(`Geocoder ${new URL(input).hostname}: ${reason}`);
            throw error;
        }
    }

    private nominatimUrl: string;
    private osrmUrl: string;
    private yandexGeocoderApiKey?: string;
    private readonly addressSearchRadiusKm = 50;

    constructor(
        private prisma: PrismaService,
        private configService: ConfigService,
        @Optional() private kzAddresses?: KazakhstanAddressIndex,
    ) {
        this.nominatimUrl = this.configService.get('NOMINATIM_URL') || 'https://nominatim.openstreetmap.org';
        this.osrmUrl = (this.configService.get('OSRM_URL') || 'https://router.project-osrm.org').replace(/^http:/, 'https:');
        this.yandexGeocoderApiKey =
            this.configService.get<string>('YANDEX_GEOCODER_API_KEY')?.trim() || undefined;
    }

    async reverseGeocode(lat: number, lng: number) {
        const nearestCity = await this.findNearestCity(lat, lng);
        try {
            const response = await this.fetchGeo(
                `${this.nominatimUrl}/reverse?lat=${lat}&lon=${lng}&format=json&addressdetails=1&accept-language=ru`,
                {
                    headers: {
                        'User-Agent': 'INTERCITY/1.0',
                    },
                }
            );
            const data = await response.json();
            const addressParts = data?.address || {};
            const rawCity = this.extractCity(addressParts);
            const reportedCountry = (addressParts.country_code || '').toUpperCase();
            const matchedCity = rawCity ? cityCatalog.find(entry => entry.countryCode === reportedCountry &&
                [entry.name, ...entry.aliases].some(name => this.matchesReverseCityName(name, rawCity)) &&
                this.haversine(lat, lng, entry.lat, entry.lng) < 50) : null;
            const knownCity = rawCity ? GeoService.fallbackCities.find(entry => countryCodeFromRegion(entry.region) === reportedCountry && this.matchesReverseCityName(entry.name, rawCity) && this.haversine(lat, lng, entry.lat, entry.lng) < 50) : null;
            const city = knownCity?.name || matchedCity?.name || rawCity || nearestCity?.name || null;
            const region = this.extractRegion(addressParts) || nearestCity?.region || null;
            const countryCode = (addressParts.country_code || nearestCity?.countryCode || countryCodeFromRegion(region)).toUpperCase();
            const verifiedAddress = verifiedAddresses.find(entry => entry.countryCode === countryCode && this.haversine(lat, lng, entry.lat, entry.lng) <= 0.002);
            const displayAddress = verifiedAddress?.displayName || this.buildReverseAddress(data, nearestCity);

            // Try to find city in database
            let cityRecord = nearestCity;
            if (city) {
                if (!cityRecord?.id || cityRecord.name.toLowerCase() !== city.toLowerCase() || cityRecord.countryCode !== countryCode) {
                    cityRecord = await this.prisma.city.findFirst({
                        where: {
                            name: { equals: city, mode: 'insensitive' },
                            lat:{gte:lat-.5,lte:lat+.5},lng:{gte:lng-.5,lte:lng+.5},
                            countryCode,
                            isActive: true,
                        },
                    });
                }
                if (!cityRecord) {
                    cityRecord = await this.prisma.city.create({
                        data: {
                            name: city,
                            region,
                            countryCode,
                            lat,
                            lng,
                            isActive: true,
                        },
                    }).catch(async () => {
                        return this.prisma.city.findFirst({
                            where: {
                                name: { equals: city, mode: 'insensitive' },
                                countryCode,
                                isActive: true,
                            },
                        });
                    });
                }
            }

            return {
                city: city || 'Unknown',
                cityId: cityRecord?.id || null,
                countryCode: cityRecord?.countryCode || countryCode,
                currency: currencyForCountry(cityRecord?.countryCode || countryCode),
                address: displayAddress,
                cityResolved: Boolean(rawCity),
                addressResolved: Boolean(verifiedAddress || addressParts.road || addressParts.house_number || addressParts.pedestrian || addressParts.amenity),
                lat,
                lng,
            };
        } catch (error) {
            return {
                city: nearestCity?.name || 'Unknown',
                cityId: nearestCity?.id || null,
                countryCode: nearestCity?.countryCode || 'KZ',
                currency: currencyForCountry(nearestCity?.countryCode),
                address: this.buildNearestCityAddress(nearestCity),
                cityResolved: false,
                addressResolved: false,
                lat,
                lng,
            };
        }
    }

    async departureCurrency(lat?: number | null, lng?: number | null, cityName?: string | null) {
        const name = (cityName || '').split(',')[0].trim();
        const city = name ? await this.prisma.city.findFirst({
            where: { name: { equals: name, mode: 'insensitive' }, isActive: true },
        }) : null;
        if (city) return currencyForCountry(city.countryCode);
        const fallback = GeoService.fallbackCities.find(item => item.name.toLowerCase() === name.toLowerCase());
        if (fallback) return currencyForCountry(countryCodeFromRegion(fallback.region));
        if (Number.isFinite(lat) && Number.isFinite(lng)) {
            return (await this.reverseGeocode(lat!, lng!)).currency;
        }
        return currencyForCountry(countryCodeFromRegion(cityName));
    }

    private extractCity(address: any) {
        return address?.city || address?.town || address?.village || address?.county || null;
    }

    private extractRegion(address: any) {
        return address?.state || address?.region || null;
    }

    private buildReverseAddress(data: any, nearestCity?: { id: string; name: string; region: string | null; lat: number; lng: number } | null) {
        const displayName = typeof data?.display_name === 'string' ? data.display_name.trim() : '';
        if (displayName && !this.looksLikeCoordinates(displayName)) {
            return displayName;
        }

        const address = data?.address || {};
        const parts = [
            address?.road,
            address?.house_number,
            address?.suburb,
            address?.neighbourhood,
            this.extractCity(address),
            this.extractRegion(address),
        ]
            .map((part: unknown) => typeof part === 'string' ? part.trim() : '')
            .filter((part: string, index: number, arr: string[]) => part && arr.indexOf(part) === index);

        if (parts.length > 0) {
            return parts.join(', ');
        }

        return this.buildNearestCityAddress(nearestCity);
    }

    private buildNearestCityAddress(nearestCity?: { id: string; name: string; region: string | null; lat: number; lng: number } | null) {
        if (!nearestCity) {
            return 'Адрес уточняется';
        }
        if (nearestCity.region) {
            return `${nearestCity.name}, ${nearestCity.region}`;
        }
        return nearestCity.name;
    }

    private looksLikeCoordinates(value: string) {
        return /^-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?$/.test(value.trim());
    }

    private async findNearestCity(lat: number, lng: number) {
        const cities = await this.activeCitySearchRows();

        let nearest: (typeof cities)[number] | null = null;
        let nearestDistance = Number.POSITIVE_INFINITY;
        for (const city of cities) {
            const distance = this.haversine(lat, lng, city.lat, city.lng);
            if (distance < nearestDistance) {
                nearestDistance = distance;
                nearest = city;
            }
        }
        return nearestDistance < 50 ? nearest : null;
    }

    async listActiveCities() {
        return this.prisma.city.findMany({
            where: { isActive: true },
            select: {
                id: true,
                name: true,
                aliases:true,
                region: true,
                countryCode: true,
                lat: true,
                lng: true,
            },
            orderBy: [
                { name: 'asc' },
            ],
        });
    }

    private citySearchSnapshot?: {expires:number; rows:any[]; exact:Map<string,any[]>};
    private citySnapshotRequest?: Promise<any[]>;
    private async activeCitySearchRows():Promise<any[]> {
        if (this.citySearchSnapshot && this.citySearchSnapshot.expires>Date.now()) return this.citySearchSnapshot.rows;
        if (this.citySnapshotRequest) return this.citySnapshotRequest;
        this.citySnapshotRequest=this.prisma.city.findMany({where:{isActive:true},
            select:{id:true,name:true,aliases:true,region:true,countryCode:true,lat:true,lng:true}}).then(rows=>{
            const exact=new Map<string,any[]>();
            for(const city of rows) {
                const entry:any=city;
                entry.searchTokens=[...new Set([entry.name,...(entry.aliases || [])].map(name=>this.normalizeCityToken(name)))];
                for(const key of entry.searchTokens) {const values=exact.get(key)||[];values.push(entry);exact.set(key,values);}
            }
            this.citySearchSnapshot={expires:Date.now()+30000,rows,exact};return rows;
        }).finally(()=>{this.citySnapshotRequest=undefined;});
        return this.citySnapshotRequest;
    }
    async searchCities(query: string) {
        const needle = this.normalizeCityToken((query || '').trim());
        if (needle.length < 2) return [];
        const rows = await this.activeCitySearchRows();
        let matches = this.citySearchSnapshot!.exact.get(needle) || rows.filter(city => city.searchTokens.some(name => name.includes(needle)));
        if (!matches.length && needle.length >= 4) {
            matches = rows.filter(city => [city.name,...(city.aliases || [])].some(name => this.isNearCityPrefix(this.normalizeCityToken(name),needle)));
        }
        return this.rankCityResults(matches.map(city => ({...city,
            displayName:[city.name,city.region,city.countryCode==='RU'?'Россия':'Казахстан'].filter(Boolean).join(', '),
            currency:currencyForCountry(city.countryCode),
        })),query).map(({aliases,searchTokens,...city})=>city);
    }

    private readonly addressCache = new Map<string, {expires: number; results: Array<{displayName: string; lat: number; lng: number}>}>();
    private readonly addressRequests = new Map<string, Promise<Array<{displayName: string; lat: number; lng: number}>>>();

    async searchLocations(query: string, nearLat?: number, nearLng?: number, cityId?: string) {
        const key = JSON.stringify([this.normalizeCityToken(query || ''), nearLat, nearLng, cityId]);
        const cached = this.addressCache.get(key);
        if (cached && cached.expires > Date.now()) return cached.results;
        if (cached) this.addressCache.delete(key);
        const pending = this.addressRequests.get(key);
        if (pending) return pending;
        const request = this.searchLocationsUncached(query, nearLat, nearLng, cityId)
            .then(results => {
                // Preserve successful suggestions during transient provider failures.
                // Empty responses must never make a later successful search disappear.
                if (results.length > 0) {
                    if (this.addressCache.size >= 500) this.addressCache.delete(this.addressCache.keys().next().value);
                    this.addressCache.set(key, {expires: Date.now() + 5 * 60 * 1000, results});
                }
                return results;
            }).finally(() => this.addressRequests.delete(key));
        this.addressRequests.set(key, request);
        return request;
    }

    private async searchLocationsUncached(query: string, nearLat?: number, nearLng?: number, cityId?: string) {
        try {
            const cityContext = cityId
                ? await this.prisma.city.findFirst({
                    where: { id: cityId, isActive: true },
                    select: {
                        id: true,
                        name: true,
                        region: true,
                        countryCode: true,
                        lat: true,
                        lng: true,
                    },
                })
                : Number.isFinite(nearLat) && Number.isFinite(nearLng)
                    ? await this.findNearestCity(nearLat!, nearLng!)
                    : null;
            const verified = this.findVerifiedAddresses(query, cityContext || undefined)
                .filter(address => !Number.isFinite(nearLat) || !Number.isFinite(nearLng) ||
                    this.haversine(nearLat!, nearLng!, address.lat, address.lng) <= this.addressSearchRadiusKm);
            if (verified.length > 0) return verified;
            if (this.kzAddresses && cityContext) {
                const indexed = await this.kzAddresses.search(query, {
                    countryCode:cityContext.countryCode,
                    lat:Number.isFinite(nearLat)?nearLat!:cityContext.lat,
                    lng:Number.isFinite(nearLng)?nearLng!:cityContext.lng,
                }).catch(() => []);
                const nearby = indexed.filter(item => this.haversine(cityContext.lat,cityContext.lng,item.lat,item.lng)<=this.addressSearchRadiusKm);
                if (nearby.length > 0) return nearby.slice(0,10);
            }
            const context = cityContext ? { city: cityContext.name, region: cityContext.region, countryCode: cityContext.countryCode.toLowerCase() } : Number.isFinite(nearLat) && Number.isFinite(nearLng)
                ? await this.getSearchContext(nearLat!, nearLng!)
                : null;
            const queries = [
                this.combineQuery(query, cityContext?.name || context?.city),
                this.combineQuery(query.replace(/[,\s]+\d+[\p{L}\d\/\-]*\s*$/u, ''), cityContext?.name || context?.city),
            ].filter((value, index, arr): value is string => Boolean(value?.trim()) && arr.indexOf(value) === index);
            const photonRequest = cityContext
                ? this.fetchPhotonSearchResults(query, cityContext).catch(() => [])
                : Promise.resolve([]);
            const yandexRequest = cityContext && this.yandexGeocoderApiKey
                ? this.fetchYandexSearchResults(queries[0], cityContext).catch(() => [])
                : Promise.resolve([]);

            const collected: Array<{ displayName: string; lat: number; lng: number }> = [];
            const seen = new Set<string>();

            for (const candidate of queries) {
                const data = await this.fetchSearchResults(
                    candidate,
                    context?.countryCode,
                    cityContext || undefined,
                ).catch(() => []);
                for (const item of data) {
                    const mapped = {
                        houseNumber: item.address?.house_number || null,
                        road: item.address?.road || null,
                        displayName: item.display_name,
                        lat: parseFloat(item.lat),
                        lng: parseFloat(item.lon),
                    };
                    if (!Number.isFinite(mapped.lat) || !Number.isFinite(mapped.lng)) {
                        continue;
                    }
                    const key = `${mapped.lat}:${mapped.lng}:${mapped.displayName}`;
                    if (seen.has(key)) continue;
                    seen.add(key);
                    collected.push(mapped);
                }
                if (collected.length >= 6 || collected.some((item: any) => item.road && item.houseNumber)) break;
            }
            for (const item of await photonRequest) {
                const key = `${item.lat}:${item.lng}:${item.displayName}`;
                if (!seen.has(key)) { seen.add(key); collected.push(item); }
            }

            for (const item of await yandexRequest) {
                const key = `${item.lat}:${item.lng}:${item.displayName}`;
                if (!seen.has(key)) { seen.add(key); collected.push(item); }
            }

            const house = query.match(/(?:^|\s)(\d+[\p{L}]?(?:\/\d+[\p{L}]?)?)(?:\s|$)/u)?.[1]?.toLowerCase();
            const addressRank = (item: any) => {
                if (!house) return item.road ? 0 : 2;
                const number = (item.houseNumber || '').toLowerCase();
                return number === house ? 0 : number.startsWith(house) && !/^\d/.test(number.slice(house.length)) && item.road ? 1 : item.road && !number ? 2 : 3;
            };
            const items = collected;
            if (Number.isFinite(nearLat) && Number.isFinite(nearLng)) {
                return items
                    .map((item: any) => ({
                        ...item,
                        distanceKm: this.haversine(nearLat!, nearLng!, item.lat, item.lng),
                    }))
                    .filter((item: any) => item.distanceKm <= this.addressSearchRadiusKm)
                    .sort((a: any, b: any) => addressRank(a) - addressRank(b) || a.distanceKm - b.distanceKm)
                    .slice(0, 10);
            }
            return items.sort((a,b) => addressRank(a)-addressRank(b)).slice(0, 10);
        } catch (error) {
            return [];
        }
    }

    private async fetchCitySearchResults(query: string) {
        const url = new URL(`${this.nominatimUrl}/search`);
        url.searchParams.set('q', query);
        url.searchParams.set('format', 'json');
        url.searchParams.set('limit', '20');
        url.searchParams.set('addressdetails', '1');
        url.searchParams.set('accept-language', 'ru');
        url.searchParams.set('featuretype', 'city');
        url.searchParams.set('countrycodes', 'kz,ru');

        const response = await this.fetchGeo(url.toString(), {
            headers: { 'User-Agent': 'INTERCITY/1.0' },
        });
        const data = await response.json();
        if (!Array.isArray(data)) return [];
        return data
            .map((item: any) => {
                const lat = Number.parseFloat(item?.lat);
                const lng = Number.parseFloat(item?.lon);
                if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
                const address = item?.address || {};
                const name = this.extractCity(address) ||
                    (typeof item?.name === 'string' ? item.name : '') ||
                    this.firstDisplayNamePart(item?.display_name);
                const region = this.extractRegion(address);
                const displayName = [name, region, address?.country]
                    .map((value: unknown) => typeof value === 'string' ? value.trim() : '')
                    .filter(Boolean)
                    .join(', ') || item?.display_name || `${lat}, ${lng}`;
                return { displayName, name, region, lat, lng, countryCode: address.country_code?.toUpperCase() };
            })
            .filter((item: any): item is { displayName: string; lat: number; lng: number; name?: string; region?: string | null; countryCode?: string; currency?: string } => item !== null);
    }

    private async fetchYandexCitySearchResults(query: string) {
        if (!this.yandexGeocoderApiKey) return [];
        const url = new URL('https://geocode-maps.yandex.ru/v1');
        url.searchParams.set('apikey', this.yandexGeocoderApiKey);
        url.searchParams.set('geocode', query);
        url.searchParams.set('lang', 'ru_RU');
        url.searchParams.set('format', 'json');
        url.searchParams.set('results', '10');
        url.searchParams.set('kind', 'locality');

        const response = await this.fetchGeo(url.toString(), {
            headers: { 'User-Agent': 'INTERCITY/1.0' },
        });
        const data = await response.json();
        const members = data?.response?.GeoObjectCollection?.featureMember;
        if (!Array.isArray(members)) return [];

        return members
            .map((member: any) => {
                const mapped = this.mapYandexFeature(member?.GeoObject);
                if (!mapped) return null;
                const feature = member?.GeoObject;
                const name = typeof feature?.name === 'string' ? feature.name.trim() : this.firstDisplayNamePart(mapped.displayName);
                const region = typeof feature?.description === 'string' ? feature.description.trim() : null;
                return {
                    ...mapped,
                    displayName: [name, region].filter(Boolean).join(', ') || mapped.displayName,
                    name,
                    region,
                };
            })
            .filter((item: any): item is { displayName: string; lat: number; lng: number; name?: string; region?: string | null; countryCode?: string; currency?: string } => item !== null);
    }

    private firstDisplayNamePart(value: unknown) {
        if (typeof value !== 'string') return '';
        return value.split(',')[0]?.trim() || '';
    }

    private looksLikeLocalityResult(item: { displayName: string; name?: string; region?: string | null; countryCode?: string; currency?: string }) {
        const name = this.normalizeCityToken(item.name || this.firstDisplayNamePart(item.displayName));
        const display = this.normalizeCityToken(item.displayName);
        if (!name || this.looksLikeCoordinates(name)) return false;
        if (/район|округ|область|администраци|поселковый совет|сельсовет/.test(name)) return false;
        const addressWords = [
            'улица', 'ул ', 'проспект', 'пр-т', 'переулок', 'дом',
            'микрорайон', 'мкр', 'шоссе', 'площадь', 'просп',
        ];
        return !addressWords.some((word) => name.includes(word) || display.startsWith(`${word} `));
    }

    private nominatimSearchRetryAt = 0;

    private async fetchSearchResults(
        query: string,
        countryCode?: string,
        cityContext?: { id: string; name: string; region: string | null; lat: number; lng: number },
    ) {
        if (Date.now() < this.nominatimSearchRetryAt) return [];
        const url = new URL(`${this.nominatimUrl}/search`);
        url.searchParams.set('q', query);
        url.searchParams.set('format', 'json');
        url.searchParams.set('limit', '20');
        url.searchParams.set('addressdetails', '1');
        url.searchParams.set('accept-language', 'ru');
        if (countryCode) {
            url.searchParams.set('countrycodes', countryCode);
        }
        if (cityContext) {
            const viewBox = this.buildCityViewBox(cityContext);
            url.searchParams.set('viewbox', [
                viewBox.west,
                viewBox.north,
                viewBox.east,
                viewBox.south,
            ].join(','));
            url.searchParams.set('bounded', '1');
        }
        const response = await this.fetchGeo(url.toString(), {
            headers: { 'User-Agent': 'INTERCITY/1.0' },
        }).catch(error => {
            if (error instanceof Error && /HTTP (429|403)/.test(error.message)) this.nominatimSearchRetryAt = Date.now() + 60000;
            throw error;
        });
        const data = await response.json();
        if (!Array.isArray(data)) return [];
        if (!cityContext) return data;
        return data.filter((item: any) => this.belongsToCityContext(item, cityContext));
    }

    private async fetchPhotonSearchResults(query: string, city: {name: string; countryCode?: string; lat: number; lng: number}) {
        const url = new URL(`${this.configService.get('PHOTON_URL') || 'https://photon.komoot.io'}/api/`);
        url.searchParams.set('q', query.trim());
        url.searchParams.set('limit', '15');
        url.searchParams.set('lat', String(city.lat));
        url.searchParams.set('lon', String(city.lng));
        const box = this.buildCityViewBox(city);
        url.searchParams.set('bbox', `${box.west},${box.south},${box.east},${box.north}`);
        const response = await this.fetchGeo(url.toString());
        const data = await response.json();
        return (Array.isArray(data.features) ? data.features : []).flatMap((feature: any) => {
            const p = feature.properties || {};
            const c = feature.geometry?.coordinates;
            if (!Array.isArray(c) || !Number.isFinite(c[0]) || !Number.isFinite(c[1])) return [];
            if (city.countryCode && p.countrycode?.toUpperCase() !== city.countryCode.toUpperCase()) return [];
            const displayName = [...new Set([p.name, p.street, p.housenumber, p.city, p.country].filter(Boolean))].join(', ');
            const item = {display_name: displayName, address: {city:p.city, town:p.town, road:p.street, country_code:p.countrycode}};
            if (!this.belongsToCityContext(item, city)) return [];
            if (this.haversine(city.lat, city.lng, c[1], c[0]) > this.addressSearchRadiusKm) return [];
            return [{displayName, lat:c[1], lng:c[0], houseNumber:p.housenumber || null,
                road:p.street || (p.osm_key === 'highway' ? p.name : null), source:'photon'}];
        });
    }

    private buildCityViewBox(
        cityContext: { lat: number; lng: number; name: string }
    ) {
        const radiusKm = this.citySearchRadiusKm(cityContext.name);
        const latDelta = radiusKm / 111;
        const lngDivider = Math.max(0.25, Math.cos((cityContext.lat * Math.PI) / 180));
        const lngDelta = radiusKm / (111 * lngDivider);
        return {
            west: cityContext.lng - lngDelta,
            east: cityContext.lng + lngDelta,
            north: cityContext.lat + latDelta,
            south: cityContext.lat - latDelta,
        };
    }

    private citySearchRadiusKm(cityName: string) {
        return this.addressSearchRadiusKm;
    }

    private async fetchYandexSearchResults(
        query: string,
        cityContext: { id: string; name: string; region: string | null; lat: number; lng: number },
    ): Promise<Array<{ displayName: string; lat: number; lng: number }>> {
        if (!this.yandexGeocoderApiKey) {
            return [];
        }

        const viewBox = this.buildCityViewBox(cityContext);
        const url = new URL('https://geocode-maps.yandex.ru/v1');
        url.searchParams.set('apikey', this.yandexGeocoderApiKey);
        url.searchParams.set('geocode', query);
        url.searchParams.set('lang', 'ru_RU');
        url.searchParams.set('format', 'json');
        url.searchParams.set('results', '10');
        url.searchParams.set(
            'bbox',
            `${viewBox.west},${viewBox.south}~${viewBox.east},${viewBox.north}`,
        );
        url.searchParams.set('rspn', '1');

        const response = await this.fetchGeo(url.toString(), {
            headers: {
                'User-Agent': 'INTERCITY/1.0',
            },
        });
        const data = await response.json();
        const members = data?.response?.GeoObjectCollection?.featureMember;
        if (!Array.isArray(members)) {
            return [];
        }

        return members
            .map((member: any) => this.mapYandexFeature(member?.GeoObject))
            .filter((item: { displayName: string; lat: number; lng: number } | null): item is { displayName: string; lat: number; lng: number } =>
                item !== null,
            );
    }

    private mapYandexFeature(feature: any) {
        const pos = typeof feature?.Point?.pos === 'string'
            ? feature.Point.pos.trim().split(/\s+/)
            : [];
        if (pos.length !== 2) {
            return null;
        }

        const lng = Number.parseFloat(pos[0]);
        const lat = Number.parseFloat(pos[1]);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
            return null;
        }

        const address =
            feature?.metaDataProperty?.GeocoderMetaData?.Address?.formatted;
        const name = typeof feature?.name === 'string' ? feature.name.trim() : '';
        const description =
            typeof feature?.description === 'string' ? feature.description.trim() : '';
        const displayName =
            [address, name, description]
                .map((value: unknown) => (typeof value === 'string' ? value.trim() : ''))
                .find((value: string) => value.length > 0) || `${lat}, ${lng}`;

        const components = feature?.metaDataProperty?.GeocoderMetaData?.Address?.Components;
        const part = (kind: string) => Array.isArray(components) ? components.find((c: any) => c.kind === kind)?.name || null : null;
        return {
            displayName,
            lat,
            lng,
            houseNumber: part('house'),
            road: part('street'),
            countryCode: feature?.metaDataProperty?.GeocoderMetaData?.Address?.country_code?.toUpperCase(),
        };
    }

    private belongsToCityContext(
        item: any,
        cityContext: { name: string }
    ) {
        const normalizedContext = this.normalizeLocalityName(cityContext.name);
        if (!normalizedContext) return true;

        const address = item?.address || {};
        const cityTokens = [
            this.extractCity(address),
            address?.municipality,
            address?.suburb,
        ]
            .map((value: unknown) => this.normalizeLocalityName(typeof value === 'string' ? value : ''))
            .filter((value: string) => value.length > 0);

        if (cityTokens.some((token) => token === normalizedContext)) {
            return true;
        }

        if (typeof item?.display_name !== 'string') {
            return false;
        }

        const displayTokens = item.display_name
            .split(',')
            .map((value: string) => this.normalizeLocalityName(value))
            .filter((value: string) => value.length > 0);
        return displayTokens.some((token: string) => token === normalizedContext);
    }

    private findVerifiedAddresses(query: string, city?: {name: string; lat: number; lng: number}) {
        const normalized = this.normalizeCityToken(query)
            .replace(/(?:^|\s)(?:улица|ул\.|проспект|пр-т|пр\.|дом|д\.)(?=\s|$)/gu, ' ')
            .replace(/\s*\/\s*/g, '/')
            .replace(/[,]/g, ' ').replace(/\s+/g, ' ').trim();
        const house = normalized.match(/(?:^|\s)(\d+[\p{L}]?(?:\/\d+[\p{L}]?)?)(?:\s|$)/u)?.[1];
        const street = normalized.replace(/(?:^|\s)\d+[\p{L}]?(?:\/\d+[\p{L}]?)?(?:\s|$)/gu, ' ').trim();
        if (street.length < 3) return [];
        return verifiedAddresses.filter(address => {
            if (house && house !== address.house && !(address.house.startsWith(house) && /^[\p{L}]$/u.test(address.house.slice(house.length)))) return false;
            if (city && this.haversine(city.lat, city.lng, address.lat, address.lng) > this.addressSearchRadiusKm) return false;
            return address.streetAliases.some(alias => alias.includes(street));
        }).map(address => ({
            displayName: address.displayName, lat: address.lat, lng: address.lng,
            countryCode: address.countryCode, source: address.source,
        }));
    }

    private matchesReverseCityName(name: string, rawCity: string) {
        const expected = this.normalizeLocalityName(name);
        const actual = this.normalizeLocalityName(rawCity);
        return expected === actual || (/городская администрация/iu.test(rawCity) && actual === `${expected}а`);
    }

    private static localityAliases: Map<string, string>;

    private normalizeLocalityName(value: string) {
        const normalized = this.normalizeCityToken(value)
            .replace(/^(городская администрация|городской округ|город|г\.)\s+/u, '')
            .replace(/\s+городская администрация$/u, '');
        if (!GeoService.localityAliases) {
            const aliases = new Map<string, string>();
            const preferred = new Map(GeoService.fallbackCities.map(city => [this.normalizeCityToken(city.name), city]));
            for (const city of cityCatalog) {
                const names = [city.name, ...city.aliases].map(name => this.normalizeCityToken(name));
                const known = names.map(name => preferred.get(name)).find(item => item && countryCodeFromRegion(item.region) === city.countryCode);
                const canonical = this.normalizeCityToken(known?.name || city.name);
                for (const name of names) if (!aliases.has(name)) aliases.set(name, canonical);
            }
            for (const name of preferred.keys()) aliases.set(name, name);
            GeoService.localityAliases = aliases;
        }
        return GeoService.localityAliases.get(normalized) || normalized;
    }

    private rankCityResults<T extends {name?: string; displayName: string}>(items: T[], query: string): T[] {
        const needle = this.normalizeCityToken(query);
        const score = (city: T) => {
            const name = this.normalizeCityToken(city.name || city.displayName);
            return name === needle ? 0 : name.startsWith(needle) ? 1 : 2;
        };
        return items.sort((a, b) => score(a) - score(b) || (a.name || a.displayName).localeCompare(b.name || b.displayName, 'ru')).slice(0, Math.max(12,Math.min(200,items.filter(city=>this.normalizeCityToken(city.name || city.displayName)===needle).length)));
    }

    private isNearCityPrefix(name: string, query: string) {
        const oneEdit = (a: string, b: string) => {
            if (Math.abs(a.length - b.length) > 1) return false;
            let i=0, j=0, edits=0;
            while (i<a.length && j<b.length) {
                if (a[i] === b[j]) { i++; j++; continue; }
                if (++edits > 1) return false;
                if (a.length >= b.length) i++;
                if (b.length >= a.length) j++;
            }
            return edits + (a.length-i) + (b.length-j) <= 1;
        };
        return [query.length-1, query.length, query.length+1].some(length => oneEdit(name.slice(0,length),query));
    }

    private normalizeCityToken(value: string) {
        return value
            .trim()
            .toLowerCase()
            .replaceAll('ё', 'е')
            .replace(/[‐‑–—-]+/g, ' ').replace(/\s+/g, ' ');
    }

    private async getSearchContext(lat: number, lng: number) {
        try {
            const response = await this.fetchGeo(
                `${this.nominatimUrl}/reverse?lat=${lat}&lon=${lng}&format=json&addressdetails=1&accept-language=ru`,
                {
                    headers: {
                        'User-Agent': 'INTERCITY/1.0',
                    },
                }
            );
            const data = await response.json();
            const address = data?.address || {};
            return {
                city: address.city || address.town || address.village || address.county || null,
                region: address.state || address.region || null,
                countryCode: typeof address.country_code === 'string'
                    ? address.country_code.toLowerCase()
                    : undefined,
            };
        } catch (_) {
            return null;
        }
    }

    private combineQuery(query: string, city?: string | null, region?: string | null) {
        const parts = [query.trim(), city?.trim(), region?.trim()].filter(Boolean);
        if (parts.length === 0) return null;
        return parts.join(', ');
    }

    private readonly routeCache = new Map<string, {expires: number; route: any}>();
    private readonly routeRequests = new Map<string, Promise<any>>();

    async getRoute(fromLat: number, fromLng: number, toLat: number, toLng: number) {
        if (![fromLat, fromLng, toLat, toLng].every(Number.isFinite) || Math.abs(fromLat)>90 || Math.abs(toLat)>90 || Math.abs(fromLng)>180 || Math.abs(toLng)>180) {
            throw new BadRequestException('Invalid route coordinates');
        }
        const key = [fromLat, fromLng, toLat, toLng].join(':');
        const cached = this.routeCache.get(key);
        if (cached && cached.expires > Date.now()) return cached.route;
        const pending = this.routeRequests.get(key);
        if (pending) return pending;
        const request = this.loadRoadRoute(fromLat, fromLng, toLat, toLng).then(route => {
            if (this.routeCache.size >= 500) this.routeCache.delete(this.routeCache.keys().next().value);
            this.routeCache.set(key, {expires:Date.now()+300000,route});
            return route;
        }).finally(() => this.routeRequests.delete(key));
        this.routeRequests.set(key, request);
        return request;
    }

    private async loadRoadRoute(fromLat: number, fromLng: number, toLat: number, toLng: number) {
        const providers = [...new Set([this.osrmUrl, this.configService.get('OSRM_FALLBACK_URL') || 'https://routing.openstreetmap.de/routed-car'])];
        for (const provider of providers) {
          try {
            const response = await this.fetchGeo(
                `${provider.replace(/\/$/, '')}/route/v1/driving/${fromLng},${fromLat};${toLng},${toLat}?overview=full&geometries=geojson&steps=true&alternatives=false`, {}, 8000
            );
            const data = await response.json();
            if (data.code === 'Ok' && data.routes && data.routes.length > 0) {
                const route = data.routes[0];
                const coords = route.geometry?.coordinates;
                if (route.geometry?.type !== 'LineString' || !Array.isArray(coords) || coords.length < 2 ||
                    !coords.every((c: any) => Array.isArray(c) && Number.isFinite(c[0]) && Number.isFinite(c[1]) && Math.abs(c[0]) <= 180 && Math.abs(c[1]) <= 90) ||
                    !Number.isFinite(route.distance) || route.distance < 0 || !Number.isFinite(route.duration) || route.duration < 0) throw new Error('Invalid road route');
                const steps = Array.isArray(route.legs)
                    ? route.legs.flatMap((leg: any) =>
                        Array.isArray(leg.steps)
                            ? leg.steps.map((step: any) => ({
                                distance: step.distance,
                                duration: step.duration,
                                name: step.name || '',
                                mode: step.mode || null,
                                maneuver: {
                                    type: step.maneuver?.type || null,
                                    modifier: step.maneuver?.modifier || null,
                                    bearingBefore: step.maneuver?.bearing_before ?? null,
                                    bearingAfter: step.maneuver?.bearing_after ?? null,
                                    location: Array.isArray(step.maneuver?.location)
                                        ? step.maneuver.location
                                        : null,
                                },
                            }))
                            : []
                    )
                    : [];
                return {
                    distance: route.distance / 1000, // km
                    duration: Math.round(route.duration / 60), // minutes
                    geometry: route.geometry,
                    steps,
                };
            }
          } catch (_) { /* Try the independent road router. Never estimate a road fare by air distance. */ }
        }
        throw new ServiceUnavailableException({code:'ROAD_ROUTE_UNAVAILABLE', message:'Не удалось построить маршрут по дорогам. Повторите попытку.'});
    }

    haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {
        const R = 6371;
        const dLat = this.toRad(lat2 - lat1);
        const dLng = this.toRad(lng2 - lng1);
        const a =
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(this.toRad(lat1)) * Math.cos(this.toRad(lat2)) *
            Math.sin(dLng / 2) * Math.sin(dLng / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    private toRad(deg: number): number {
        return deg * (Math.PI / 180);
    }
}
