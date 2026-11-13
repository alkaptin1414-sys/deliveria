import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { sign, verify } from 'jsonwebtoken';
import { AuthUser } from '../common/current-user.decorator';

@Injectable()
export class JwtService {
  constructor(@Inject(ConfigService) private readonly config: ConfigService) {}

  signAccess(user: AuthUser): string {
    return sign(user, this.config.getOrThrow<string>('JWT_ACCESS_SECRET'), { expiresIn: '30m' });
  }

  verifyAccess(token: string): AuthUser {
    return verify(token, this.config.getOrThrow<string>('JWT_ACCESS_SECRET')) as AuthUser;
  }
}
