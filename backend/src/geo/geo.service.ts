import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma.service';
import { verifiedAddresses } from './verified-addresses';
import { cityCatalog } from './city-catalog';
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

    private async fetchGeo(input: string, options: RequestInit = {}) {
        try {
            const response = await fetch(input, { ...options, signal: AbortSignal.timeout(4000) });
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
    ) {
        this.nominatimUrl = this.configService.get('NOMINATIM_URL') || 'https://nominatim.openstreetmap.org';
        this.osrmUrl = this.configService.get('OSRM_URL') || 'http://router.project-osrm.org';
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
                [entry.name, ...entry.aliases].some(name => this.normalizeCityToken(name) === this.normalizeCityToken(rawCity)) &&
                this.haversine(lat, lng, entry.lat, entry.lng) < 50) : null;
            const city = matchedCity?.name || rawCity || nearestCity?.name || null;
            const region = this.extractRegion(addressParts) || nearestCity?.region || null;
            const countryCode = (addressParts.country_code || nearestCity?.countryCode || countryCodeFromRegion(region)).toUpperCase();
            const displayAddress = this.buildReverseAddress(data, nearestCity);

            // Try to find city in database
            let cityRecord = nearestCity;
            if (city) {
                if (!cityRecord?.id || cityRecord.name.toLowerCase() !== city.toLowerCase() || cityRecord.countryCode !== countryCode) {
                    cityRecord = await this.prisma.city.findFirst({
                        where: {
                            name: { equals: city, mode: 'insensitive' },
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
                addressResolved: Boolean(addressParts.road || addressParts.house_number || addressParts.pedestrian || addressParts.amenity),
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
        const cities = await this.prisma.city.findMany({
            where: { isActive: true },
            select: {
                id: true,
                name: true,
                region: true,
                countryCode: true,
                lat: true,
                lng: true,
            },
        });

        let nearest: (typeof cities)[number] | null = null;
        let nearestDistance = Number.POSITIVE_INFINITY;
        for (const city of cities) {
            const distance = this.haversine(lat, lng, city.lat, city.lng);
            if (distance < nearestDistance) {
                nearestDistance = distance;
                nearest = city;
            }
        }
        for (const city of GeoService.fallbackCities) {
            const distance = this.haversine(lat, lng, city.lat, city.lng);
            if (distance < nearestDistance && distance < 50) {
                nearestDistance = distance;
                nearest = { ...city, id: null, countryCode: countryCodeFromRegion(city.region) };
            }
        }
        return nearestDistance < 100 ? nearest : null;
    }

    async listActiveCities() {
        return this.prisma.city.findMany({
            where: { isActive: true },
            select: {
                id: true,
                name: true,
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

    async searchCities(query: string) {
        const normalized = (query || '').trim();
        if (normalized.length < 2) return [];

        const collected: Array<{ displayName: string; lat: number; lng: number; name?: string; region?: string | null; countryCode?: string; currency?: string }> = [];
        const seen = new Set<string>();

        const addCity = (item: { displayName: string; lat: number; lng: number; name?: string; region?: string | null; countryCode?: string; currency?: string }, matchesAlias = false) => {
            if (!item.displayName || !Number.isFinite(item.lat) || !Number.isFinite(item.lng)) return;
            if (!this.looksLikeLocalityResult(item)) return;
            const name = this.normalizeCityToken(item.name || item.displayName);
            const needle = this.normalizeCityToken(normalized);
            if (!matchesAlias && !name.includes(needle)) return;
            const key = `${item.countryCode || countryCodeFromRegion(item.region)}:${name}`;
            if (seen.has(key)) return;
            seen.add(key);
            const countryCode = item.countryCode || countryCodeFromRegion(item.region);
            collected.push({ ...item, countryCode, currency: currencyForCountry(countryCode) });
        };

        GeoService.fallbackCities
            .filter((city) => {
                const needle = this.normalizeCityToken(normalized);
                const name = this.normalizeCityToken(city.name);
                const region = this.normalizeCityToken(city.region);
                return name.includes(needle) || region.includes(needle);
            })
            .sort((a, b) => {
                const needle = this.normalizeCityToken(normalized);
                const aStarts = this.normalizeCityToken(a.name).startsWith(needle);
                const bStarts = this.normalizeCityToken(b.name).startsWith(needle);
                if (aStarts !== bStarts) return aStarts ? -1 : 1;
                return a.name.localeCompare(b.name, 'ru');
            })
            .forEach((city) => addCity({
                displayName: `${city.name}, ${city.region}`,
                name: city.name,
                region: city.region,
                lat: city.lat,
                lng: city.lng,
            }));

        const dbCities = await this.prisma.city.findMany({
            where: {
                isActive: true,
                OR: [
                    { name: { contains: normalized, mode: 'insensitive' } },
                    { region: { contains: normalized, mode: 'insensitive' } },
                ],
            },
            select: { name: true, region: true, countryCode: true, lat: true, lng: true },
            take: 8,
        });
        dbCities.forEach((city) => addCity({
            displayName: [city.name, city.region].filter(Boolean).join(', '),
            name: city.name,
            region: city.region,
            countryCode: city.countryCode,
            lat: city.lat,
            lng: city.lng,
        }));

        const needle = this.normalizeCityToken(normalized);
        cityCatalog
            .filter(city => [city.name, ...city.aliases].some(name => this.normalizeCityToken(name).includes(needle)))
            .sort((a, b) => Number(this.normalizeCityToken(b.name).startsWith(needle)) - Number(this.normalizeCityToken(a.name).startsWith(needle)))
            .forEach(city => addCity({ ...city, displayName: `${city.name}, ${city.countryCode === 'KZ' ? 'Казахстан' : 'Россия'}` }, true));
        if (collected.length > 0) return this.rankCityResults(collected, normalized);

        try {
            const osmCities = await this.fetchCitySearchResults(normalized);
            osmCities.forEach(city => addCity(city));
        } catch (_) { }

        if (collected.length < 6 && this.yandexGeocoderApiKey) {
            try {
                const yandexCities = await this.fetchYandexCitySearchResults(normalized);
                yandexCities.forEach(city => addCity(city));
            } catch (_) { }
        }

        return this.rankCityResults(collected, normalized);
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
            const context = cityContext ? { city: cityContext.name, region: cityContext.region, countryCode: cityContext.countryCode.toLowerCase() } : Number.isFinite(nearLat) && Number.isFinite(nearLng)
                ? await this.getSearchContext(nearLat!, nearLng!)
                : null;
            const queries = [
                this.combineQuery(query, cityContext?.name || context?.city),
                query.trim(),
                this.combineQuery(query, cityContext?.name || context?.city, cityContext?.region || context?.region),
                this.combineQuery(query.replace(/[,\s]+\d+[\p{L}\d\/\-]*\s*$/u, ''), cityContext?.name || context?.city),
            ].filter((value, index, arr): value is string =>
                Boolean(value && value.trim()) && arr.indexOf(value) === index
            );

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
                if (collected.length >= 10) break;
            }

            if (collected.length < 6 && cityContext && this.yandexGeocoderApiKey) {
                for (const candidate of queries) {
                    const data = await this.fetchYandexSearchResults(
                        candidate,
                        cityContext,
                    ).catch(() => []);
                    for (const item of data) {
                        const key = `${item.lat}:${item.lng}:${item.displayName}`;
                        if (seen.has(key)) continue;
                        seen.add(key);
                        collected.push(item);
                    }
                    if (collected.length >= 10) break;
                }
            }

            const items = collected;
            if (Number.isFinite(nearLat) && Number.isFinite(nearLng)) {
                return items
                    .map((item: any) => ({
                        ...item,
                        distanceKm: this.haversine(nearLat!, nearLng!, item.lat, item.lng),
                    }))
                    .filter((item: any) => item.distanceKm <= this.addressSearchRadiusKm)
                    .sort((a: any, b: any) => a.distanceKm - b.distanceKm)
                    .slice(0, 10);
            }
            return items.slice(0, 10);
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

    private async fetchSearchResults(
        query: string,
        countryCode?: string,
        cityContext?: { id: string; name: string; region: string | null; lat: number; lng: number },
    ) {
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
            headers: {
                'User-Agent': 'INTERCITY/1.0',
            },
        });
        const data = await response.json();
        if (!Array.isArray(data)) return [];
        if (!cityContext) return data;
        return data.filter((item: any) => this.belongsToCityContext(item, cityContext));
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

        return {
            displayName,
            lat,
            lng,
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
            .replace(/(?:улица|ул\.|дом|д\.)/gu, ' ')
            .replace(/[,]/g, ' ').replace(/\s+/g, ' ').trim();
        const house = normalized.match(/(?:^|\s)(\d+[\p{L}]?(?:\/\d+)?)(?:\s|$)/u)?.[1];
        const street = normalized.replace(/(?:^|\s)\d+[\p{L}]?(?:\/\d+)?(?:\s|$)/gu, ' ').trim();
        if (street.length < 3) return [];
        return verifiedAddresses.filter(address => {
            if (house && house !== address.house) return false;
            if (city && this.haversine(city.lat, city.lng, address.lat, address.lng) > this.addressSearchRadiusKm) return false;
            return address.streetAliases.some(alias => alias.includes(street));
        }).map(address => ({
            displayName: address.displayName, lat: address.lat, lng: address.lng,
            countryCode: address.countryCode, source: address.source,
        }));
    }

    private normalizeLocalityName(value: string) {
        return this.normalizeCityToken(value)
            .replace(/^(городской округ|город|г\.)\s+/u, '')
            .replace(/\s+городская администрация$/u, '');
    }

    private rankCityResults<T extends {name?: string; displayName: string}>(items: T[], query: string): T[] {
        const needle = this.normalizeCityToken(query);
        const score = (city: T) => {
            const name = this.normalizeCityToken(city.name || city.displayName);
            return name === needle ? 0 : name.startsWith(needle) ? 1 : 2;
        };
        return items.sort((a, b) => score(a) - score(b) || (a.name || a.displayName).localeCompare(b.name || b.displayName, 'ru')).slice(0, 12);
    }

    private normalizeCityToken(value: string) {
        return value
            .trim()
            .toLowerCase()
            .replaceAll('ё', 'е');
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
        if (parts.length <= 1) return null;
        return parts.join(', ');
    }

    async getRoute(fromLat: number, fromLng: number, toLat: number, toLng: number) {
        try {
            const response = await this.fetchGeo(
                `${this.osrmUrl}/route/v1/driving/${fromLng},${fromLat};${toLng},${toLat}?overview=full&geometries=geojson&steps=true&alternatives=false`
            );
            const data = await response.json();

            if (data.routes && data.routes.length > 0) {
                const route = data.routes[0];
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
            throw new Error('Route unavailable');
        } catch (error) {
            // Fallback: calculate straight line distance
            const distance = this.haversine(fromLat, fromLng, toLat, toLng);
            return {
                distance,
                duration: Math.round(distance / 30 * 60), // Assume 30 km/h average
                geometry: null,
                steps: [],
            };
        }
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
