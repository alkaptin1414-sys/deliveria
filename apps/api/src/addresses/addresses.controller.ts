import { Body, Controller, Delete, Get, Inject, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { IsBoolean, IsIn, IsNumber, IsOptional, IsString, Length, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { AddressLabel } from '@prisma/client';
import { AuthGuard } from '../common/auth.guard';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { ApiError } from '../common/api-error';
import { PrismaService } from '../prisma/prisma.service';
import { HttpStatus } from '@nestjs/common';
import { inEgypt } from '../domain/geo';

class AddressDto {
  @IsIn(['HOME', 'WORK', 'SHOP', 'OTHER'])
  label!: AddressLabel;

  @IsString()
  @Length(2, 40)
  name!: string;

  @IsString()
  @Length(2, 40)
  governorate!: string;

  @IsString()
  @Length(2, 40)
  city!: string;

  @IsString()
  @Length(2, 40)
  area!: string;

  @IsString()
  @Length(3, 180)
  line!: string;

  @IsOptional()
  @IsString()
  details?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng!: number;

  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;
}

@Controller('addresses')
@UseGuards(AuthGuard)
export class AddressesController {
  constructor(@Inject(PrismaService) private readonly prisma: PrismaService) {}

  @Get()
  list(@CurrentUser() user: AuthUser) {
    return this.prisma.address.findMany({ where: { userId: user.id }, orderBy: { createdAt: 'desc' } });
  }

  @Post()
  async create(@CurrentUser() user: AuthUser, @Body() dto: AddressDto) {
    await this.ensureCovered(dto.lat, dto.lng);
    if (dto.isDefault) {
      await this.prisma.address.updateMany({ where: { userId: user.id }, data: { isDefault: false } });
    }
    const count = await this.prisma.address.count({ where: { userId: user.id } });
    return this.prisma.address.create({
      data: { ...dto, userId: user.id, isDefault: dto.isDefault ?? count === 0 },
    });
  }

  @Patch(':id')
  async update(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: AddressDto) {
    await this.owned(user.id, id);
    await this.ensureCovered(dto.lat, dto.lng);
    if (dto.isDefault) {
      await this.prisma.address.updateMany({ where: { userId: user.id }, data: { isDefault: false } });
    }
    return this.prisma.address.update({ where: { id }, data: dto });
  }

  @Delete(':id')
  async remove(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    await this.owned(user.id, id);
    await this.prisma.address.delete({ where: { id } });
    return { ok: true };
  }

  @Post(':id/default')
  async makeDefault(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    await this.owned(user.id, id);
    await this.prisma.address.updateMany({ where: { userId: user.id }, data: { isDefault: false } });
    return this.prisma.address.update({ where: { id }, data: { isDefault: true } });
  }

  private async owned(userId: string, id: string) {
    const address = await this.prisma.address.findUnique({ where: { id } });
    if (!address || address.userId !== userId) {
      throw new ApiError('NOT_FOUND', 'العنوان غير موجود.', HttpStatus.NOT_FOUND);
    }
    return address;
  }

  private async ensureCovered(lat: number, lng: number) {
    if (lat === 0 && lng === 0) return;
    if (!inEgypt({ lat, lng })) {
      throw new ApiError('OUT_OF_SERVICE_AREA', 'العنوان يجب أن يكون داخل مصر.');
    }
  }
}
