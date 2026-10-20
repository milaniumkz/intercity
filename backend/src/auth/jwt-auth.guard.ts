import { ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
 async canActivate(context: ExecutionContext): Promise<boolean> {
  const ok = await super.canActivate(context); const req = context.switchToHttp().getRequest();
  if (req.user?.mustChangePassword && !String(req.path).endsWith('/auth/change-password') && !String(req.path).endsWith('/auth/me')) throw new ForbiddenException('MUST_CHANGE_PASSWORD');
  return !!ok;
 }
}
