import { Body, Controller, Delete, Get, Inject, Param, Post, UseGuards } from '@nestjs/common';
import { IsIn, IsString, Length } from 'class-validator';
import { AuthGuard } from '../common/auth.guard';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { ApiError } from '../common/api-error';
import { PrismaService } from '../prisma/prisma.service';
import { HttpStatus } from '@nestjs/common';

class DeviceDto {
  @IsString()
  @Length(8, 512)
  token!: string;

  @IsIn(['android', 'ios'])
  platform!: string;
}

@Controller('notifications')
@UseGuards(AuthGuard)
export class NotificationsController {
  constructor(@Inject(PrismaService) private readonly prisma: PrismaService) {}

  @Post('devices')
  async register(@CurrentUser() user: AuthUser, @Body() dto: DeviceDto) {
    return this.prisma.deviceToken.upsert({
      where: { token: dto.token },
      update: { userId: user.id, platform: dto.platform },
      create: { userId: user.id, token: dto.token, platform: dto.platform },
    });
  }

  @Delete('devices')
  async unregister(@CurrentUser() user: AuthUser, @Body() dto: DeviceDto) {
    await this.prisma.deviceToken.deleteMany({ where: { token: dto.token, userId: user.id } });
    return { ok: true };
  }

  @Get()
  list(@CurrentUser() user: AuthUser) {
    return this.prisma.notification.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
  }

  @Post(':id/read')
  async read(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    const item = await this.prisma.notification.findUnique({ where: { id } });
    if (!item || item.userId !== user.id) {
      throw new ApiError('NOT_FOUND', 'الإشعار غير موجود.', HttpStatus.NOT_FOUND);
    }
    return this.prisma.notification.update({ where: { id }, data: { readAt: new Date() } });
  }

  @Post('read-all')
  async readAll(@CurrentUser() user: AuthUser) {
    await this.prisma.notification.updateMany({
      where: { userId: user.id, readAt: null },
      data: { readAt: new Date() },
    });
    return { ok: true };
  }
}
