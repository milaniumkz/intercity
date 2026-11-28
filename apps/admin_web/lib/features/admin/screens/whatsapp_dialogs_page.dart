import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';
import 'admin_dashboard_page.dart';

class WhatsappDialogsPage extends StatefulWidget {
  const WhatsappDialogsPage({super.key});
  @override
  State<WhatsappDialogsPage> createState() => _DialogsState();
}

class _DialogsState extends State<WhatsappDialogsPage> {
  final draft = TextEditingController();
  Timer? timer;
  String? chat;
  String title = 'Диалоги WhatsApp';
  String error = '';
  List rows = [];
  int request = 0;
  bool sending = false;
  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 8), (_) => refresh());
  }

  Future<void> refresh() async {
    final serial = ++request;
    final path = chat == null ? '/admin/whatsapp/dialogs' : '/admin/whatsapp/dialogs/${Uri.encodeComponent(chat!)}/messages';
    try {
      final result = await AdminApiClient.instance.get(path);
      if (mounted && serial == request) setState(() {rows = result.data as List; error = '';});
    } catch (_) {
      if (mounted && serial == request) setState(() => error = 'Не удалось загрузить переписку. Проверьте подключение канала.');
    }
  }

  void open(String? id, String name) {
    setState(() {chat=id; title=name; rows=[]; error=''; draft.clear();});
    refresh();
  }

  Future<void> send() async {
    if (sending || draft.text.trim().isEmpty || chat == null) return;
    setState(() => sending = true);
    try {
      await AdminApiClient.instance.post('/admin/whatsapp/dialogs/${Uri.encodeComponent(chat!)}/messages',data:{'text':draft.text.trim()});
      if (!mounted) return;
      draft.clear();
      await refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Отправка не подтверждена. Проверьте историю перед повтором.')));
    } finally {
      if (mounted) setState(() => sending=false);
    }
  }

  @override
  void dispose() {timer?.cancel(); draft.dispose(); super.dispose();}
  @override
  Widget build(BuildContext context) => AdminShell(title:title,subtitle:'Личная переписка служебного номера',child:Column(children:[
    if(chat!=null) TextButton(onPressed:sending?null:()=>open(null,'Диалоги WhatsApp'),child:const Text('К списку диалогов')),
    if(error.isNotEmpty) Text(error),
    Expanded(child:ListView.builder(itemCount:rows.length,itemBuilder:(_,i){
      final row=rows[i];
      if(chat==null) return ListTile(title:Text(row['name'].toString()),onTap:()=>open(row['id'] as String,row['name'].toString()));
      return ListTile(title:SelectableText(row['text'].toString()),subtitle:Text(row['mine']==true?'InterCity':'Клиент'));
    })),
    if(chat!=null) Row(children:[
      Expanded(child:TextField(controller:draft,enabled:!sending,maxLength:4096,decoration:const InputDecoration(labelText:'Сообщение клиенту'))),
      IconButton(onPressed:sending?null:send,tooltip:'Отправить',icon:const Icon(Icons.send)),
    ]),
  ]));
}
