import 'dart:async';
import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';
import 'admin_dashboard_page.dart';

class WhatsappPage extends StatefulWidget {
  const WhatsappPage({super.key});
  @override
  State<WhatsappPage> createState() => _WhatsappState();
}

class _WhatsappState extends State<WhatsappPage> {
  Timer? timer;
  bool loading = false;
  bool sending = false;
  String phone = '';
  String message = '';
  Future<void> testDelivery() async {
    if (sending) return;
    setState(() { sending = true; message = ''; });
    try {
      await AdminApiClient.instance.post('/admin/whatsapp/test', data: {'phone':phone.trim()});
      if (mounted) setState(() => message = 'WhatsApp принял сообщение. Проверьте WhatsApp на выбранном телефоне.');
    } on DioException catch (error) {
      final body = error.response?.data;
      final reason = body is Map ? body['message'] : null;
      if (mounted) setState(() => message = reason is String && RegExp('[А-Яа-я]').hasMatch(reason) ? reason : 'Не удалось отправить сообщение. Проверьте соединение и повторите.');
    } catch (_) {
      if (mounted) setState(() => message = 'Отправить не удалось. Проверьте номер профиля и состояние канала.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }
  bool switching = false;
  Future<void> logout() async {
    final approved = await showDialog<bool>(context:context,builder:(dialog)=>AlertDialog(
      title:const Text('Выйти из WhatsApp?'),
      content:const Text('Отправка кодов и переписка приостановятся до подключения номера по QR-коду.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('Отмена')),
        FilledButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('Выйти из WhatsApp')),
      ],
    ));
    if (!mounted || approved != true) return;
    setState(() => switching = true);
    try {
      await AdminApiClient.instance.post('/admin/whatsapp/logout');
      if (mounted) setState(() { status = 'Отключён'; image = null; message = 'Подключите нужный номер через QR-код.'; });
    } catch (_) {
      if (mounted) setState(() => message = 'Выход не подтверждён. Проверьте состояние канала.');
    } finally {
      if (mounted) setState(() => switching = false);
      await refresh();
    }
  }
  String status = 'Загрузка';
  String? image;
  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
  }

  Future<void> refresh({bool connect = false}) async {
    if (loading || switching || !mounted) return;
    loading = true;
    try {
      if (connect) await AdminApiClient.instance.post('/admin/whatsapp/connect');
      final result = await AdminApiClient.instance.get('/admin/whatsapp');
      if (mounted) {
        setState(() {
        image = result.data['image'] as String?;
        status = const {'WORKING':'Подключён','SCAN_QR_CODE':'Отсканируйте QR-код','STARTING':'Подключается','STOPPED':'Отключён','FAILED':'Соединение потеряно'}[result.data['status']] ?? 'Уточняется';
        });
      }
    } catch (_) {
      if (mounted) setState(() {image = null; status = 'Не удалось получить состояние канала. Проверьте доступ и настройки сервера.';});
    } finally { loading = false; }
  }

  @override
  void dispose() {timer?.cancel(); super.dispose();}

  @override
  Widget build(BuildContext context) => AdminShell(title:'Канал WhatsApp',subtitle:'Отправка кодов восстановления',child:ListView(
    padding:const EdgeInsets.all(20),children:[
      Text(status),
      if (status == 'Подключён') OutlinedButton.icon(onPressed:switching || sending ? null : logout,icon:const Icon(Icons.logout),label:const Text('Выйти из WhatsApp')),
      TextButton(onPressed:()=>Navigator.pushNamed(context,'/whatsapp-dialogs'),child:const Text('Открыть диалоги WhatsApp')),
      if (status == 'Подключён') TextField(
        keyboardType: TextInputType.phone, enabled: !sending,
        decoration: const InputDecoration(labelText:'Тестовый номер WhatsApp', hintText:'+7', helperText:'Оставьте пустым для отправки на телефон из профиля.'),
        onChanged:(value) => phone = value,
      ),
      if (status == 'Подключён') FilledButton(onPressed:sending ? null : testDelivery, child:const Text('Отправить тестовый код')),
      if (message.isNotEmpty) Text(message),
      if (image != null) ...[
        const Text('На служебном телефоне откройте WhatsApp → Связанные устройства → Привязка устройства.'),
        Center(child:Image.memory(base64Decode(image!),width:256,height:256)),
      ],
      if (status != 'Подключён') FilledButton(onPressed:()=>refresh(connect:true),child:const Text('Подключить WhatsApp')),
    ]));
}
