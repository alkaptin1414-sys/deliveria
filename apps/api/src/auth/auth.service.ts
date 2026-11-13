import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash, randomBytes, randomInt, scrypt, timingSafeEqual } from 'crypto';
import { promisify } from 'util';
import { PrismaService } from '../prisma/prisma.service';
import { ApiError } from '../common/api-error';
import { normalizeEgyptPhone } from '../domain/phone';
import { JwtService } from './jwt.service';
import { CompleteProfileDto, RegisterDto, UpdateMeDto } from './dto';

const scryptAsync = promisify(scrypt);

@Injectable()
export class AuthService {
  constructor(
    @Inject(PrismaService) private readonly prisma: PrismaService,
    @Inject(JwtService) private readonly jwt: JwtService,
    @Inject(ConfigService) private readonly config: ConfigService,
  ) {}

  async register(dto: RegisterDto) {
    const email = dto.email.trim().toLowerCase();
    const existing = await this.prisma.user.findUnique({ where: { email } });
    if (existing) throw new ApiError('EMAIL_EXISTS', 'هذا البريد مسجّل بالفعل. سجّل الدخول.');
    const user = await this.prisma.user.create({
      data: {
        email,
        name: dto.name.trim(),
        role: dto.role,
        passwordHash: await this.hashPassword(dto.password),
      },
    });
    return this.issueSession(user);
  }

