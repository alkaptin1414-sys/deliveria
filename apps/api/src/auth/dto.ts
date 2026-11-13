import { IsEmail, IsIn, IsOptional, IsString, Length, Matches } from 'class-validator';

export class RequestOtpDto {
  @IsString()
  phone!: string;
}

export class VerifyOtpDto {
  @IsString()
  challengeId!: string;

  @Matches(/^\d{6}$/)
  code!: string;
}

export class RefreshDto {
  @IsString()
  refreshToken!: string;
}

export class CompleteProfileDto {
  @IsString()
  @Length(2, 60)
  name!: string;

  @IsIn(['PERSONAL', 'BUSINESS'])
  accountType!: 'PERSONAL' | 'BUSINESS';
}

export class UpdateMeDto {
  @IsOptional()
  @IsString()
  @Length(2, 60)
  name?: string;

  @IsOptional()
  notifOrders?: boolean;

  @IsOptional()
  notifChat?: boolean;
}

export class RegisterDto {
  @IsString()
  @Length(2, 80)
  name!: string;

  @IsEmail()
  email!: string;

  @IsString()
  @Length(8, 72)
  password!: string;

  @IsIn(['CUSTOMER', 'COURIER'])
  role!: 'CUSTOMER' | 'COURIER';
}

export class LoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  @Length(8, 72)
  password!: string;
}
