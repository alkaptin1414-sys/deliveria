import { Controller, Inject, Post, Query, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import { extname, join } from 'path';
import { randomBytes } from 'crypto';
import { mkdirSync } from 'fs';
import { ConfigService } from '@nestjs/config';
import { AuthGuard } from '../common/auth.guard';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { ApiError } from '../common/api-error';
import { AuthService } from '../auth/auth.service';

const root = join(process.cwd(), 'uploads');
mkdirSync(root, { recursive: true });

@Controller('uploads')
@UseGuards(AuthGuard)
export class StorageController {
  constructor(
    @Inject(ConfigService) private readonly config: ConfigService,
    @Inject(AuthService) private readonly auth: AuthService,
  ) {}

  @Post()
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: root,
        filename: (_req, file, cb) => {
          cb(null, `${randomBytes(8).toString('hex')}${extname(file.originalname || '.jpg')}`);
        },
      }),
      limits: { fileSize: 4 * 1024 * 1024 },
      fileFilter: (_req, file, cb) => {
        if (!file.mimetype.startsWith('image/')) {
          cb(new ApiError('INVALID_FILE', 'ارفع صورة فقط.'), false);
          return;
        }
        cb(null, true);
      },
    }),
  )
  async upload(
    @CurrentUser() user: AuthUser,
    @UploadedFile() file?: Express.Multer.File,
    @Query('purpose') purpose?: string,
  ) {
    if (!file) throw new ApiError('INVALID_FILE', 'اختَر صورة.');
    const base = this.config.get<string>('PUBLIC_BASE_URL') ?? 'http://localhost:3000';
    const url = `${base}/uploads/${file.filename}`;
    if (purpose === 'avatar') await this.auth.setAvatar(user.id, url);
    return { url };
  }
}