  async login(emailInput: string, password: string) {
    const email = emailInput.trim().toLowerCase();
    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user?.passwordHash || !(await this.verifyPassword(password, user.passwordHash))) {
      throw new ApiError('INVALID_LOGIN', 'البريد أو كلمة المرور غير صحيحة.', HttpStatus.UNAUTHORIZED);
    }
    if (user.suspendedAt) {
      throw new ApiError('ACCOUNT_SUSPENDED', 'الحساب موقوف من الإدارة.', HttpStatus.FORBIDDEN);
    }
    return this.issueSession(user);
  }

  async requestOtp(phoneInput: string) {
    const phone = normalizeEgyptPhone(phoneInput);
    if (!phone) {
      throw new ApiError('INVALID_PHONE', 'اكتب رقم موبايل مصري صحيح.');
    }
    const since = new Date(Date.now() - 15 * 60 * 1000);
    const recent = await this.prisma.otpChallenge.count({
      where: { phone, createdAt: { gte: since } },
    });
    if (recent >= 5) {
      throw new ApiError('OTP_RATE_LIMIT', 'حاولت كتير. استنى شوية وحاول تاني.', HttpStatus.TOO_MANY_REQUESTS);
    }
    const code = String(randomInt(0, 1000000)).padStart(6, '0');
    const challenge = await this.prisma.otpChallenge.create({
      data: {
        phone,
        codeHash: this.hashCode(code),
        expiresAt: new Date(Date.now() + 5 * 60 * 1000),
      },
    });
    const dev = this.config.get('NODE_ENV') !== 'production';
    if (dev) console.info(`[otp] ${phone} ${code}`);
    return {
      challengeId: challenge.id,
      expiresIn: 300,
      phone,
      ...(dev ? { devCode: code } : {}),
    };
  }

  async verifyOtp(challengeId: string, code: string) {
    const challenge = await this.prisma.otpChallenge.findUnique({ where: { id: challengeId } });
    if (!challenge || challenge.consumedAt) {
      throw new ApiError('OTP_INVALID', 'رمز التأكيد غير صحيح.');
    }
    if (challenge.expiresAt.getTime() < Date.now() || challenge.attempts >= 5) {
      throw new ApiError('OTP_EXPIRED', 'انتهت صلاحية الرمز. اطلب رمزًا جديدًا.');
    }
    if (challenge.codeHash !== this.hashCode(code)) {
      await this.prisma.otpChallenge.update({
        where: { id: challenge.id },
        data: { attempts: { increment: 1 } },
      });
      throw new ApiError('OTP_INVALID', 'رمز التأكيد غير صحيح.');
    }
    await this.prisma.otpChallenge.update({
      where: { id: challenge.id },
      data: { consumedAt: new Date() },
    });
    const user = await this.prisma.user.upsert({
      where: { phone: challenge.phone },
      update: {},
      create: { phone: challenge.phone },
    });
    if (user.suspendedAt) {
      throw new ApiError('ACCOUNT_SUSPENDED', 'الحساب موقوف من الإدارة.', HttpStatus.FORBIDDEN);
    }
    return this.issueSession(user);
  }

  async refresh(refreshToken: string) {
    const session = await this.prisma.refreshSession.findUnique({
      where: { tokenHash: this.hashToken(refreshToken) },
      include: { user: true },
    });
    if (!session || session.revokedAt || session.expiresAt.getTime() < Date.now()) {
      throw new ApiError('SESSION_EXPIRED', 'انتهت الجلسة. سجّل الدخول من جديد.', HttpStatus.UNAUTHORIZED);
    }
    if (session.user.suspendedAt) {
      throw new ApiError('ACCOUNT_SUSPENDED', 'الحساب موقوف من الإدارة.', HttpStatus.FORBIDDEN);
    }
    await this.prisma.refreshSession.update({
      where: { id: session.id },
      data: { revokedAt: new Date() },
    });
    return this.issueSession(session.user);
  }

  async logout(refreshToken: string) {
    await this.prisma.refreshSession.updateMany({
      where: { tokenHash: this.hashToken(refreshToken), revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return { ok: true };
  }

  async completeProfile(userId: string, dto: CompleteProfileDto) {
    const current = await this.prisma.user.findUnique({ where: { id: userId } });
    if (current?.role === 'COURIER') {
      throw new ApiError('FORBIDDEN', 'حساب المندوب لا يستخدم إعداد حساب العميل.', HttpStatus.FORBIDDEN);
    }
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: { name: dto.name.trim(), accountType: dto.accountType },
    });
    return this.presentUser(user);
  }

  async me(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new ApiError('UNAUTHENTICATED', 'سجّل الدخول للمتابعة.', HttpStatus.UNAUTHORIZED);
    const profile = await this.prisma.courierProfile.findUnique({ where: { userId } });
    return { ...this.presentUser(user), courierStatus: profile?.status ?? null };
  }

  async updateMe(userId: string, dto: UpdateMeDto) {
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: {
        name: dto.name?.trim(),
        notifOrders: dto.notifOrders,
        notifChat: dto.notifChat,
      },
    });
    return this.presentUser(user);
  }

  async setAvatar(userId: string, avatarUrl: string) {
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: { avatarUrl },
    });
    return this.presentUser(user);
  }

  async issueSession(user: {
    id: string;
    phone: string | null;
    role: 'CUSTOMER' | 'COURIER' | 'ADMIN';
    name: string | null;
    accountType: 'PERSONAL' | 'BUSINESS' | null;
    avatarUrl: string | null;
    notifOrders: boolean;
    notifChat: boolean;
  }) {
    const refreshToken = randomBytes(32).toString('hex');
    await this.prisma.refreshSession.create({
      data: {
        userId: user.id,
        tokenHash: this.hashToken(refreshToken),
        expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
    });
    return {
      accessToken: this.jwt.signAccess({ id: user.id, phone: user.phone ?? '', role: user.role }),
      refreshToken,
      user: this.presentUser(user),
      next: user.role === 'ADMIN' ? 'admin' : user.role === 'COURIER' ? 'courier' : user.name && user.accountType ? 'home' : 'complete_profile',
    };
  }

  presentUser(user: {
    id: string;
    phone: string | null;
    name: string | null;
    accountType: 'PERSONAL' | 'BUSINESS' | null;
    role: 'CUSTOMER' | 'COURIER' | 'ADMIN';
    avatarUrl: string | null;
    notifOrders: boolean;
    notifChat: boolean;
  }) {
    return {
      id: user.id,
      phone: user.phone,
      name: user.name,
      accountType: user.accountType,
      role: user.role,
      avatarUrl: user.avatarUrl,
      notifOrders: user.notifOrders,
      notifChat: user.notifChat,
    };
  }

  private async hashPassword(password: string) {
    const salt = randomBytes(16).toString('hex');
    const hash = (await scryptAsync(password, salt, 32)) as Buffer;
    return `scrypt:${salt}:${hash.toString('hex')}`;
  }

  private async verifyPassword(password: string, stored: string) {
    const [kind, salt, hex] = stored.split(':');
    if (kind !== 'scrypt' || !salt || !hex) return false;
    const hash = (await scryptAsync(password, salt, 32)) as Buffer;
    const expected = Buffer.from(hex, 'hex');
    if (hash.length !== expected.length) return false;
    return timingSafeEqual(hash, expected);
  }

  private hashCode(code: string) {
    return createHash('sha256')
      .update(`${this.config.getOrThrow<string>('OTP_PEPPER')}:${code}`)
      .digest('hex');
  }

  private hashToken(token: string) {
    return createHash('sha256').update(token).digest('hex');
  }
}
