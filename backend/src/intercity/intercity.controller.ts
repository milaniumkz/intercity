import {
  Controller,
  Get,
  Post,
  Body,
  Param,
  UseGuards,
  Request,
} from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { IntercityService } from "./intercity.service";
import { JwtAuthGuard } from "../auth/jwt-auth.guard";

@ApiTags("intercity")
@Controller("intercity")
export class IntercityController {
  constructor(private intercityService: IntercityService) {}

  @Post('requests/:id/rate')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  rateDriver(@Param('id') id: string, @Request() req, @Body() body: {rating?:unknown;reason?:unknown}) {
    return this.intercityService.rateDriver(id,req.user.sub,body.rating,body.reason);
  }

  @Get('requests/:id/chat')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  getChat(@Param('id') id: string, @Request() req) {
    return this.intercityService.getChat(id,req.user.sub);
  }

  @Post('requests/:id/chat')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  sendChat(@Param('id') id: string, @Request() req, @Body() body: {text?:unknown}) {
    return this.intercityService.sendChat(id,req.user.sub,body.text);
  }

  @Post("requests")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: "Create intercity request" })
  async createRequest(@Request() req, @Body() body: any) {
    return this.intercityService.createRequest(req.user.sub, body);
  }

  @Post('requests/:id/passenger-leaving')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  async passengerLeaving(@Param('id') id: string, @Request() req) {
    return this.intercityService.passengerLeaving(id, req.user.sub);
  }

  @Get("requests/open")
  @ApiOperation({ summary: "Get open intercity requests" })
  async getOpenRequests() {
    return this.intercityService.getOpenRequests();
  }

  @Get("requests/my")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: "Get my intercity requests" })
  async getMyRequests(@Request() req) {
    return this.intercityService.getMyRequests(req.user.sub);
  }

  @Get("requests/:id")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: "Get my intercity request details" })
  async getRequest(@Request() req, @Param("id") id: string) {
    return this.intercityService.getRequest(req.user.sub, id);
  }

  @Post('requests/:id/accept-passenger-price')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  async acceptPassengerPrice(@Request() req,@Param('id') id:string) {
    return this.intercityService.acceptPassengerPrice(req.user.sub,id);
  }

  @Post("requests/:id/offers")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: "Create offer for request" })
  async createOffer(
    @Request() req,
    @Param("id") id: string,
    @Body() body: { price: number; seats?: number; comment?: string },
  ) {
    return this.intercityService.createOffer(req.user.sub, id, body);
  }

  @Get("requests/:id/offers")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: "Get offers for request" })
  async getOffers(@Request() req, @Param("id") id: string) {
    return this.intercityService.getOffers(req.user.sub, id);
  }

  @Post('offers/:offerId/reject')
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  async rejectOffer(@Request() req, @Param('offerId') offerId: string) {
    return this.intercityService.rejectOffer(req.user.sub, offerId);
  }

  @Post("offers/:offerId/accept")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: "Accept offer" })
  async acceptOffer(@Request() req, @Param("offerId") offerId: string) {
    return this.intercityService.acceptOffer(req.user.sub, offerId);
  }

  @Post("requests/:id/cancel")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: "Cancel my intercity request" })
  async cancelRequest(@Request() req, @Param("id") id: string) {
    return this.intercityService.cancelRequest(req.user.sub, id);
  }

  @Post("requests/:id/status")
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({
    summary: "Update accepted intercity request status by driver",
  })
  async updateDriverRequestStatus(
    @Request() req,
    @Param("id") id: string,
    @Body() body: { status: string },
  ) {
    return this.intercityService.updateDriverRequestStatus(
      req.user.sub,
      id,
      body.status,
    );
  }
}
