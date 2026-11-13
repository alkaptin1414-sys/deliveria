import { Body, Controller, Get, Headers, Inject, Param, Post, Query, UseGuards } from '@nestjs/common';
import { IsString, Length } from 'class-validator';
import { AuthGuard } from '../common/auth.guard';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { CancelDto, CreateOrderDto, MessageDto, QuoteDto, ReviewDto } from './dto';
import { OrdersService } from './orders.service';

@Controller('orders')
@UseGuards(AuthGuard)
export class OrdersController {
  constructor(@Inject(OrdersService) private readonly orders: OrdersService) {}

  @Post('quote')
  quote(@CurrentUser() user: AuthUser, @Body() dto: QuoteDto) {
    return this.orders.quote(user.id, dto);
  }

  @Post()
  create(
    @CurrentUser() user: AuthUser,
    @Headers('idempotency-key') key: string,
    @Body() dto: CreateOrderDto,
  ) {
    return this.orders.create(user.id, key, dto);
  }

  @Get()
  list(@CurrentUser() user: AuthUser, @Query('bucket') bucket = 'active', @Query('q') q?: string) {
    return this.orders.list(user.id, bucket, q);
  }

  @Get(':id')
  get(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.orders.get(user.id, id);
  }

  @Get(':id/cancel-preview')
  cancelPreview(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.orders.cancelPreview(user.id, id);
  }

  @Post(':id/cancel')
  cancel(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: CancelDto) {
    return this.orders.cancel(user.id, id, dto);
  }

  @Post(':id/retry')
  retry(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.orders.retry(user.id, id);
  }

  @Get(':id/delivery-code')
  code(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.orders.deliveryCode(user.id, id);
  }

  @Get(':id/review')
  orderReview(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.orders.orderReview(user.id, id);
  }

  @Post(':id/review')
  review(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: ReviewDto) {
    return this.orders.review(user.id, id, dto);
  }

  @Post(':id/review/update')
  updateReview(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: ReviewDto) {
    return this.orders.updateReview(user.id, id, dto);
  }

  @Get(':id/messages')
  messages(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.orders.messages(user.id, id);
  }

  @Post(':id/messages')
  send(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: MessageDto) {
    return this.orders.sendMessage(user.id, id, dto.body);
  }
}

class ReportDto {
  @IsString()
  @Length(3, 240)
  reason!: string;
}

@Controller('couriers')
@UseGuards(AuthGuard)
export class CourierRatingsController {
  constructor(@Inject(OrdersService) private readonly orders: OrdersService) {}

  @Get('selectable')
  selectable() {
    return this.orders.selectableCouriers();
  }

  @Get(':courierId/ratings')
  ratings(@CurrentUser() user: AuthUser, @Param('courierId') courierId: string) {
    return this.orders.courierRatings(user.id, courierId);
  }
}

@Controller('reviews')
@UseGuards(AuthGuard)
export class ReviewReportsController {
  constructor(@Inject(OrdersService) private readonly orders: OrdersService) {}

  @Post(':id/report')
  report(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: ReportDto) {
    return this.orders.reportReview(user.id, id, dto.reason);
  }
}

