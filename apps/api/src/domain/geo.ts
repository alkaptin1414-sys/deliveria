export interface LatLng {
  lat: number;
  lng: number;
}

export interface ServiceBox {
  name: string;
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
  motorcycles: boolean;
  cars: boolean;
  active: boolean;
}

const EARTH_METERS = 6371000;
const ROAD_FACTOR = 1.25;

export function haversineMeters(a: LatLng, b: LatLng): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_METERS * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function estimatedRoadMeters(a: LatLng, b: LatLng): number {
  return Math.round(haversineMeters(a, b) * ROAD_FACTOR);
}

export function inEgypt(point: LatLng): boolean {
  return point.lat >= 22 && point.lat <= 32.5 && point.lng >= 24.5 && point.lng <= 37;
}

export function findServiceArea(point: LatLng, areas: ServiceBox[]): ServiceBox | null {
  return (
    areas.find(
      (area) =>
        area.active &&
        point.lat >= area.minLat &&
        point.lat <= area.maxLat &&
        point.lng >= area.minLng &&
        point.lng <= area.maxLng,
    ) ?? null
  );
}

export function vehicleAllowed(area: ServiceBox, vehicle: 'MOTORCYCLE' | 'CAR'): boolean {
  return vehicle === 'MOTORCYCLE' ? area.motorcycles : area.cars;
}
