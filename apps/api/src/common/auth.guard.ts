import { CanActivate, ExecutionContext, Inject, Injectable } from '@nestjs/common';
import { HttpStatus } from '@nestjs/common';
import { JwtService } from '../auth/jwt.service';
import { PrismaService } from '../prisma/prisma.service';
import { ApiError } from './api-error';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    @Inject(JwtService) private readonly jwt: JwtService,
    @Inject(PrismaService) private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const header = request.headers.authorization as string | undefined;
    if (!header?.startsWith('Bearer ')) {
      throw new ApiError('UNAUTHENTICATED', 'سجّل الدخول للمتابعة.', HttpStatus.UNAUTHORIZED);
    }
    let user;
    try {
      user = this.jwt.verifyAccess(header.slice(7));
    } catch {
      throw new ApiError('SESSION_EXPIRED', 'انتهت الجلسة. سجّل الدخول من جديد.', HttpStatus.UNAUTHORIZED);
    }
    const row = await this.prisma.user.findUnique({ where: { id: user.id }, select: { suspendedAt: true, role: true } });
    if (!row) throw new ApiError('UNAUTHENTICATED', 'سجّل الدخول للمتابعة.', HttpStatus.UNAUTHORIZED);
    if (row.suspendedAt) throw new ApiError('ACCOUNT_SUSPENDED', 'الحساب موقوف من الإدارة.', HttpStatus.FORBIDDEN);
    request.user = { ...user, role: row.role };
    return true;
  }
}
