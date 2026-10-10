import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:intercity_mobile/core/utils/browser_location_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/location_session.dart';
import 'package:intercity_mobile/core/utils/browser_location_model.dart';

void main() {
  test('concurrent city and pickup lookups share one reverse request',
      () async {
    final session = LocationSession();
    final result = Completer<Map<String, dynamic>>();
    var calls = 0;
    Future<Map<String, dynamic>> provider() {
      calls++;
      return result.future;
    }

    const point = LatLng(49.9, 82.6);
    final city = session.resolveReverse(point, provider);
    final address = session.resolveReverse(point, provider);
    result.complete({
      'address': 'Шакарима 10',
      'cityResolved': true,
      'addressResolved': true
    });
    expect(await city, await address);
    await session.resolveReverse(point, provider);
    expect(calls, 1);
  });

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
  test('transient timeout allows another request; denial does not', () async {
    final session = LocationSession();
    var calls = 0;
    Future<BrowserLocation?> timeout() async {
      calls++;
      throw const BrowserLocationException(BrowserLocationFailure.timeout);
    }

    for (var i = 0; i < 2; i++) {
      await expectLater(
          session.locate(timeout), throwsA(isA<BrowserLocationException>()));
    }
    expect(calls, 2);
    Future<BrowserLocation?> denied() async {
      calls++;
      throw const BrowserLocationException(
          BrowserLocationFailure.permissionDenied);
    }

    await expectLater(
        session.locate(denied), throwsA(isA<BrowserLocationException>()));
    await expectLater(
        session.locate(denied), throwsA(isA<BrowserLocationException>()));
    expect(calls, 3);
    final fix = await session.locate(
        () async => const BrowserLocation(
            latitude: 49.9, longitude: 82.6, accuracy: 10),
        retry: true);
    expect(fix?.latitude, 49.9);
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
