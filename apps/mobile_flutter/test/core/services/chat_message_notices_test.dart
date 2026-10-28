import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/services/chat_message_notices.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('history and own messages do not ring; only newly received messages do',
      () {
    final known = <String>{};
    expect(
        newIncomingChatMessages(
            known: known,
            initialized: false,
            messages: [
              {'id': 'old', 'isMine': false}
            ],
            role: 'PASSENGER'),
        isEmpty);
    final incoming = newIncomingChatMessages(
        known: known,
        initialized: true,
        messages: [
          {'id': 'old', 'isMine': false},
          {'id': 'own', 'isMine': true},
          {'id': 'new', 'isMine': false}
        ],
        role: 'PASSENGER');
    expect(incoming.map((m) => m['id']), ['new']);
  });
  test(
      'FCM, realtime and polling ring once per message; notification failure is harmless',
      () async {
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var sounds = 0, notices = 0;
    final service = ChatMessageNotices(sound: (_, __) async {
      sounds++;
    }, notification: (_) async {
      notices++;
      throw StateError('unsupported');
    });
    final data = <String, dynamic>{
      'kind': 'INTERCITY',
      'orderId': 'trip',
      'messageId': 'one',
      'recipientRole': 'DRIVER'
    };
    final events = <Map<String, dynamic>>[];
    final sub = service.events.listen(events.add);
    await Future.wait(
        [service.notify(data), service.notify(data), service.notify(data)]);
    expect(sounds, 1);
    expect(notices, 1);
    expect(events.single['route'], contains('intercityRequestId=trip'));
    await service.notify({...data, 'messageId': 'two'});
    expect(sounds, 2);
    await sub.cancel();
    await service.dispose();
  });
}
