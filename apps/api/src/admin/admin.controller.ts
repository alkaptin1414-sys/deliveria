import { Body, Controller, Get, Inject, Param, Post, Query, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsOptional, IsString, Max, Min, ValidateNested, IsArray, IsNumber } from 'class-validator';
import { HttpStatus } from '@nestjs/common';
import { AuthGuard } from '../common/auth.guard';
import { ApiError } from '../common/api-error';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { OrdersService } from '../orders/orders.service';
import { AdminService } from './admin.service';

class AmountDto {
  @Type(() => Number)
  @IsNumber()
  amountMinor!: number;
}

class SettlementItemDto {
  @IsString()
  orderId!: string;

  @Type(() => Number)
  @IsNumber()
  amountMinor!: number;
}

class ExcludeDto {
  @IsString()
  reason!: string;
}

class SettlementDto {
  @IsString()
  businessId!: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SettlementItemDto)
  items!: SettlementItemDto[];

  @IsOptional()
  @IsString()
  note?: string;
}

class NotifyDto {
  @IsString()
  userId!: string;

  @IsString()
  title!: string;

  @IsString()
  body!: string;
}

class ReasonDto {
  @IsString()
  reason!: string;
}

class SuspendDto extends ReasonDto {
  @IsBoolean()
  suspended!: boolean;
}

class RestaurantPatchDto extends ReasonDto {
  @IsOptional()
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @IsIn(['OPEN', 'CLOSED', 'SCHEDULED'])
  shift?: 'OPEN' | 'CLOSED' | 'SCHEDULED';

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  minOrderMinor?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  deliveryFeeMinor?: number;

  @IsOptional()
  @IsString()
  opensAt?: string;

  @IsOptional()
  @IsString()
  closesAt?: string;
}

class MenuPatchDto extends ReasonDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  priceMinor?: number;

  @IsOptional()
  @IsBoolean()
  available?: boolean;
}

class PricingDto extends ReasonDto {
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(10000)
  deliveryPlatformBps!: number;

  @Type(() => Number)
  @IsInt()
  @Min(0)
  serviceFeeMinor!: number;
}

class AreaDto extends ReasonDto {
  @IsBoolean()
  active!: boolean;
}

class TicketDto {
  @IsIn(['OPEN', 'IN_REVIEW', 'NEEDS_INFO', 'RESOLVED', 'CLOSED'])
  status!: 'OPEN' | 'IN_REVIEW' | 'NEEDS_INFO' | 'RESOLVED' | 'CLOSED';

  @IsString()
  note!: string;

  @IsOptional()
  @IsBoolean()
  internal?: boolean;
}

class CommissionDto extends ReasonDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(10000)
  bps?: number | null;
}

@Controller('admin')
@UseGuards(AuthGuard)
export class AdminController {
  constructor(
    @Inject(OrdersService) private readonly orders: OrdersService,
    @Inject(AdminService) private readonly admin: AdminService,
  ) {}

  private assertAdmin(user: AuthUser) {
    if (user.role !== 'ADMIN') {
      throw new ApiError('FORBIDDEN', 'التسوية والتحصيل النهائي من صلاحية الإدارة.', HttpStatus.FORBIDDEN);
    }
  }

  @Get('home')
  async home(@CurrentUser() user: AuthUser) {
    this.assertAdmin(user);
    const [dashboard, couriers, orders] = await Promise.all([
      this.admin.dashboard(),
      this.admin.couriers(),
      this.admin.orders(),
    ]);
    return {
      ...dashboard,
      recentCouriers: couriers.slice(0, 8),
      recentOrders: orders,
    };
  }

  @Get('couriers')
  couriers(@CurrentUser() user: AuthUser, @Query('q') q?: string) {
    this.assertAdmin(user);
    return this.admin.couriers(q);
  }

  @Get('couriers/:id')
  courier(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    this.assertAdmin(user);
    return this.admin.courier(id);
  }

  @Get('users')
  users(
    @CurrentUser() user: AuthUser,
    @Query('role') role?: string,
    @Query('status') status?: string,
    @Query('q') q?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('take') take?: string,
    @Query('skip') skip?: string,
  ) {
    this.assertAdmin(user);
    return this.admin.users({ role, status, q, from, to, take: take ? Number(take) : undefined, skip: skip ? Number(skip) : undefined });
  }

  @Get('earnings')
  earnings(@CurrentUser() user: AuthUser, @Query('take') take?: string, @Query('skip') skip?: string) {
    this.assertAdmin(user);
    return this.admin.earnings(take ? Number(take) : 30, skip ? Number(skip) : 0);
  }

  @Get('earnings/:profileId')
  earningDetail(@CurrentUser() user: AuthUser, @Param('profileId') profileId: string) {
    this.assertAdmin(user);
    return this.admin.earningDetail(profileId);
  }

