import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';

Future<Map> providerSignIn(ApiClient api,String provider,{String? password,required bool Function() active}) async {
  final mode=password==null?'provider':'link';
  final start=await api.post('/auth/recovery/$mode/start',data:{'provider':provider});
  final url=Uri.parse(start.data['url'] as String);
  if(url.scheme!='https' || !{'accounts.google.com','appleid.apple.com'}.contains(url.host)) {
    throw StateError('Недопустимый адрес входа');
  }
  if(!await launchUrl(url,mode:LaunchMode.externalApplication,webOnlyWindowName:'_blank')) {
    throw StateError('Не удалось открыть сервис входа');
  }
  for(var attempt=0;attempt<95 && active();attempt++){
    await Future<void>.delayed(const Duration(seconds:3));
    if(!active()) break;
    final reply=await api.post('/auth/recovery/$mode/verify',data:{
      'provider':provider,'nonce':start.data['nonce'],'ticket':start.data['ticket'],if(password!=null)'password':password,
    });
    if(reply.data['pending']!=true) return reply.data as Map;
  }
  throw StateError('Время подтверждения истекло');
}
