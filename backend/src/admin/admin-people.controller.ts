import {Body,Controller,Get,Patch,Post,Param,Query,Request,UseGuards,ForbiddenException,BadRequestException,Header,NotFoundException} from '@nestjs/common';
import {JwtAuthGuard} from '../auth/jwt-auth.guard';
import {PrismaService} from '../prisma.service';
import {AdminService} from './admin.service';
import {OrdersService} from '../orders/orders.service';
import {IntercityService} from '../intercity/intercity.service';
import {customerSelect,listCustomers,customerOverview,customerTrips,customerTransactions,customerEdit,editDriverRecord} from './customer-records';
@Controller('admin') @UseGuards(JwtAuthGuard)
export class AdminPeopleController {
 constructor(private readonly db:PrismaService,private readonly admin:AdminService,private readonly intercity:IntercityService,private readonly orders:OrdersService){}
 private async permit(req:any,key:string){if(!await this.admin.adminHasPermission(req.user.sub,key))throw new ForbiddenException('Нет доступа к этому разделу');}
 @Get('people-cities') async cities(@Request()req,@Query('search')search:string){await this.permit(req,'users.manage');return this.db.city.findMany({where:{isActive:true,name:{contains:String(search||'').slice(0,100),mode:'insensitive'}},take:30,select:{id:true,name:true,countryCode:true,region:true},orderBy:{name:'asc'}});}
 @Get('people') @Header('Cache-Control','no-store') async people(@Request()req,@Query()q:any){await this.permit(req,q.kind==='driver'?'drivers.view':'users.view');return listCustomers(this.db,q);}
 @Get('people/:id') @Header('Cache-Control','no-store') async person(@Request()req,@Param('id')id:string){await this.permit(req,'users.view');return customerOverview(this.db,id,await this.admin.adminHasPermission(req.user.sub,'finance.view'));}
 @Get('people/:id/referrals') async referrals(@Request()req,@Param('id')id:string,@Query()q:any){await this.permit(req,'users.view');const u=await this.db.user.findUnique({where:{id},select:{refCode:true}});if(!u)throw new NotFoundException('Пользователь не найден');return listCustomers(this.db,{...q,invitedBy:u.refCode});}
 @Get('people/:id/trips') @Header('Cache-Control','no-store') async trips(@Request()req,@Param('id')id:string,@Query()q:any){await this.permit(req,'users.view');await this.permit(req,'orders.view');return customerTrips(this.db,{...q,userId:id});}
 @Get('people/:id/transactions') @Header('Cache-Control','no-store') async transactions(@Request()req,@Param('id')id:string,@Query()q:any){await this.permit(req,'finance.view');return customerTransactions(this.db,id,q);}
 @Get('trip-register') @Header('Cache-Control','no-store') async register(@Request()req,@Query()q:any){await this.permit(req,'orders.view');return customerTrips(this.db,q);}
 @Get('people/:id/documents') async documents(@Request()req,@Param('id')id:string){await this.permit(req,'drivers.view');return this.db.driverProfile.findUnique({where:{userId:id},select:{selfieUrl:true,passportUrl:true,driverLicenseUrl:true,techPassportFrontUrl:true,techPassportBackUrl:true}});}
 @Patch('people/:id/driver') async editDriver(@Request()req,@Param('id')id:string,@Body()body:any){await this.permit(req,'drivers.manage');return this.db.$transaction(async tx=>{const result=await editDriverRecord(tx,id,body);await tx.adminAuditLog.create({data:{adminId:req.user.sub,action:'driver.profile.update',targetType:'DriverProfile',targetId:result.profile.id,details:{reason:result.reason,fields:body.fields,carChanged:result.carChanged}}});return {profile:result.profile,carChanged:result.carChanged};});}
 @Patch('people/:id') async edit(@Request()req,@Param('id')id:string,@Body()body:any){
  await this.permit(req,'users.manage');const {data,reason}=customerEdit(body);
  try{return await this.db.$transaction(async tx=>{const before=await tx.user.findUnique({where:{id},select:{id:true,name:true,phone:true,cityId:true,blockedAt:true,role:true}});if(!before)throw new NotFoundException('Пользователь не найден');if(before.role==='ADMIN')throw new ForbiddenException('Учётные записи администраторов изменяются в разделе доступа');
   if(data.phone===before.phone)delete data.phone;
   if('blockedAt'in data&&!!data.blockedAt===!!before.blockedAt)delete data.blockedAt;
   if(!('phone'in data)&&!('blockedAt'in data))delete data.authVersion;
   if(data.cityId&&!await tx.city.findUnique({where:{id:data.cityId}}))throw new BadRequestException('Город не найден');
   const user=await tx.user.update({where:{id},data,select:customerSelect});if(data.authVersion)await tx.refreshToken.deleteMany({where:{userId:id}});
   await tx.adminAuditLog.create({data:{adminId:req.user.sub,action:'user.profile.update',targetType:'User',targetId:id,details:{reason,before,after:{name:user.name,phone:user.phone,cityId:user.cityId,blockedAt:user.blockedAt}}}});return {user};});}catch(e:any){if(e.code==='P2002')throw new BadRequestException('Этот телефон уже принадлежит другому аккаунту');throw e;}
 }
 @Post('trip-register/:source/:id/cancel') async cancel(@Request()req,@Param('source')source:string,@Param('id')id:string,@Body()body:any){
  await this.permit(req,'orders.manage');const reason=typeof body.reason==='string'?body.reason.trim():'';if(reason.length<5||reason.length>1000)throw new BadRequestException('Укажите причину отмены, от 5 до 1000 символов');
  let result:any;if(source==='ORDER'){const order=await this.db.order.findUnique({where:{id},select:{passengerId:true}});if(!order)throw new NotFoundException('Заказ не найден');result=await this.orders.cancelOrder(id,order.passengerId);}else if(source==='MARKET'){const order=await this.db.intercityRequest.findUnique({where:{id},select:{passengerId:true}});if(!order)throw new NotFoundException('Заказ не найден');result=await this.intercity.cancelRequest(order.passengerId,id);}else throw new BadRequestException('Неизвестный тип заказа');
  await this.admin.logAdminAction({at:new Date().toISOString(),adminId:req.user.sub,role:'ADMIN',action:'order.support.cancel',target:id,details:{source,reason},status:'SUCCESS'});return {success:true,status:result.status};
 }
}
