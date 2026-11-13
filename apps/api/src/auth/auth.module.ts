import { Global, Module } from '@nestjs/common';
import { AuthController, MeController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtService } from './jwt.service';
import { AuthGuard } from '../common/auth.guard';

@Global()
@Module({
  controllers: [AuthController, MeController],
  providers: [AuthService, JwtService, AuthGuard],
  exports: [AuthService, JwtService, AuthGuard],
})
export class AuthModule {}
