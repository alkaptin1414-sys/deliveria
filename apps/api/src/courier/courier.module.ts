import { Module } from '@nestjs/common';
import { OrdersModule } from '../orders/orders.module';
import { AdminCourierController, CourierController } from './courier.controller';
import { CourierService } from './courier.service';

@Module({
  imports: [OrdersModule],
  controllers: [CourierController, AdminCourierController],
  providers: [CourierService],
  exports: [CourierService],
})
export class CourierModule {}
