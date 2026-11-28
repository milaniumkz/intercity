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
  Map? reply;
  String clock(int n) => n.toString().padLeft(2,'0');
  DateTime? sentAt(Map row) {
    final time = row['time'];
    return time is num && time > 0 ? DateTime.fromMillisecondsSinceEpoch(time.toInt()*1000) : null;
  }
  String day(DateTime date) => '${clock(date.day)}.${clock(date.month)}.${date.year}';
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
    setState(() {chat=id; title=name; rows=[]; error=''; reply=null; draft.clear();});
    refresh();
  }

  Future<void> send() async {
    if (sending || draft.text.trim().isEmpty || chat == null) return;
    setState(() => sending = true);
    try {
      await AdminApiClient.instance.post('/admin/whatsapp/dialogs/${Uri.encodeComponent(chat!)}/messages',data:{'text':draft.text.trim(),if(reply!=null) 'replyTo':reply!['id']});
      if (!mounted) return;
      setState(() {draft.clear(); reply=null;});
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
    Expanded(child:ListView.builder(reverse:chat!=null,itemCount:rows.length,itemBuilder:(_,i){
      final index=chat==null?i:rows.length-1-i;
      final row=rows[index];
      if(chat==null) return ListTile(title:Text(row['name'].toString()),onTap:()=>open(row['id'] as String,row['name'].toString()));
      final mine=row['mine']==true;
      final date=sentAt(row);
      final prev=index>0?sentAt(rows[index-1]):null;
      final ack=row['ack'];
      final colors=Theme.of(context).colorScheme;
      return Column(children:[
        if(date!=null && (prev==null || !DateUtils.isSameDay(date,prev))) Padding(
          padding:const EdgeInsets.symmetric(vertical:8),child:Text(day(date))),
        Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,child:FractionallySizedBox(
          widthFactor:.84,alignment:mine?Alignment.centerRight:Alignment.centerLeft,child:Align(
          alignment:mine?Alignment.centerRight:Alignment.centerLeft,child:Container(
          margin:const EdgeInsets.symmetric(vertical:3,horizontal:8),padding:const EdgeInsets.fromLTRB(12,8,6,4),
          decoration:BoxDecoration(color:mine?colors.primaryContainer:colors.surfaceContainerHighest,borderRadius:BorderRadius.circular(14)),
          child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
            if(row['quote']!=null) Text('▎ ${row['quote']}',maxLines:3,overflow:TextOverflow.ellipsis),
            SelectableText(row['text'].toString()),
            Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:5,children:[
              if(date!=null) Text('${clock(date.hour)}:${clock(date.minute)}',style:Theme.of(context).textTheme.labelSmall),
              if(mine && ack is num && ack>=0) Tooltip(message:ack>=3?'Прочитано':ack==2?'Доставлено':ack==1?'Отправлено':'Ожидает отправки',
                child:Icon(ack>=2?Icons.done_all:ack==1?Icons.done:Icons.schedule,size:16,color:ack>=3?Colors.blue:null)),
              IconButton(tooltip:'Ответить на сообщение',visualDensity:VisualDensity.compact,icon:const Icon(Icons.reply,size:18),
                onPressed:sending?null:()=>setState(()=>reply=row)),
            ]),
          ]))))),
      ]);
    })),
    if(reply!=null) ListTile(leading:const Icon(Icons.reply),title:Text(reply!['mine']==true?'Ответ на ваше сообщение':'Ответ клиенту'),
      subtitle:Text(reply!['text'].toString(),maxLines:2,overflow:TextOverflow.ellipsis),
      trailing:IconButton(tooltip:'Убрать цитату',onPressed:sending?null:()=>setState(()=>reply=null),icon:const Icon(Icons.close))),
    if(chat!=null) Row(children:[
      Expanded(child:TextField(controller:draft,enabled:!sending,maxLength:4096,decoration:const InputDecoration(labelText:'Сообщение клиенту'))),
      IconButton(onPressed:sending?null:send,tooltip:'Отправить',icon:const Icon(Icons.send)),
    ]),
  ]));
}
