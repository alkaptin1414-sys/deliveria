import { PrismaClient, VehicleType } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  await prisma.pricingRule.upsert({
    where: { vehicle: VehicleType.MOTORCYCLE },
    update: {},
    create: {
      vehicle: VehicleType.MOTORCYCLE,
      baseFeeMinor: 2000,
      perKmMinor: 450,
      minFeeMinor: 2500,
      maxDistanceMeters: 25000,
      fragileSurchargeMinor: 800,
      mediumSurchargeMinor: 500,
      largeSurchargeMinor: 0,
      maxWeightKg: 10,
      allowedSizes: ['SMALL', 'MEDIUM'],
      version: 1,
    },
  });
  await prisma.pricingRule.upsert({
    where: { vehicle: VehicleType.CAR },
    update: {},
    create: {
      vehicle: VehicleType.CAR,
      baseFeeMinor: 3500,
      perKmMinor: 700,
      minFeeMinor: 4000,
      maxDistanceMeters: 40000,
      fragileSurchargeMinor: 1000,
      mediumSurchargeMinor: 0,
      largeSurchargeMinor: 1500,
      maxWeightKg: 80,
      allowedSizes: ['SMALL', 'MEDIUM', 'LARGE'],
      version: 1,
    },
  });

  const areas = [
    { name: 'القاهرة', minLat: 29.95, maxLat: 30.2, minLng: 31.15, maxLng: 31.45 },
    { name: 'الجيزة', minLat: 29.9, maxLat: 30.15, minLng: 30.9, maxLng: 31.25 },
    { name: 'القليوبية', minLat: 30.1, maxLat: 30.35, minLng: 31.15, maxLng: 31.4 },
    { name: 'الإسكندرية', minLat: 31.1, maxLat: 31.35, minLng: 29.85, maxLng: 30.05 },
  ];
  for (const area of areas) {
    const existing = await prisma.serviceArea.findFirst({ where: { name: area.name } });
    if (!existing) await prisma.serviceArea.create({ data: area });
  }
}

main()
  .then(() => prisma.$disconnect())
  .catch(async (error) => {
    console.error(error);
    await prisma.$disconnect();
    process.exit(1);
  });
