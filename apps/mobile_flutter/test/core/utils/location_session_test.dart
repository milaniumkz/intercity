import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/location_session.dart';
import 'package:intercity_mobile/core/utils/browser_location_model.dart';

void main() {
  test('home and booking share an in-flight fix and retain it after navigation',
      () async {
    final session = LocationSession();
    final result = Completer<BrowserLocation?>();
    var calls = 0;
    Future<BrowserLocation?> provider() {
      calls++;
      return result.future;
    }

    final home = session.locate(provider);
    final booking = session.locate(provider);
    result.complete(
        const BrowserLocation(latitude: 49.9, longitude: 82.6, accuracy: 10));
    expect((await booking)?.latitude, 49.9);
    await home;
    expect(session.freshFix?.longitude, 82.6);
    await session.locate(provider);
    expect(calls, 1);
  });
  test('denied auto location does not repeat permission; GPS allows a retry',
      () async {
    final session = LocationSession();
    var calls = 0;
    Future<BrowserLocation?> provider() async {
      calls++;
      return null;
    }

    await session.locate(provider);
    await session.locate(provider);
    expect(calls, 1);
    await session.locate(provider, retry: true);
    expect(calls, 2);
  });
}
