import { Controller, Get, Inject, Query } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { findServiceArea, inEgypt, vehicleAllowed } from '../domain/geo';
import { BUSINESS_CATEGORIES, FAQ, PARCEL_SIZES, PARCEL_TYPES } from './catalog';

@Controller('catalog')
export class CatalogController {
  constructor(@Inject(PrismaService) private readonly prisma: PrismaService) {}

  @Get('business-categories')
  categories() {
    return BUSINESS_CATEGORIES;
  }

  @Get('parcel-types')
  parcels() {
    return { types: PARCEL_TYPES, sizes: PARCEL_SIZES };
  }

  @Get('vehicles')
  async vehicles(@Query('lat') lat?: string, @Query('lng') lng?: string) {
    const rules = await this.prisma.pricingRule.findMany({ where: { active: true } });
    let vehicles = rules.map((rule) => ({
      code: rule.vehicle,
      label: rule.vehicle === 'MOTORCYCLE' ? 'موتوسيكل' : 'سيارة',
      maxWeightKg: rule.maxWeightKg,
      allowedSizes: rule.allowedSizes,
    }));
    if (lat && lng && !(Number(lat) === 0 && Number(lng) === 0)) {
      const areas = await this.prisma.serviceArea.findMany({ where: { active: true } });
      const point = { lat: Number(lat), lng: Number(lng) };
      if (!inEgypt(point)) return [];
      const area = findServiceArea(point, areas);
      if (area) vehicles = vehicles.filter((item) => vehicleAllowed(area, item.code));
    }
    return vehicles;
  }

  @Get('faq')
  faq() {
    return FAQ;
  }
}
