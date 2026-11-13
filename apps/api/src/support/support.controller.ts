import { Body, Controller, Get, Inject, Param, Post, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString, Length } from 'class-validator';
import { HttpStatus } from '@nestjs/common';
import { TicketKind } from '@prisma/client';
import { AuthGuard } from '../common/auth.guard';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { ApiError } from '../common/api-error';
import { FAQ } from '../catalog/catalog';
import { PrismaService } from '../prisma/prisma.service';

const KINDS = ['ORDER', 'COURIER', 'COLLECTION', 'LATE', 'DAMAGED', 'MISSING', 'OTHER'] as const;

class TicketDto {
  @IsIn(KINDS)
  kind!: TicketKind;

  @IsString()
  @Length(3, 80)
  subject!: string;

  @IsString()
  @Length(5, 800)
  message!: string;

  @IsOptional()
  @IsString()
  orderId?: string;
}

class TicketMessageDto {
  @IsString()
  @Length(1, 800)
  body!: string;
}

@Controller()
export class SupportController {
  constructor(@Inject(PrismaService) private readonly prisma: PrismaService) {}

  @Get('support/faq')
  faq() {
    return FAQ;
  }

  @Get('support/tickets')
  @UseGuards(AuthGuard)
  async tickets(@CurrentUser() user: AuthUser) {
    return this.prisma.supportTicket.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: 'desc' },
      take: 40,
    });
  }

  @Get('support/tickets/:id')
  @UseGuards(AuthGuard)
  async ticket(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    const ticket = await this.prisma.supportTicket.findUnique({
      where: { id },
      include: { messages: { where: { internal: false }, orderBy: { createdAt: 'asc' } } },
    });
    if (!ticket || ticket.userId !== user.id) {
      throw new ApiError('NOT_FOUND', 'الشكوى غير موجودة.', HttpStatus.NOT_FOUND);
    }
    return ticket;
  }

  @Post('support/tickets')
  @UseGuards(AuthGuard)
  async create(@CurrentUser() user: AuthUser, @Body() dto: TicketDto) {
    if (dto.orderId) {
      const order = await this.prisma.deliveryOrder.findUnique({ where: { id: dto.orderId } });
      if (!order || order.userId !== user.id) {
        throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
      }
    }
    const count = await this.prisma.supportTicket.count();
    return this.prisma.supportTicket.create({
      data: {
        publicNumber: `SP-${String(count + 1).padStart(5, '0')}`,
        userId: user.id,
        kind: dto.kind,
        subject: dto.subject.trim(),
        message: dto.message.trim(),
        orderId: dto.orderId,
        messages: { create: { sender: 'CUSTOMER', senderId: user.id, body: dto.message.trim() } },
      },
    });
  }

  @Post('support/tickets/:id/messages')
  @UseGuards(AuthGuard)
  async reply(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: TicketMessageDto) {
    const ticket = await this.prisma.supportTicket.findUnique({ where: { id } });
    if (!ticket || ticket.userId !== user.id) {
      throw new ApiError('NOT_FOUND', 'الشكوى غير موجودة.', HttpStatus.NOT_FOUND);
    }
    if (ticket.status === 'CLOSED') throw new ApiError('TICKET_CLOSED', 'الشكوى مغلقة.');
    return this.prisma.supportMessage.create({
      data: { ticketId: id, sender: 'CUSTOMER', senderId: user.id, body: dto.body.trim() },
    });
  }

  @Get('legal/terms')
  terms() {
    return {
      title: 'الشروط والأحكام',
      body: 'دليفريه منصة لطلب مندوبي التوصيل. سعر التوصيل يحدده الخادم، وقيمة المنتجات التي يدخلها التاجر ليست مبلغًا موثقًا من المنصة. اكتمال التوصيل لا يعني تسوية الأموال. الإلغاء بعد استلام البضاعة يتم عبر الدعم.',
    };
  }

  @Get('legal/privacy')
  privacy() {
    return {
      title: 'سياسة الخصوصية',
      body: 'نجمع رقم الهاتف والاسم والعناوين اللازمة لتنفيذ التوصيل. دفتر عملاء النشاط مرتبط بذلك النشاط فقط، ولا يظهر لمحل آخر. لا يطلع مستخدم على شكاوى أو طلبات غيره.',
    };
  }
}
