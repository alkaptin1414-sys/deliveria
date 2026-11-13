import { Module } from '@nestjs/common';
import { OrdersModule } from '../orders/orders.module';
import { CartController, FoodOrdersController, RestaurantPortalController, RestaurantsController } from './restaurants.controller';
import { RestaurantsService } from './restaurants.service';

@Module({
  imports: [OrdersModule],
  controllers: [RestaurantsController, CartController, FoodOrdersController, RestaurantPortalController],
  providers: [RestaurantsService],
})
export class RestaurantsModule {}
