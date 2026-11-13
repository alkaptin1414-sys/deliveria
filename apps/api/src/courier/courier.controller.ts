import { Body, Controller, Get, Inject, Param, Post, Query, Res, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Type } from 'class-transformer';
import { IsBoolean, IsEmail, IsIn, IsNumber, IsOptional, IsString, Length, Max, Min } from 'class-validator';
import { diskStorage } from 'multer';
import { randomBytes } from 'crypto';
import { extname, join } from 'path';
import { mkdirSync } from 'fs';
import { Response } from 'express';
import { CourierAccountStatus, CourierDocKind, CourierSettlementKind, CourierVehicleKind } from '@prisma/client';
import { AuthGuard } from '../common/auth.guard';
import { ApiError } from '../common/api-error';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { HttpStatus } from '@nestjs/common';
import { CourierService } from './courier.service';

const root = join(process.cwd(), 'private-uploads');
mkdirSync(root, { recursive: true });

class ApplyDto {
  @IsString()
  @Length(5, 80)
  fullName!: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsString()
  governorate!: string;

  @IsString()
  @Length(2, 80)
  area!: string;

  @IsIn(['MOTORCYCLE', 'CAR', 'BICYCLE', 'OTHER'])
  vehicle!: CourierVehicleKind;

  @IsOptional()
  @IsString()
  @Length(0, 120)
  vehicleDetails?: string;

  @IsOptional()
  @IsString()
  @Length(0, 20)
  plate?: string;

  @IsBoolean()
  termsAccepted!: boolean;

  @IsOptional()
  @IsString()
  phone?: string;
}

class AvailabilityDto {
  @IsBoolean()
  available!: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng?: number;
}

class AdvanceDto {
  @IsIn(['EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'])
  status!: 'EN_ROUTE_PICKUP' | 'PICKED_UP' | 'EN_ROUTE_DROPOFF';
}

class DeliverDto {
  @IsString()
  @Length(4, 4)
  code!: string;
}

class PingDto {
  @Type(() => Number)
  @IsNumber()
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  lng!: number;
}

class ReviewDto {
  @IsIn(['PENDING_REVIEW', 'NEEDS_INFO', 'APPROVED', 'REJECTED', 'SUSPENDED'])
  status!: CourierAccountStatus;

  @IsOptional()
  @IsString()
  @Length(0, 300)
  note?: string;
}

class SettleDto {
  @IsIn(['WAGE_PAID', 'CASH_REMITTED', 'ADJUSTMENT'])
  kind!: CourierSettlementKind;

  @Type(() => Number)
  @IsNumber()
  amountMinor!: number;

  @IsString()
  @Length(3, 240)
  reason!: string;
}

class ReportDto {
  @IsString()
  @Length(3, 500)
  message!: string;
}

@Controller('courier')
@UseGuards(AuthGuard)
export class CourierController {
  constructor(@Inject(CourierService) private readonly courier: CourierService) {}

