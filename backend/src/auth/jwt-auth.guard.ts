import { ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
 async canActivate(context: ExecutionContext): Promise<boolean> {
  const ok = await super.canActivate(context); const req = context.switchToHttp().getRequest();
  if (req.user?.mustChangePassword && !String(req.path).endsWith('/auth/change-password') && !String(req.path).endsWith('/auth/me')) throw new ForbiddenException('MUST_CHANGE_PASSWORD');
  const path=String(req.path).replace(/^\/api(?=\/)/,'');
  const identityAllowed=['/auth/me','/me','/auth/change-password','/auth/delete-account','/auth/push-token'].includes(path) || path.startsWith('/auth/identity/') || (path==='/driver/profile' && req.method==='POST');
  if(req.user?.identityRequired && !identityAllowed) throw new ForbiddenException({code:'IDENTITY_REQUIRED',message:'Пройдите видеопроверку личности в приложении или веб-версии InterCity'});
  const driverAction=(path.startsWith('/driver/')&&!['/driver/profile','/driver/service-modes','/driver/earnings'].includes(path)&&!path.startsWith('/driver/docs/')) || /^\/orders\/[^/]+\/offers$/.test(path) || /^\/intercity\/requests\/[^/]+\/(offers|accept-passenger-price)$/.test(path) || (path==='/ridesharing/trips'&&req.method==='POST');
  if(req.user?.driverDocumentsRequired&&driverAction)throw new ForbiddenException({code:'DRIVER_DOCUMENTS_REQUIRED',message:'Сверка лица с удостоверением и автомобиля не завершена. Откройте раздел «Документы и проверка».'});
  return !!ok;
 }
}
