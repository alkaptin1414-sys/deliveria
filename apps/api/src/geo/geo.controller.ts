import { Controller, Get, HttpStatus, Inject, Query, UseGuards } from '@nestjs/common';
import { inEgypt } from '../domain/geo';
import { ConfigService } from '@nestjs/config';
import { AuthGuard } from '../common/auth.guard';
import { ApiError } from '../common/api-error';

@Controller('geo')
@UseGuards(AuthGuard)
export class GeoController {
  constructor(@Inject(ConfigService) private readonly config: ConfigService) {}

  @Get('place')
  async place(@Query('q') q: string) {
    const line = q?.trim() ?? '';
    if (line.length < 3) throw new ApiError('INVALID_LOCATION', 'اكتب العنوان والمنطقة والمدينة.');
    const queries = line.includes('مصر') || line.toLowerCase().includes('egypt') ? [line] : [line, `${line}، مصر`];
    for (const query of queries) {
      const url = new URL('https://nominatim.openstreetmap.org/search');
      url.searchParams.set('q', query);
      url.searchParams.set('format', 'json');
      url.searchParams.set('limit', '5');
      url.searchParams.set('countrycodes', 'eg');
      const response = await fetch(url, { headers: { 'User-Agent': 'Deliveria/1.0 (delivery)', 'Accept-Language': 'ar' } });
      if (!response.ok) continue;
      const list = (await response.json()) as Array<{ lat?: string; lon?: string }>;
      const hit = list.find((item) => inEgypt({ lat: Number(item.lat), lng: Number(item.lon) }));
      if (!hit?.lat || !hit.lon) continue;
      return { line, lat: Number(hit.lat), lng: Number(hit.lon) };
    }
    throw new ApiError('PLACE_NOT_FOUND', 'لم نتعرف على هذا العنوان داخل مصر. اكتب الشارع والمنطقة والمدينة.');
  }

  @Get('route')
  async route(
    @Query('fromLat') fromLat: string,
    @Query('fromLng') fromLng: string,
    @Query('toLat') toLat: string,
    @Query('toLng') toLng: string,
  ) {
    const origin = this.point(fromLat, fromLng);
    const destination = this.point(toLat, toLng);
    const key = this.config.get<string>('GOOGLE_MAPS_API_KEY');
    if (!key) {
      throw new ApiError(
        'ROUTE_UNAVAILABLE',
        'مسار القيادة يحتاج مفتاح طرق على الخادم، منفصلًا عن مفتاح تطبيق أندرويد.',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': key,
        'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
      },
      body: JSON.stringify({
        origin: { location: { latLng: { latitude: origin.lat, longitude: origin.lng } } },
        destination: { location: { latLng: { latitude: destination.lat, longitude: destination.lng } } },
        travelMode: 'DRIVE',
      }),
    });
    const body = (await response.json()) as { routes?: Array<{ duration?: string; distanceMeters?: number; polyline?: { encodedPolyline?: string } }> };
    const route = body.routes?.[0];
    const encoded = route?.polyline?.encodedPolyline;
    if (!response.ok || !encoded) {
      throw new ApiError('ROUTE_UNAVAILABLE', 'تعذر حساب مسار القيادة من Google.', HttpStatus.BAD_GATEWAY);
    }
    const seconds = Number(String(route.duration ?? '0').replace('s', ''));
    return {
      encodedPolyline: encoded,
      distanceMeters: route.distanceMeters ?? null,
      etaMinutes: Number.isFinite(seconds) && seconds > 0 ? Math.ceil(seconds / 60) : null,
      approximate: true,
    };
  }

  private point(lat: string, lng: string) {
    const latitude = Number(lat);
    const longitude = Number(lng);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
      throw new ApiError('INVALID_LOCATION', 'إحداثيات المسار غير صالحة.');
    }
    return { lat: latitude, lng: longitude };
  }
}
