/** Convert the private BRouter car response to the existing road-route contract. */
export function brouterRoadResponse(data: any) {
    const feature = data?.features?.find((item: any) => item.geometry?.type === 'LineString');
    const geometry = feature?.geometry;
    const properties = feature?.properties;
    const distance = Number(properties?.['track-length']);
    const duration = Number(properties?.['total-time']);
    if (!geometry || !Array.isArray(geometry.coordinates) || geometry.coordinates.length < 2 ||
        !geometry.coordinates.every((c: any) => Array.isArray(c) && Number.isFinite(c[0]) && Number.isFinite(c[1]) && Math.abs(c[0]) <= 180 && Math.abs(c[1]) <= 90) ||
        properties?.['track-length'] == null || properties?.['total-time'] == null ||
        !Number.isFinite(distance) || distance <= 0 || !Number.isFinite(duration) || duration <= 0) {
        throw new Error('Invalid private car route');
    }
    return {code: 'Ok', routes: [{distance, duration, geometry: {type: 'LineString', coordinates: geometry.coordinates.map((c: number[]) => c.slice(0, 2))}, legs: []}]};
}
