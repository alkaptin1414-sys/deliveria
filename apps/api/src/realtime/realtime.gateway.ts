import { Inject } from '@nestjs/common';
import { OnGatewayConnection, WebSocketGateway } from '@nestjs/websockets';
import { IncomingMessage } from 'http';
import { WebSocket } from 'ws';
import { JwtService } from '../auth/jwt.service';
import { RealtimeService } from './realtime.service';

@WebSocketGateway({ path: '/v1/realtime' })
export class RealtimeGateway implements OnGatewayConnection {
  constructor(
    @Inject(JwtService) private readonly jwt: JwtService,
    @Inject(RealtimeService) private readonly realtime: RealtimeService,
  ) {}

  handleConnection(client: WebSocket, request: IncomingMessage) {
    const url = new URL(request.url ?? '', 'http://localhost');
    const token = url.searchParams.get('token');
    if (!token) {
      client.close();
      return;
    }
    try {
      const user = this.jwt.verifyAccess(token);
      this.realtime.add(user.id, client);
      client.send(JSON.stringify({ type: 'ready' }));
      client.on('close', () => this.realtime.remove(user.id, client));
    } catch {
      client.close();
    }
  }
}
