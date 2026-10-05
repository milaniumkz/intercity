import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('global address search skips city radius filtering', () {
    expect(
      shouldApplyAddressSearchRadiusFilter(mode: 'CITY', anchor: null),
      isFalse,
    );
    expect(
      shouldApplyAddressSearchRadiusFilter(
        mode: 'CITY',
        anchor: const LatLng(43.222, 76.851),
      ),
      isTrue,
    );
    expect(
      shouldApplyAddressSearchRadiusFilter(
        mode: 'INTERCITY',
        anchor: const LatLng(43.222, 76.851),
      ),
      isFalse,
    );
  });

  test(
      'global address search fallback triggers on local failure or empty local results',
      () {
    expect(
      shouldFallbackToGlobalAddressSearch(
        localFailed: true,
        query: 'улица Астана 1',
        local: const [],
        allowGlobalFallback: true,
      ),
      isTrue,
    );
    expect(
      shouldFallbackToGlobalAddressSearch(
        localFailed: false,
        query: 'улица Астана 1',
        local: const [],
        allowGlobalFallback: true,
      ),
      isTrue,
    );
    expect(
      shouldFallbackToGlobalAddressSearch(
        localFailed: false,
        query: 'дом',
        local: const [
          {'displayName': 'local hit'}
        ],
        allowGlobalFallback: true,
      ),
      isFalse,
    );
    expect(
      shouldFallbackToGlobalAddressSearch(
        localFailed: true,
        query: 'улица Астана 1',
        local: const [],
        allowGlobalFallback: false,
      ),
      isFalse,
    );
  });

  test(
      'fixed city explicit search requires an unambiguous result to auto-apply',
      () {
    expect(
      shouldAutoApplyFirstAddressSearchResult(
        requiresConfirmedCoordinates: true,
        results: const [
          {'displayName': 'only hit'}
        ],
      ),
      isTrue,
    );
    expect(
      shouldAutoApplyFirstAddressSearchResult(
        requiresConfirmedCoordinates: true,
        results: const [
          {'displayName': 'first hit'},
          {'displayName': 'second hit'},
        ],
      ),
      isFalse,
    );
    expect(
      shouldAutoApplyFirstAddressSearchResult(
        requiresConfirmedCoordinates: false,
        results: const [
          {'displayName': 'first hit'},
          {'displayName': 'second hit'},
        ],
      ),
      isTrue,
    );
  });

  test('nearby anchored city address can win over global fallback noise', () {
    expect(
      shouldUseNearestAnchoredAddressResult(
        query: 'улица Астана 1',
        local: const [
          {
            'displayName': 'Аксу, улица Астана 1',
            'distanceKm': 27.18,
          },
          {
            'displayName': 'Тайынша, улица Астана 1',
            'distanceKm': 510.63,
          },
        ],
      ),
      isTrue,
    );

    expect(
      shouldUseNearestAnchoredAddressResult(
        query: 'астана',
        local: const [
          {
            'displayName': 'nearby',
            'distanceKm': 12.0,
          },
          {
            'displayName': 'far away',
            'distanceKm': 220.0,
          },
        ],
      ),
      isFalse,
    );

    expect(
      shouldUseNearestAnchoredAddressResult(
        query: 'улица Астана 1',
        local: const [
          {
            'displayName': 'first',
            'distanceKm': 140.0,
          },
          {
            'displayName': 'second',
            'distanceKm': 180.0,
          },
        ],
      ),
      isFalse,
    );
  });

  test('explicit address search prefers fresher last input over stale prefix',
      () {
    expect(
      resolveExplicitAddressSearchQuery(
        controllerText: 'улица Астана ',
        lastInputValue: 'улица Астана 1',
      ),
      'улица Астана 1',
    );

    expect(
      resolveExplicitAddressSearchQuery(
        controllerText: 'улица Астана 1',
        lastInputValue: 'улица Астана ',
      ),
      'улица Астана 1',
    );

    expect(
      resolveExplicitAddressSearchQuery(
        controllerText: 'Риддер, вокзал',
        lastInputValue: 'Риддер, вокзал',
      ),
      'Риддер, вокзал',
    );
  });

  test(
      'transient address changes are ignored during and right after explicit search',
      () {
    final now = DateTime(2026, 5, 16, 12);

    expect(
      shouldIgnoreTransientAddressChangeDuringExplicitSearch(
        explicitSearchInProgress: true,
        now: now,
        guardUntil: null,
      ),
      isTrue,
    );

    expect(
      shouldIgnoreTransientAddressChangeDuringExplicitSearch(
        explicitSearchInProgress: false,
        now: now,
        guardUntil: now.add(const Duration(milliseconds: 1500)),
      ),
      isTrue,
    );

    expect(
      shouldIgnoreTransientAddressChangeDuringExplicitSearch(
        explicitSearchInProgress: false,
        now: now,
        guardUntil: now.subtract(const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
  });

  test('confirmed address survives one-shot stale search echo', () {
    expect(
      shouldRestoreConfirmedAddressAfterStaleSearchEcho(
        changedValue: 'улица Астана 1',
        pendingQueryEcho: 'улица Астана 1',
        confirmedAddress:
            'Аксуский высший многопрофильный колледж им. Жаяу Мусы, 1, улица Астана, городская администрация Аксу',
        hasConfirmedLocation: true,
      ),
      isTrue,
    );

    expect(
      shouldRestoreConfirmedAddressAfterStaleSearchEcho(
        changedValue: 'Риддер, вокзал',
        pendingQueryEcho: 'улица Астана 1',
        confirmedAddress:
            'Аксуский высший многопрофильный колледж им. Жаяу Мусы, 1, улица Астана, городская администрация Аксу',
        hasConfirmedLocation: true,
      ),
      isFalse,
    );

    expect(
      shouldRestoreConfirmedAddressAfterStaleSearchEcho(
        changedValue: 'улица Астана 1',
        pendingQueryEcho: 'улица Астана 1',
        confirmedAddress:
            'Аксуский высший многопрофильный колледж им. Жаяу Мусы, 1, улица Астана, городская администрация Аксу',
        hasConfirmedLocation: false,
      ),
      isFalse,
    );
  });

  test('top ridesharing trip stays top while promotion is active', () {
    final now = DateTime(2026, 6, 24, 12);

    expect(
      isTopRideSharingTrip(
        {
          'topUntil': now.add(const Duration(hours: 2)).toIso8601String(),
        },
        now: now,
      ),
      isTrue,
    );

    expect(
      isTopRideSharingTrip(
        {
          'topUntil':
              now.subtract(const Duration(minutes: 1)).toIso8601String(),
        },
        now: now,
      ),
      isFalse,
    );
  });

  testWidgets(
    'mobile mode selector keeps city cards inside a 390px viewport',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OrderScreen(
              routeStage: 'mode',
              enableLiveMap: false,
              autoLocateOnStart: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('ЗАКАЗ'), findsOneWidget);
      expect(find.text('Город'), findsOneWidget);
      expect(find.text('Аукцион'), findsOneWidget);
      expect(find.text('Межгород'), findsOneWidget);
      expect(find.text('Доставка'), findsOneWidget);

      final cityRect = tester.getRect(find.text('ЗАКАЗ'));
      final fixedRect = tester.getRect(find.text('Город'));
      final auctionRect = tester.getRect(find.text('Аукцион'));
      final deliveryRect = tester.getRect(find.text('Доставка'));

      expect(cityRect.left, greaterThanOrEqualTo(0));
      expect(fixedRect.right, lessThanOrEqualTo(390));
      expect(auctionRect.right, lessThanOrEqualTo(390));
      expect(deliveryRect.right, lessThanOrEqualTo(390));
    },
  );

  testWidgets(
    'mobile city order flow shows maket mode first',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OrderScreen(
              routeStage: 'mode',
              enableLiveMap: false,
              autoLocateOnStart: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      final fixedMode = find.text('Город');
      final auctionMode = find.text('Аукцион');

      expect(fixedMode, findsOneWidget);
      expect(auctionMode, findsOneWidget);
      expect(find.text('Межгород'), findsOneWidget);
      expect(find.text('Доставка'), findsOneWidget);
      expect(find.text('Откуда'), findsNothing);
      expect(find.text('Куда'), findsNothing);
    },
  );
}
