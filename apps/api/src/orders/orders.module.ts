import { Module } from '@nestjs/common';
import { NotificationsModule } from '../notifications/notifications.module';
import { CourierRatingsController, OrdersController, ReviewReportsController } from './orders.controller';
import { OrdersService } from './orders.service';

@Module({
  imports: [NotificationsModule],
  controllers: [OrdersController, CourierRatingsController, ReviewReportsController],
  providers: [OrdersService],
  exports: [OrdersService],
})
export class OrdersModule {}
