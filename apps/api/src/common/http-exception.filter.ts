import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus } from '@nestjs/common';
import { Response } from 'express';

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<Response>();
    if (exception instanceof HttpException) {
      const body = exception.getResponse();
      const status = exception.getStatus();
      if (typeof body === 'object' && body && 'code' in body) {
        response.status(status).json(body);
        return;
      }
      const message =
        typeof body === 'string'
          ? body
          : Array.isArray((body as { message?: unknown }).message)
            ? ((body as { message: string[] }).message[0] ?? 'البيانات غير مكتملة.')
            : ((body as { message?: string }).message ?? 'تعذر تنفيذ الطلب.');
      response.status(status).json({ code: 'REQUEST_FAILED', message });
      return;
    }
    console.error(exception);
    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      code: 'SERVER_ERROR',
      message: 'حصل خطأ غير متوقع. حاول مرة أخرى.',
    });
  }
}
