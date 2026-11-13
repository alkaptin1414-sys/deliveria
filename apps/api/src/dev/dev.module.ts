import { Module } from '@nestjs/common';
import { OrdersModule } from '../orders/orders.module';
import { DevController } from './dev.controller';

@Module({ imports: [OrdersModule], controllers: [DevController] })
export class DevModule {}