  @Get('audits')
  audits(@CurrentUser() user: AuthUser, @Query('take') take?: string, @Query('skip') skip?: string) {
    this.assertAdmin(user);
    return this.admin.audits(take ? Number(take) : 40, skip ? Number(skip) : 0);
  }

  @Post('couriers/:id/commission')
  commission(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: CommissionDto) {
    this.assertAdmin(user);
    return this.admin.setCourierCommission(user.id, id, dto.bps ?? null, dto.reason);
  }

  @Get('customers')
  customers(@CurrentUser() user: AuthUser, @Query('q') q?: string) {
    this.assertAdmin(user);
    return this.admin.customers(q);
  }

  @Post('users/:id/suspension')
  suspend(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: SuspendDto) {
    this.assertAdmin(user);
    return this.admin.setSuspension(user.id, id, dto.suspended, dto.reason);
  }

  @Get('restaurants')
  restaurants(@CurrentUser() user: AuthUser) {
    this.assertAdmin(user);
    return this.admin.restaurants();
  }

  @Get('restaurants/:id')
  restaurant(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    this.assertAdmin(user);
    return this.admin.restaurant(id);
  }

  @Post('restaurants/:id')
  updateRestaurant(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: RestaurantPatchDto) {
    this.assertAdmin(user);
    const { reason, ...data } = dto;
    return this.admin.updateRestaurant(user.id, id, data, reason);
  }

  @Post('menu-items/:id')
  updateItem(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: MenuPatchDto) {
    this.assertAdmin(user);
    const { reason, ...data } = dto;
    return this.admin.updateMenuItem(user.id, id, data, reason);
  }

  @Get('orders')
  orderList(@CurrentUser() user: AuthUser, @Query('status') status?: string) {
    this.assertAdmin(user);
    return this.admin.orders(status);
  }

  @Get('orders/:id')
  order(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    this.assertAdmin(user);
    return this.admin.order(id);
  }

  @Post('orders/:id/cancel')
  cancel(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: ReasonDto) {
    this.assertAdmin(user);
    return this.admin.cancelOrder(user.id, id, dto.reason);
  }

  @Get('finance')
  finance(@CurrentUser() user: AuthUser) {
    this.assertAdmin(user);
    return this.admin.finance();
  }

  @Post('pricing')
  pricing(@CurrentUser() user: AuthUser, @Body() dto: PricingDto) {
    this.assertAdmin(user);
    return this.admin.setPricing(user.id, dto.deliveryPlatformBps, dto.serviceFeeMinor, dto.reason);
  }

  @Get('areas')
  areas(@CurrentUser() user: AuthUser) {
    this.assertAdmin(user);
    return this.admin.areas();
  }

  @Post('areas/:id')
  area(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: AreaDto) {
    this.assertAdmin(user);
    return this.admin.setArea(user.id, id, dto.active, dto.reason);
  }

  @Get('tickets')
  tickets(
    @CurrentUser() user: AuthUser,
    @Query('status') status?: string,
    @Query('kind') kind?: string,
    @Query('q') q?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('take') take?: string,
    @Query('skip') skip?: string,
  ) {
    this.assertAdmin(user);
    return this.admin.tickets({ status, kind, q, from, to, take: take ? Number(take) : undefined, skip: skip ? Number(skip) : undefined });
  }

  @Post('tickets/:id')
  ticket(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: TicketDto) {
    this.assertAdmin(user);
    return this.admin.setTicket(user.id, id, dto.status, dto.note, dto.internal === true);
  }

  @Get('reviews')
  reviews(@CurrentUser() user: AuthUser) {
    this.assertAdmin(user);
    return this.admin.reviews();
  }

  @Post('notifications')
  notify(@CurrentUser() user: AuthUser, @Body() dto: NotifyDto) {
    this.assertAdmin(user);
    return this.admin.notifyUser(user.id, dto.userId, dto.title, dto.body);
  }

  @Post('orders/:id/collection')
  collect(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: AmountDto) {
    this.assertAdmin(user);
    return this.orders.recordCollection(id, dto.amountMinor, 'SUPPORT');
  }

  @Post('reviews/:id/exclude')
  async exclude(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: ExcludeDto) {
    this.assertAdmin(user);
    const result = await this.orders.excludeReview(id, dto.reason);
    await this.admin.audit(user.id, 'EXCLUDE_REVIEW', 'REVIEW', id, dto.reason);
    return result;
  }

  @Post('settlements')
  settle(@CurrentUser() user: AuthUser, @Body() dto: SettlementDto) {
    this.assertAdmin(user);
    return this.orders.settle(dto.businessId, dto.items, dto.note);
  }
}
