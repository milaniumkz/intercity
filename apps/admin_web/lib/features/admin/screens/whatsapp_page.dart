import 'dart:async';
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
  String status = 'Загрузка';
  String? image;
  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
  }

  Future<void> refresh({bool connect = false}) async {
    if (loading) return;
    loading = true;
    try {
      if (connect) await AdminApiClient.instance.post('/admin/whatsapp/connect');
      final result = await AdminApiClient.instance.get('/admin/whatsapp');
      if (mounted) setState(() {
        image = result.data['image'] as String?;
        status = const {'WORKING':'Подключён','SCAN_QR_CODE':'Отсканируйте QR-код','STARTING':'Подключается','STOPPED':'Отключён','FAILED':'Соединение потеряно'}[result.data['status']] ?? 'Уточняется';
      });
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
      if (image != null) ...[
        const Text('На служебном телефоне откройте WhatsApp → Связанные устройства → Привязка устройства.'),
        Center(child:Image.memory(base64Decode(image!),width:256,height:256)),
      ],
      if (status != 'Подключён') FilledButton(onPressed:()=>refresh(connect:true),child:const Text('Подключить WhatsApp')),
    ]));
}
