import { Controller, Post, Get, Body, Param, UseGuards, Request, Patch } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { OrdersService } from './orders.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CreateOrderDto, PreviewOrderDto, UpdateOrderStatusDto, RateOrderDto, CreateOrderOfferDto } from './dto/orders.dto';

@ApiTags('orders')
@Controller('orders')
export class OrdersController {
    constructor(private ordersService: OrdersService) { }

    @Post('preview')
    @ApiOperation({ summary: 'Preview order price' })
    async preview(@Body() dto: PreviewOrderDto) {
        return this.ordersService.previewOrder(dto);
    }

    @Post()
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Create new order' })
    async create(@Request() req, @Body() dto: CreateOrderDto) {
        return this.ordersService.createOrder(req.user.sub, dto);
    }

    @Get('my')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Get my orders' })
    async getMyOrders(@Request() req) {
        return this.ordersService.getMyOrders(req.user.sub);
    }

    @Get('active')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    async getActive(@Request() req) {
        return this.ordersService.getActivePassengerOrder(req.user.sub);
    }

    @Get(':id')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Get order by ID' })
    async getOrder(@Param('id') id: string, @Request() req) {
        return this.ordersService.getOrder(id, {
            userId: req.user.sub,
            role: req.user.role,
        });
    }

    @Get(':id/chat')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Get order chat messages' })
    async getChat(@Param('id') id: string, @Request() req) {
        return this.ordersService.getOrderChat(id, {
            userId: req.user.sub,
            role: req.user.role,
        });
    }

    @Post(':id/chat')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Send order chat message' })
    async sendChat(@Param('id') id: string, @Request() req, @Body() body: { text?: string }) {
        return this.ordersService.sendOrderChatMessage(
            id,
            { userId: req.user.sub, role: req.user.role },
            body.text ?? '',
        );
    }

    @Post(':id/offers')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Create/update city auction offer' })
    async createOffer(@Param('id') id: string, @Request() req, @Body() dto: CreateOrderOfferDto) {
        return this.ordersService.createOrderOffer(id, req.user.sub, dto);
    }

    @Post('offers/:offerId/accept')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Accept city auction offer' })
    async acceptOffer(@Param('offerId') offerId: string, @Request() req) {
        return this.ordersService.acceptOrderOffer(offerId, req.user.sub);
    }

    @Post('offers/:offerId/reject')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Reject city auction offer' })
    async rejectOffer(@Param('offerId') offerId: string, @Request() req) {
        return this.ordersService.rejectOrderOffer(offerId, req.user.sub);
    }

    @Post(':id/cancel')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Cancel order' })
    async cancel(@Param('id') id: string, @Request() req) {
        return this.ordersService.cancelOrder(id, req.user.sub);
    }

    @Patch(':id/status')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Update order status' })
    async updateStatus(@Param('id') id: string, @Request() req, @Body() dto: UpdateOrderStatusDto) {
        return this.ordersService.updateOrderStatus(id, dto.status, {
            userId: req.user.sub,
            role: req.user.role,
        });
    }

    @Post(':id/status')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Update order status (POST alias for client compatibility)' })
    async updateStatusPost(@Param('id') id: string, @Request() req, @Body() dto: UpdateOrderStatusDto) {
        return this.ordersService.updateOrderStatus(id, dto.status, {
            userId: req.user.sub,
            role: req.user.role,
        });
    }

    @Post(':id/rate')
    @UseGuards(JwtAuthGuard)
    @ApiBearerAuth()
    @ApiOperation({ summary: 'Rate order' })
    async rate(@Param('id') id: string, @Request() req, @Body() dto: RateOrderDto) {
        return this.ordersService.rateOrder(id, req.user.sub, dto.rating, false);
    }
}
