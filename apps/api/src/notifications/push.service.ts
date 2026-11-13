import { Injectable } from '@nestjs/common';

@Injectable()
export class PushService {
  async send(userId: string, title: string, body: string, data: Record<string, string>) {
    void userId;
    void title;
    void body;
    void data;
    return { sent: 0, reason: 'PHONE_CHANNEL' as const };
  }
}
