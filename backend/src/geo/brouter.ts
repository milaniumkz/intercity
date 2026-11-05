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
    const coordinates = geometry.coordinates.map((c: number[]) => c.slice(0, 2));
    const times = Array.isArray(properties.times) ? properties.times : [];
    const modifiers: Record<number, string> = {1:'straight',2:'left',3:'slight left',4:'sharp left',5:'right',6:'slight right',7:'sharp right',8:'left',9:'right',10:'uturn',11:'uturn',13:'right',14:'left',15:'uturn',17:'left',18:'right'};
    const turns = (Array.isArray(properties.voicehints) ? properties.voicehints : [])
        .filter((hint: any) => Array.isArray(hint) && Number.isInteger(hint[0]) && hint[0]>0 && hint[0]<coordinates.length-1 && modifiers[hint[1]] && Number.isFinite(hint[3]) && hint[3]>=0)
        .sort((a: number[], b: number[]) => a[0]-b[0]);
    const points = [{index:0,type:'depart',modifier:'straight',distance:0,exit:0}, ...turns.map((hint: number[]) => ({
        index:hint[0],type:[13,14].includes(hint[1])?'roundabout':[8,9].includes(hint[1])?'fork':'turn',
        modifier:modifiers[hint[1]],distance:hint[3],exit:hint[2],
    })), {index:coordinates.length-1,type:'arrive',modifier:'straight',distance:0,exit:0}];
    const steps = points.map((point, index) => ({
        distance:point.distance,
        duration:Math.max(0,Number(times[points[index+1]?.index] || 0)-Number(times[point.index] || 0)),
        name:'', mode:'driving',
        maneuver:{type:point.type,modifier:point.modifier,location:coordinates[point.index],...(point.type==='roundabout'?{exit:point.exit}:{})},
    }));
    return {code: 'Ok', routes: [{distance, duration, geometry: {type: 'LineString', coordinates}, legs: [{steps}]}]};
}
