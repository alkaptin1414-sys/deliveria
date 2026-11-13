import { Body, Controller, Get, Headers, Inject, Param, Patch, Post, Put, Query, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsArray, IsBoolean, IsIn, IsInt, IsOptional, IsString, Length, Max, Min, ValidateNested } from 'class-validator';
import { AuthGuard } from '../common/auth.guard';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { RestaurantsService } from './restaurants.service';

class CartLineDto {
  @IsString()
  itemId!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(20)
  quantity!: number;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  optionIds?: string[];

  @IsOptional()
  @IsString()
  @Length(0, 180)
  note?: string;
}

class SaveCartDto {
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CartLineDto)
  items!: CartLineDto[];
}

class CheckoutDto {
  @IsString()
  restaurantId!: string;

  @IsString()
  addressId!: string;

  @IsString()
  @Length(2, 60)
  recipientName!: string;

  @IsString()
  recipientPhone!: string;

  @IsOptional()
  @IsString()
  @Length(0, 240)
  notes?: string;

  @IsOptional()
  @IsString()
  scheduledFor?: string;

  @IsOptional()
  @IsString()
  courierId?: string;
}

class ReviewBody {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(5)
  rating!: number;

  @IsOptional()
  @IsString()
  @Length(0, 240)
  comment?: string;
}

class AcceptBody {
  @Type(() => Number)
  @IsInt()
  @Min(5)
  @Max(180)
  prepMinutes!: number;
}

class ReasonBody {
  @IsString()
  @Length(3, 180)
  reason!: string;
}

class ItemBody {
  @IsString()
  sectionId!: string;

  @IsString()
  @Length(2, 80)
  name!: string;

  @IsOptional()
  @IsString()
  description?: string;

  @Type(() => Number)
  @IsInt()
  @Min(0)
  priceMinor!: number;

  @IsOptional()
  @IsIn(['ITEM', 'COMBO'])
  kind?: 'ITEM' | 'COMBO';

  @IsOptional()
  @IsString()
  imageUrl?: string;
}

class PatchItemBody {
  @IsOptional()
  @IsBoolean()
  available?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  priceMinor?: number;

  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsString()
  imageUrl?: string;
}

@Controller('restaurants')
export class RestaurantsController {
  constructor(@Inject(RestaurantsService) private readonly restaurants: RestaurantsService) {}

  @Get('categories')
  categories() {
    return this.restaurants.categories();
  }

  @Get()
  list(@Query('q') q?: string, @Query('category') category?: string, @Query('sort') sort?: string) {
    return this.restaurants.list({ q, category, sort });
  }

  @Get(':id')
  detail(@Param('id') id: string) {
    return this.restaurants.detail(id);
  }
}

@Controller('restaurants/:id/cart')
@UseGuards(AuthGuard)
export class CartController {
  constructor(@Inject(RestaurantsService) private readonly restaurants: RestaurantsService) {}

  @Get()
  get(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.restaurants.cart(user.id, id);
  }

  @Put()
  save(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: SaveCartDto) {
    return this.restaurants.saveCart(user.id, id, dto.items);
  }

  @Get('quote')
  quote(@CurrentUser() user: AuthUser, @Param('id') id: string, @Query('addressId') addressId: string) {
    return this.restaurants.quote(user.id, id, addressId);
  }
}

@Controller('food-orders')
@UseGuards(AuthGuard)
export class FoodOrdersController {
  constructor(@Inject(RestaurantsService) private readonly restaurants: RestaurantsService) {}

  @Get()
  list(@CurrentUser() user: AuthUser) {
    return this.restaurants.myOrders(user.id);
  }

  @Post()
  create(
    @CurrentUser() user: AuthUser,
    @Headers('idempotency-key') key: string,
    @Body() dto: CheckoutDto,
  ) {
    return this.restaurants.checkout(user.id, dto.restaurantId, { ...dto, idempotencyKey: key });
  }

  @Get(':id')
  one(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.restaurants.myOrder(user.id, id);
  }

  @Post(':id/cancel')
  cancel(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.restaurants.cancel(user.id, id);
  }

  @Post(':id/review')
  review(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: ReviewBody) {
    return this.restaurants.review(user.id, id, dto.rating, dto.comment);
  }
}

@Controller('restaurant')
@UseGuards(AuthGuard)
export class RestaurantPortalController {
  constructor(@Inject(RestaurantsService) private readonly restaurants: RestaurantsService) {}

  @Get('orders')
  orders(@CurrentUser() user: AuthUser) {
    return this.restaurants.portalOrders(user.id);
  }

  @Get('sales')
  sales(@CurrentUser() user: AuthUser) {
    return this.restaurants.sales(user.id);
  }

  @Post('orders/:id/accept')
  accept(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: AcceptBody) {
    return this.restaurants.accept(user.id, id, dto.prepMinutes);
  }

  @Post('orders/:id/reject')
  reject(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: ReasonBody) {
    return this.restaurants.reject(user.id, id, dto.reason);
  }

  @Post('orders/:id/preparing')
  preparing(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.restaurants.preparing(user.id, id);
  }

  @Post('orders/:id/ready')
  ready(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.restaurants.ready(user.id, id);
  }

  @Post('items')
  createItem(@CurrentUser() user: AuthUser, @Body() dto: ItemBody) {
    return this.restaurants.createItem(user.id, dto);
  }

  @Patch('items/:id')
  patchItem(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: PatchItemBody) {
    return this.restaurants.patchItem(user.id, id, dto);
  }
}