  private assertCourier(user: AuthUser) {
    if (user.role !== 'COURIER' && user.role !== 'ADMIN') {
      throw new ApiError('FORBIDDEN', 'هذه الواجهة لحساب المندوب.', HttpStatus.FORBIDDEN);
    }
  }

  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    this.assertCourier(user);
    return this.courier.me(user.id);
  }

  @Post('application')
  apply(@CurrentUser() user: AuthUser, @Body() dto: ApplyDto) {
    if (user.role === 'ADMIN') throw new ApiError('FORBIDDEN', 'هذه الواجهة لحساب المندوب.', HttpStatus.FORBIDDEN);
    return this.courier.apply(user.id, dto);
  }

  @Post('documents')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: root,
        filename: (_req, file, cb) => cb(null, `${randomBytes(16).toString('hex')}${extname(file.originalname || '.jpg')}`),
      }),
      limits: { fileSize: 4 * 1024 * 1024 },
      fileFilter: (_req, file, cb) => {
        if (!file.mimetype.startsWith('image/')) {
          cb(new ApiError('INVALID_FILE', 'ارفع صورة فقط.'), false);
          return;
        }
        cb(null, true);
      },
    }),
  )
  async document(
    @CurrentUser() user: AuthUser,
    @UploadedFile() file?: Express.Multer.File,
    @Query('kind') kind?: CourierDocKind,
  ) {
    if (!file) throw new ApiError('INVALID_FILE', 'اختَر صورة.');
    if (!kind || !['PORTRAIT', 'NATIONAL_ID', 'LICENSE', 'VEHICLE_REGISTRATION', 'OTHER'].includes(kind)) {
      throw new ApiError('INVALID_FILE', 'نوع المستند غير معروف.');
    }
    return this.courier.attachDocument(user.id, kind, file.filename);
  }

  @Get('documents/:id')
  async download(@CurrentUser() user: AuthUser, @Param('id') id: string, @Res() res: Response) {
    const file = await this.courier.openDocument(user, id);
    file.stream.pipe(res);
  }

  @Post('availability')
  availability(@CurrentUser() user: AuthUser, @Body() dto: AvailabilityDto) {
    this.assertCourier(user);
    return this.courier.setAvailability(user.id, dto.available, dto.lat, dto.lng);
  }

  @Get('offers')
  offers(@CurrentUser() user: AuthUser) {
    this.assertCourier(user);
    return this.courier.offers(user.id);
  }

  @Post('offers/:id/accept')
  accept(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    this.assertCourier(user);
    return this.courier.acceptOffer(user.id, id);
  }

  @Post('offers/:id/decline')
  decline(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    this.assertCourier(user);
    return this.courier.declineOffer(user.id, id);
  }

  @Get('orders')
  history(@CurrentUser() user: AuthUser) {
    this.assertCourier(user);
    return this.courier.history(user.id);
  }

  @Get('orders/:id')
  job(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    this.assertCourier(user);
    return this.courier.job(user.id, id);
  }

  @Post('orders/:id/report')
  report(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: ReportDto) {
    this.assertCourier(user);
    return this.courier.report(user.id, id, dto.message);
  }

  @Post('orders/:id/advance')
  advance(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: AdvanceDto) {
    this.assertCourier(user);
    return this.courier.advance(user.id, id, dto.status);
  }

  @Post('orders/:id/deliver')
  deliver(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: DeliverDto) {
    this.assertCourier(user);
    return this.courier.deliver(user.id, id, dto.code);
  }

  @Post('orders/:id/location')
  location(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: PingDto) {
    this.assertCourier(user);
    return this.courier.ping(user.id, id, dto.lat, dto.lng);
  }

  @Get('earnings')
  earnings(@CurrentUser() user: AuthUser) {
    this.assertCourier(user);
    return this.courier.earnings(user.id);
  }

  @Get('ratings')
  ratings(@CurrentUser() user: AuthUser) {
    this.assertCourier(user);
    return this.courier.ratings(user.id);
  }
}

@Controller('admin/couriers')
@UseGuards(AuthGuard)
export class AdminCourierController {
  constructor(@Inject(CourierService) private readonly courier: CourierService) {}

  private assertAdmin(user: AuthUser) {
    if (user.role !== 'ADMIN') throw new ApiError('FORBIDDEN', 'مراجعة المندوبين من صلاحية الإدارة.', HttpStatus.FORBIDDEN);
  }

  @Get()
  list(@CurrentUser() user: AuthUser) {
    this.assertAdmin(user);
    return this.courier.adminList();
  }

  @Post(':id/review')
  review(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: ReviewDto) {
    this.assertAdmin(user);
    return this.courier.adminReview(user.id, id, dto.status, dto.note);
  }

  @Post(':id/settlements')
  settle(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: SettleDto) {
    this.assertAdmin(user);
    return this.courier.adminSettle(user.id, id, dto.kind, dto.amountMinor, dto.reason);
  }
}
