import { Body, Controller, Headers, Inject, Param, Post } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { HttpStatus } from '@nestjs/common';
import { IsIn, IsNumber, IsOptional, IsString } from 'class-validator';
import { Type } from 'class-transformer';
import { OrderStatus } from '@prisma/client';
import { ApiError } from '../common/api-error';
import { OrdersService } from '../orders/orders.service';

class AdvanceDto {
  @IsIn(['ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF', 'NO_COURIER'])
  status!: OrderStatus;
}

class MoveDto {
  @Type(() => Number)
  @IsNumber()
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  lng!: number;
}

class CodeDto {
  @IsString()
  code!: string;
}

class CollectDto {
  @Type(() => Number)
  @IsNumber()
  amountMinor!: number;
}

class NoteDto {
  @IsOptional()
  @IsString()
  note?: string;
}

@Controller('dev')
export class DevController {
  constructor(
    @Inject(ConfigService) private readonly config: ConfigService,
    @Inject(OrdersService) private readonly orders: OrdersService,
  ) {}

  @Post('orders/:id/accept')
  accept(@Headers('x-dev-key') key: string, @Param('id') id: string) {
    this.assert(key);
    return this.orders.acceptForDev(id, {
      id: 'dev-courier',
      name: 'محمود عادل',
      phone: '+201000000000',
      vehicle: 'MOTORCYCLE',
      plate: 'أ ب ج 1234',
      rating: 4.8,
    });
  }

  @Post('orders/:id/status')
  status(@Headers('x-dev-key') key: string, @Param('id') id: string, @Body() dto: AdvanceDto) {
    this.assert(key);
    const actor = dto.status === 'NO_COURIER' ? 'SYSTEM' : 'COURIER';
    return this.orders.advanceForDev(id, dto.status, actor);
  }

  @Post('orders/:id/location')
  location(@Headers('x-dev-key') key: string, @Param('id') id: string, @Body() dto: MoveDto) {
    this.assert(key);
    return this.orders.moveCourier(id, dto.lat, dto.lng);
  }

  @Post('orders/:id/verify')
  verify(@Headers('x-dev-key') key: string, @Param('id') id: string, @Body() dto: CodeDto) {
    this.assert(key);
    return this.orders.verifyDelivery(id, dto.code, 'SYSTEM');
  }

  @Post('orders/:id/collect')
  collect(@Headers('x-dev-key') key: string, @Param('id') id: string, @Body() dto: CollectDto) {
    this.assert(key);
    return this.orders.recordCollection(id, dto.amountMinor, 'SYSTEM');
  }

  @Post('orders/:id/support-complete')
  support(@Headers('x-dev-key') key: string, @Param('id') id: string, @Body() dto: NoteDto) {
    this.assert(key);
    return this.orders.supportComplete(id, dto.note?.trim() || 'تعذر استخدام الرمز، واعتمد الدعم التسليم.');
  }

  private assert(key: string) {
    if (this.config.get('NODE_ENV') === 'production' || this.config.get('ENABLE_DEV_TOOLS') !== 'true') {
      throw new ApiError('NOT_FOUND', 'غير متاح.', HttpStatus.NOT_FOUND);
    }
    if (key !== this.config.get('DEV_TOOLS_KEY')) {
      throw new ApiError('FORBIDDEN', 'مفتاح بيئة التطوير غير صحيح.', HttpStatus.FORBIDDEN);
    }
  }
}
