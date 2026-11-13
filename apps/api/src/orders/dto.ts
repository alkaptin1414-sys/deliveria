import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  Length,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';

export class PlaceDto {
  @IsString()
  @Length(2, 80)
  name!: string;

  @IsString()
  @Length(3, 180)
  line!: string;

  @IsOptional()
  @IsString()
  @Length(0, 180)
  details?: string;

  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng!: number;
}

export class QuoteDto {
  @ValidateNested()
  @Type(() => PlaceDto)
  pickup!: PlaceDto;

  @ValidateNested()
  @Type(() => PlaceDto)
  dropoff!: PlaceDto;

  @IsIn(['SMALL', 'MEDIUM', 'LARGE'])
  size!: 'SMALL' | 'MEDIUM' | 'LARGE';

  @IsBoolean()
  fragile!: boolean;

  @IsIn(['MOTORCYCLE', 'CAR'])
  vehicle!: 'MOTORCYCLE' | 'CAR';

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  goodsMinor?: number;

  @IsOptional()
  @IsBoolean()
  goodsPrepaid?: boolean;

  @IsOptional()
  @IsBoolean()
  collectGoods?: boolean;

  @IsOptional()
  @IsIn(['RECIPIENT', 'BUSINESS'])
  deliveryPayer?: 'RECIPIENT' | 'BUSINESS';
}

export class CreateOrderDto extends QuoteDto {
  @IsString()
  @Length(2, 60)
  recipientName!: string;

  @IsString()
  recipientPhone!: string;

  @IsString()
  parcelType!: string;

  @IsString()
  @Length(2, 180)
  parcelDescription!: string;

  @IsOptional()
  @IsString()
  @Length(0, 240)
  notes?: string;

  @IsOptional()
  @IsString()
  photoUrl?: string;

  @IsOptional()
  @IsBoolean()
  saveRecipient?: boolean;

  @IsOptional()
  @IsString()
  courierId?: string;
}

export class CancelDto {
  @IsIn(['NO_LONGER_NEEDED', 'WRONG_ADDRESS', 'COURIER_LATE', 'CREATED_BY_MISTAKE', 'OTHER'])
  code!: 'NO_LONGER_NEEDED' | 'WRONG_ADDRESS' | 'COURIER_LATE' | 'CREATED_BY_MISTAKE' | 'OTHER';

  @IsOptional()
  @IsString()
  @Length(0, 180)
  reason?: string;
}

export class ReviewDto {
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  @Max(5)
  rating!: number;

  @IsOptional()
  @IsString({ each: true })
  tags?: string[];

  @IsOptional()
  @IsString()
  @Length(0, 240)
  comment?: string;
}

export class MessageDto {
  @IsString()
  @Length(1, 500)
  body!: string;
}

export class CourierStatusDto {
  @IsIn(['EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'])
  status!: 'EN_ROUTE_PICKUP' | 'PICKED_UP' | 'EN_ROUTE_DROPOFF';
}

export class VerifyDeliveryDto {
  @IsString()
  code!: string;
}

export class LocationDto {
  @Type(() => Number)
  @IsNumber()
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  lng!: number;
}
