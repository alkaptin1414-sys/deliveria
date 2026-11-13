const LIVE_MS = 90_000;

export function customerTracking(input: {
  status: string;
  lat: number | null;
  lng: number | null;
  updatedAt: Date | null;
  now: Date;
}) {
  const active = ['ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'].includes(input.status);
  if (!active || input.lat == null || input.lng == null || !input.updatedAt) {
    return { active, lat: null as number | null, lng: null as number | null, fresh: false, updatedAt: null as string | null };
  }
  const age = input.now.getTime() - input.updatedAt.getTime();
  return {
    active: true,
    lat: input.lat,
    lng: input.lng,
    fresh: age <= LIVE_MS,
    updatedAt: input.updatedAt.toISOString(),
  };
}
