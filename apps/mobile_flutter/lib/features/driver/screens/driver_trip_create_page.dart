import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intercity_shared/intercity_shared.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/location_display.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/utils/request_flow_utils.dart';
import '../../../core/utils/route_query.dart';
import '../../../core/widgets/ic_premium.dart';
import '../widgets/driver_bottom_nav.dart';

class DriverTripCreatePage extends StatefulWidget {
  const DriverTripCreatePage({super.key, this.routeStage});

  final String? routeStage;

  @override
  State<DriverTripCreatePage> createState() => _DriverTripCreatePageState();
}

class _DriverTripCreatePageState extends State<DriverTripCreatePage> {
  final _fromCityCtrl = TextEditingController(text: 'Алматы');
  final _toCityCtrl = TextEditingController(text: 'Астана');
  final _pricePerSeatCtrl = TextEditingController(text: '2000');
  final _routeSeatsCtrl = TextEditingController(text: '4');
  int _seatsTotal = 3;
  String _offerCurrencySymbol = '₸';
  bool _promoteToTop = false;
  DateTime _departureTime = _defaultDepartureTime();
  List<dynamic> _openRequests = [];
  List<dynamic> _myTrips = [];
  List<Map<String, dynamic>> _cities = const [];
  List<Map<String, dynamic>> _intercityRoutes = const [];
  String _message = '';
  bool _loading = false;
  bool _routeSaving = false;
  int _selectedTab = 0;
  bool _initialized = false;
  String? _boardStageOverride;
  Map<String, dynamic>? _boardSelectedOrder;
  String _boardTypeFilter = 'Межгород';
  String _boardPaymentFilter = 'Все';
  String? _routeFromCityId;
  String? _routeToCityId;
  String _routeFromCityName = '';
  String _routeToCityName = '';

  static DateTime _defaultDepartureTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 9);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    if (_routeStage('insufficient') ||
        _routeStage('commission') ||
        _routeStage('detail')) {
      _openRequests = _boardDriverRequests;
      _loading = false;
      return;
    }
    _loadDriverIntercityData();
  }

  static final List<Map<String, dynamic>> _boardDriverRequests = [];

  bool _routeStage(String marker) {
    return widget.routeStage == marker || routeHas(context, '$marker=1');
  }

  bool get _useIntercityBoardUi => true;

  @override
  void dispose() {
    _fromCityCtrl.dispose();
    _toCityCtrl.dispose();
    _pricePerSeatCtrl.dispose();
    _routeSeatsCtrl.dispose();
    super.dispose();
  }

  Future<void> _createTrip({BuildContext? closeContext}) async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient().post('/ridesharing/trips', data: {
        'fromCity': _fromCityCtrl.text,
        'toCity': _toCityCtrl.text,
        'fromLat': 43.2220,
        'fromLng': 76.8512,
        'toLat': 51.1694,
        'toLng': 71.4491,
        'seatsTotal': _seatsTotal,
        'pricePerSeat': double.tryParse(_pricePerSeatCtrl.text) ?? 2000,
        'departureTime': _departureTime.toUtc().toIso8601String(),
        'promoteToTop': _promoteToTop,
      });
      if (!mounted) return;
      final createdTrip = Map<String, dynamic>.from(res.data as Map);
      setState(() {
        _myTrips = [createdTrip, ..._myTrips];
        _message = _promoteToTop
            ? 'Заявка создана и поднята в топ'
            : 'Заявка создана: ${res.data['id']} (мест: $_seatsTotal)';
      });
      await _loadDriverIntercityData(silent: true);
      if (closeContext != null && closeContext.mounted) {
        Navigator.of(closeContext).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _promoteTrip(String id) async {
    setState(() => _loading = true);
    try {
      await ApiClient().post('/ridesharing/trips/$id/promote');
      if (!mounted) return;
      setState(() => _message = 'Заявка поднята в топ');
      await _loadDriverIntercityData(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateTripSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            return DraggableScrollableSheet(
              initialChildSize: 0.88,
              minChildSize: 0.55,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(30)),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 32,
                        offset: const Offset(0, -12),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      10,
                      16,
                      16 + MediaQuery.of(context).viewInsets.bottom,
                    ),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.secondaryColor,
                                  AppTheme.primaryColor,
                                ],
                              ),
                            ),
                            child: const Icon(
                              Icons.route_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Создать заявку',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'Ваша межгородняя поездка для пассажиров',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _fromCityCtrl,
                        decoration: _inputDecoration(
                          label: 'Город отправления',
                          icon: Icons.trip_origin_rounded,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _toCityCtrl,
                        decoration: _inputDecoration(
                          label: 'Город назначения',
                          icon: Icons.location_on_outlined,
                        ),
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: _loading
                            ? null
                            : () async {
                                await _pickDepartureTime();
                                setSheetState(() {});
                              },
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppTheme.secondaryColor
                                  .withValues(alpha: 0.14),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                color: AppTheme.primaryColor,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Выезд: ${_formatDate(_departureTime.toIso8601String())}',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_seat_rounded,
                              color: AppTheme.primaryColor,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Свободные места',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _seatsTotal > 1
                                  ? () {
                                      setState(() => _seatsTotal--);
                                      setSheetState(() {});
                                    }
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              '$_seatsTotal',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            IconButton(
                              onPressed: _seatsTotal < 8
                                  ? () {
                                      setState(() => _seatsTotal++);
                                      setSheetState(() {});
                                    }
                                  : null,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pricePerSeatCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _inputDecoration(
                          label: 'Цена за 1 место',
                          icon: Icons.payments_outlined,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _promoteToTop,
                        activeThumbColor: Colors.amberAccent,
                        title: Text(
                          'Поднять заявку в топ',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(
                          'Пассажиры увидят её выше других примерно на 24 часа.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        onChanged: _loading
                            ? null
                            : (value) {
                                setState(() => _promoteToTop = value);
                                setSheetState(() {});
                              },
                      ),
                      const SizedBox(height: 12),
                      ICGradientButton(
                        label: 'Создать заявку',
                        loading: _loading,
                        icon: Icons.check_rounded,
                        onPressed: _loading
                            ? null
                            : () => _createTrip(closeContext: sheetContext),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _loadDriverIntercityData({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }

    List<dynamic> openRequests = _openRequests;
    List<dynamic> myTrips = _myTrips;
    List<Map<String, dynamic>> cities = _cities;
    List<Map<String, dynamic>> intercityRoutes = _intercityRoutes;
    String? warning;

    try {
      final res = await ApiClient().get('/intercity/requests/open');
      openRequests = List<dynamic>.from(res.data as List);
    } catch (e) {
      debugPrint('Failed to load open intercity requests: $e');
      warning ??=
          'Не удалось загрузить заявки пассажиров: ${errorMessageRu(e)}';
    }

    try {
      final res = await ApiClient().get('/ridesharing/trips/my');
      myTrips = List<dynamic>.from(res.data as List);
    } catch (e) {
      debugPrint('Failed to load driver trips: $e');
      warning ??= 'Не удалось загрузить мои поездки: ${errorMessageRu(e)}';
    }

    try {
      final citiesRes = await ApiClient().get('/geo/cities');
      cities = citiesRes.data is List
          ? (citiesRes.data as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      cities.sort(
        (a, b) => (a['name'] ?? '').toString().compareTo(
              (b['name'] ?? '').toString(),
            ),
      );
    } catch (e) {
      debugPrint('Failed to load cities: $e');
      warning ??= 'Не удалось загрузить города: ${errorMessageRu(e)}';
    }

    try {
      final routesRes = await ApiClient().get('/driver/intercity/routes');
      intercityRoutes = routesRes.data is List
          ? (routesRes.data as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
    } catch (e) {
      debugPrint('Failed to load driver intercity routes: $e');
      warning ??=
          'Не удалось загрузить межгород-маршруты: ${errorMessageRu(e)}';
    }

    if (!mounted) return;
    setState(() {
      _openRequests = openRequests;
      _myTrips = myTrips;
      _cities = cities;
      _intercityRoutes = intercityRoutes;
      if (warning != null) {
        _message = warning;
      }
      _loading = false;
    });
  }

  String _cityNameById(String? id) {
    if (id == null || id.isEmpty) return '';
    final match = _cities.cast<Map<String, dynamic>?>().firstWhere(
          (city) => city?['id']?.toString() == id,
          orElse: () => null,
        );
    return (match?['name'] ?? '').toString().trim();
  }

  Future<void> _addIntercityRoute() async {
    if (_routeSaving) return;
    final fromCity = _routeFromCityName.trim().isNotEmpty
        ? _routeFromCityName.trim()
        : _cityNameById(_routeFromCityId);
    final toCity = _routeToCityName.trim().isNotEmpty
        ? _routeToCityName.trim()
        : _cityNameById(_routeToCityId);
    if (fromCity.isEmpty || toCity.isEmpty) {
      setState(() => _message = 'Выберите город отправления и назначения');
      return;
    }
    if (fromCity == toCity) {
      setState(
          () => _message = 'Города отправления и назначения должны отличаться');
      return;
    }
    final seatsAvailable = int.tryParse(_routeSeatsCtrl.text.trim()) ?? 0;
    if (seatsAvailable < 1 || seatsAvailable > 8) {
      setState(() => _message = 'Укажите количество мест от 1 до 8');
      return;
    }
    setState(() => _routeSaving = true);
    try {
      await ApiClient().post('/driver/intercity/routes', data: {
        'fromCity': fromCity,
        'toCity': toCity,
        'seatsAvailable': seatsAvailable,
      });
      if (!mounted) return;
      setState(() {
        _message = 'Заявка на межгород-маршрут подана';
        _routeFromCityId = null;
        _routeToCityId = null;
        _routeFromCityName = '';
        _routeToCityName = '';
      });
      await _loadDriverIntercityData(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _routeSaving = false);
    }
  }

  Future<void> _deleteIntercityRoute(String id) async {
    if (id.isEmpty) return;
    try {
      await ApiClient().post('/driver/intercity/routes/$id/delete');
      if (!mounted) return;
      setState(() => _message = 'Межгород-маршрут отключен');
      await _loadDriverIntercityData(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    }
  }

  String _cityTitleFromGeo(Map<String, dynamic> item) {
    final raw = (item['displayName'] ?? item['name'] ?? '').toString().trim();
    if (raw.isEmpty) return 'Город';
    final parts = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? raw : parts.first;
  }

  String _citySubtitleFromGeo(Map<String, dynamic> item) {
    final raw = (item['displayName'] ?? '').toString().trim();
    final title = _cityTitleFromGeo(item);
    final parts = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != title)
        .toList();
    return parts.take(2).join(', ');
  }

  List<Map<String, dynamic>> _localCitySearchResults(String query) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final matches = _cities.where((city) {
      final name = (city['name'] ?? '').toString().toLowerCase();
      final region = (city['region'] ?? '').toString().toLowerCase();
      return name.contains(q) || region.contains(q);
    }).map((city) {
      final name = (city['name'] ?? '').toString().trim();
      final region = (city['region'] ?? '').toString().trim();
      return <String, dynamic>{
        ...city,
        'displayName':
            [name, region].where((part) => part.trim().isNotEmpty).join(', '),
      };
    }).toList();
    matches.sort((a, b) {
      final aName = (a['name'] ?? '').toString();
      final bName = (b['name'] ?? '').toString();
      final aStarts = aName.toLowerCase().startsWith(q);
      final bStarts = bName.toLowerCase().startsWith(q);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return aName.compareTo(bName);
    });
    return matches.take(12).toList();
  }

  Future<void> _openRouteCitySearch({required bool isFrom}) async {
    final controller = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = false;
    String localMessage = 'Введите минимум 2 буквы';
    int requestId = 0;
    Timer? debounce;

    Future<void> runSearch(
      String value,
      void Function(void Function()) setSheetState,
    ) async {
      final query = value.trim();
      requestId++;
      final currentRequestId = requestId;
      if (query.length < 2) {
        setSheetState(() {
          results = [];
          loading = false;
          localMessage = 'Введите минимум 2 буквы';
        });
        return;
      }
      setSheetState(() {
        loading = true;
        localMessage = '';
      });
      try {
        final res = await ApiClient().post(
          '/geo/search',
          data: {'q': query, 'type': 'city'},
        );
        if (currentRequestId != requestId) return;
        final parsed = res.data is List
            ? (res.data as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : <Map<String, dynamic>>[];
        final localFallback = _localCitySearchResults(query);
        final merged = <Map<String, dynamic>>[];
        final seen = <String>{};
        for (final item in [...parsed, ...localFallback]) {
          final key = [
            (item['name'] ?? '').toString().trim().toLowerCase(),
            (item['region'] ?? '').toString().trim().toLowerCase(),
            (item['displayName'] ?? '').toString().trim().toLowerCase(),
          ].where((part) => part.isNotEmpty).join('|');
          if (key.isEmpty || seen.contains(key)) continue;
          seen.add(key);
          merged.add(item);
        }
        setSheetState(() {
          results = merged.take(12).toList();
          loading = false;
          localMessage = results.isEmpty ? 'Город не найден' : '';
        });
      } catch (e) {
        if (currentRequestId != requestId) return;
        final localFallback = _localCitySearchResults(query);
        setSheetState(() {
          results = localFallback;
          loading = false;
          localMessage = localFallback.isEmpty
              ? 'Не удалось выполнить поиск. Попробуйте ещё раз.'
              : '';
        });
      }
    }

    void scheduleSearch(
      String value,
      void Function(void Function()) setSheetState,
    ) {
      debounce?.cancel();
      debounce = Timer(
        const Duration(milliseconds: 280),
        () => runSearch(value, setSheetState),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            return DraggableScrollableSheet(
              initialChildSize: 0.78,
              minChildSize: 0.45,
              maxChildSize: 0.92,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(30)),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.14),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      10,
                      16,
                      18 + MediaQuery.of(context).viewInsets.bottom,
                    ),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.40),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isFrom ? 'Город отправления' : 'Город назначения',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: _inputDecoration(
                          label: 'Поиск города',
                          icon: Icons.search_rounded,
                        ),
                        onChanged: (value) =>
                            scheduleSearch(value, setSheetState),
                        onSubmitted: (value) => runSearch(value, setSheetState),
                      ),
                      if (loading) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(minHeight: 3),
                      ],
                      if (localMessage.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ICPremiumInfoBanner(text: localMessage),
                      ],
                      const SizedBox(height: 12),
                      ...results.map((item) {
                        final title = _cityTitleFromGeo(item);
                        final subtitle = _citySubtitleFromGeo(item);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color:
                                  AppTheme.primaryColor.withValues(alpha: 0.12),
                            ),
                          ),
                          child: ListTile(
                            leading: const Icon(
                              Icons.location_city_rounded,
                              color: AppTheme.primaryColor,
                            ),
                            title: Text(
                              title,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: subtitle.isEmpty
                                ? null
                                : Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              setState(() {
                                if (isFrom) {
                                  _routeFromCityName = title;
                                  _routeFromCityId = null;
                                } else {
                                  _routeToCityName = title;
                                  _routeToCityId = null;
                                }
                              });
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
    debounce?.cancel();
    controller.dispose();
  }

  Future<void> _showOfferDialog(Map<String, dynamic> request) async {
    _offerCurrencySymbol = rideCurrencySymbol(request);
    final requestType =
        (request['requestType'] ?? requestTypeIntercity).toString();
    final paymentMethod =
        paymentMethodLabel(request['paymentMethod']?.toString());
    final fromText = formatLocationDisplay(request, isFrom: true);
    final toText = formatLocationDisplay(request, isFrom: false);
    final expectsSeats = requestType == requestTypeIntercity;
    final priceCtrl = TextEditingController();
    final commentCtrl = TextEditingController();
    final seatsCtrl = TextEditingController(
      text: ((request['seats'] as num?)?.toInt() ?? 1).toString(),
    );

    Future<void> submitOffer(StateSetter setDialogState) async {
      final price = double.tryParse(priceCtrl.text.trim());
      final seats = expectsSeats ? int.tryParse(seatsCtrl.text.trim()) : 1;
      if (price == null || price <= 0 || seats == null || seats <= 0) {
        setDialogState(() {});
        return;
      }

      try {
        await ApiClient().post(
          '/intercity/requests/${request['id']}/offers',
          data: {
            'price': price,
            'seats': seats,
            'comment': commentCtrl.text.trim().isEmpty
                ? null
                : commentCtrl.text.trim(),
          },
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        setState(() => _message = 'Отклик на заявку отправлен');
        await _loadDriverIntercityData(silent: true);
      } catch (e) {
        if (!mounted) return;
        setState(() => _message = errorMessageRu(e));
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final title = requestType == requestTypeIntercity
                ? 'Откликнуться на межгород'
                : requestType == requestTypeCityAuction
                    ? 'Предложить цену'
                    : 'Откликнуться на доставку';
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(18),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 430),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    AppTheme.secondaryColor,
                                    AppTheme.primaryColor,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryColor
                                        .withValues(alpha: 0.28),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.gavel_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Оплата пассажира: $paymentMethod',
                                    style:
                                        const TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _routeLine(from: fromText, to: toText),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: 0.14),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppTheme.primaryColor
                                          .withValues(alpha: 0.12),
                                    ),
                                    child: const Icon(
                                      Icons.payments_rounded,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Ваша цена за поездку',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Пассажир увидит предложение и сможет выбрать вас',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Быстрый выбор цены',
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _quickOfferPrices(priceCtrl, setDialogState),
                            const SizedBox(height: 12),
                            TextField(
                              controller: priceCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: _inputDecoration(
                                label: 'Предложение по цене',
                                icon: Icons.payments_outlined,
                              ),
                            ),
                            if (expectsSeats) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: seatsCtrl,
                                keyboardType: TextInputType.number,
                                decoration: _inputDecoration(
                                  label: 'Количество мест',
                                  icon: Icons.event_seat_rounded,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextField(
                              controller: commentCtrl,
                              decoration: _inputDecoration(
                                label: 'Комментарий к предложению',
                                icon: Icons.chat_bubble_outline_rounded,
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _premiumOutlineButton(
                                    label: 'Отмена',
                                    icon: Icons.close_rounded,
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ICGradientButton(
                                    label: 'Отправить',
                                    onPressed: () =>
                                        submitOffer(setDialogState),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return ICCard(padding: padding ?? const EdgeInsets.all(16), child: child);
  }

  Widget _quickOfferPrices(
    TextEditingController priceCtrl,
    StateSetter setDialogState,
  ) {
    const options = [3000, 5000, 8000, 12000];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((price) {
        final selected = priceCtrl.text.trim() == price.toString();
        return InkWell(
          onTap: () {
            priceCtrl.text = price.toString();
            setDialogState(() {});
          },
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: selected
                  ? const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    )
                  : null,
              color: selected
                  ? null
                  : AppTheme.primaryColor.withValues(alpha: 0.08),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.18),
              ),
            ),
            child: Text(
              '$price $_offerCurrencySymbol',
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.primaryColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _premiumOutlineButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(18);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.48,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.white.withValues(alpha: 0.74),
              borderRadius: radius,
              border: Border.all(
                color: AppTheme.primaryColor
                    .withValues(alpha: isDark ? 0.35 : 0.22),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                )
              : null,
          color: selected
              ? null
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.55),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : AppTheme.primaryColor.withValues(alpha: 0.16),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppTheme.primaryColor),
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : const Color(0xFFF8F6FF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.14),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.14),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.4),
      ),
    );
  }

  Widget _routeLine({
    required String from,
    required String to,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.16 : 0.10),
        ),
        boxShadow: [
          if (!isDark)
            const BoxShadow(
              color: Color(0x142C174C),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _routeDot(AppTheme.primaryColor),
              Container(
                width: 2,
                height: 34,
                color: AppTheme.primaryColor.withValues(alpha: 0.35),
              ),
              _routeDot(AppTheme.secondaryColor),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  from,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  to,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeDot(Color color) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _pill({
    required IconData icon,
    required String text,
    Color? color,
  }) {
    final c = color ?? AppTheme.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String text) {
    final isRequests = text.contains('заявок');
    return ICPremiumEmptyState(
      icon: isRequests ? Icons.travel_explore_rounded : Icons.alt_route_rounded,
      title: isRequests ? 'Заявок пока нет' : 'Поездок пока нет',
      subtitle: text,
    );
  }

  Widget _intercityRouteApplicationCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return _card(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  ),
                ),
                child: const Icon(Icons.route_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Мои межгород-маршруты',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Подайте маршрут, чтобы получать заказы только по нему.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_cities.isEmpty)
            const ICPremiumInfoBanner(
              text: 'Поиск работает по городам Казахстана и России.',
            )
          else
            const ICPremiumInfoBanner(
              text: 'Начните вводить название, выберите город из поиска.',
            ),
          const SizedBox(height: 10),
          _routeCitySearchField(
            label: 'Откуда',
            value: _routeFromCityName,
            icon: Icons.trip_origin_rounded,
            onTap:
                _routeSaving ? null : () => _openRouteCitySearch(isFrom: true),
          ),
          const SizedBox(height: 10),
          _routeCitySearchField(
            label: 'Куда',
            value: _routeToCityName,
            icon: Icons.location_on_rounded,
            onTap:
                _routeSaving ? null : () => _openRouteCitySearch(isFrom: false),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _routeSeatsCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration(
              label: 'Свободных мест',
              icon: Icons.event_seat_rounded,
            ),
          ),
          const SizedBox(height: 12),
          ICGradientButton(
            label: _routeSaving ? 'Отправляем...' : 'Подать заявку',
            icon: Icons.check_rounded,
            loading: _routeSaving,
            onPressed: _routeSaving ? null : _addIntercityRoute,
          ),
          if (_intercityRoutes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Активные маршруты',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            ..._intercityRoutes.map((route) {
              final id = (route['id'] ?? '').toString();
              final from = (route['fromCity'] ?? '').toString();
              final to = (route['toCity'] ?? '').toString();
              final seats = (route['seatsAvailable'] as num?)?.toInt() ??
                  (route['seatsTotal'] as num?)?.toInt() ??
                  0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.035)
                      : const Color(0xFFF8F6FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.alt_route_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$from → $to',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Свободно мест: $seats',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed:
                          _routeSaving ? null : () => _deleteIntercityRoute(id),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Отключить маршрут',
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _routeCitySearchField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final hasValue = value.trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFF8F6FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppTheme.secondaryColor.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasValue ? value : 'Найти город',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasValue
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.search_rounded, color: AppTheme.primaryColor),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic raw) {
    final value = raw?.toString();
    if (value == null || value.isEmpty) return '-';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    final twoDigitsMonth = parsed.month.toString().padLeft(2, '0');
    final twoDigitsDay = parsed.day.toString().padLeft(2, '0');
    final twoDigitsHour = parsed.hour.toString().padLeft(2, '0');
    final twoDigitsMinute = parsed.minute.toString().padLeft(2, '0');
    return '$twoDigitsDay.$twoDigitsMonth ${parsed.year} $twoDigitsHour:$twoDigitsMinute';
  }

  Future<void> _pickDepartureTime() async {
    final today = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _departureTime.isBefore(today) ? today : _departureTime,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
      helpText: 'Дата и время выезда',
      cancelText: 'Отмена',
      confirmText: 'Далее',
      locale: const Locale('ru'),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departureTime),
      helpText: 'Время выезда',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
    );
    if (!mounted) return;
    setState(() {
      _departureTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime?.hour ?? _departureTime.hour,
        pickedTime?.minute ?? _departureTime.minute,
      );
    });
  }

  Widget _buildOpenRequestCard(Map<String, dynamic> request) {
    final offersCount = (request['offers'] as List?)?.length ?? 0;
    final seats = (request['seats'] as num?)?.toInt() ?? 0;
    final requestType =
        (request['requestType'] ?? requestTypeIntercity).toString();
    final fromText = formatLocationDisplay(request, isFrom: true);
    final toText = formatLocationDisplay(request, isFrom: false);
    final paymentMethod =
        paymentMethodLabel(request['paymentMethod']?.toString());
    final price = request['price'] ?? request['proposedPrice'];
    final priceText = price is num
        ? '${price.toStringAsFixed(0)} ${rideCurrencySymbol(request)}'
        : 'Цена от водителя';
    final distance = request['distanceKm'] ?? request['distance'];
    final distanceText =
        distance is num ? '${distance.toStringAsFixed(0)} км' : 'Маршрут';
    final manualWarning = hasUnconfirmedLocation(request, isFrom: true) ||
        hasUnconfirmedLocation(request, isFrom: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card(
        padding: const EdgeInsets.all(0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                gradient: LinearGradient(
                  colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _pill(
                          icon: requestType == requestTypeIntercity
                              ? Icons.route_rounded
                              : Icons.local_shipping_outlined,
                          text: requestTypeLabel(requestType),
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                      _pill(
                        icon: Icons.forum_outlined,
                        text: '$offersCount откл.',
                        color: offersCount > 0
                            ? Colors.greenAccent
                            : Colors.white70,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              AppTheme.secondaryColor,
                              AppTheme.primaryColor,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppTheme.primaryColor.withValues(alpha: 0.26),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          requestType == requestTypeIntercity
                              ? Icons.alt_route_rounded
                              : Icons.local_shipping_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$fromText → $toText',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                height: 1.12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatDate(request['date']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Text(
                              priceText,
                              style: const TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              requestType == requestTypeIntercity
                                  ? '$seats мест'
                                  : 'доставка',
                              style: const TextStyle(
                                color: Color(0xFF7C7590),
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Оплата: $paymentMethod',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        distanceText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _routeLine(
                    from: fromText,
                    to: toText,
                    subtitle: 'Дата: ${_formatDate(request['date'])}',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _metricBlock(
                          label: 'Оплата',
                          value: paymentMethod,
                          icon: Icons.credit_card_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _metricBlock(
                          label: 'Стоимость',
                          value: priceText,
                          icon: Icons.payments_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _metricBlock(
                          label: 'Расстояние',
                          value: distanceText,
                          icon: Icons.straighten_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _metricBlock(
                          label: requestType == requestTypeIntercity
                              ? 'Пассажиры'
                              : 'Тип',
                          value: requestType == requestTypeIntercity
                              ? '$seats мест'
                              : 'Доставка',
                          icon: requestType == requestTypeIntercity
                              ? Icons.airline_seat_recline_normal_rounded
                              : Icons.inventory_2_outlined,
                        ),
                      ),
                    ],
                  ),
                  if ((request['itemDescription'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Груз: ${request['itemDescription']}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (manualWarning)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Адрес введён вручную, геоточка не подтверждена.',
                        style: TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ICGradientButton(
                      label: requestType == requestTypeIntercity
                          ? 'Предложить цену'
                          : 'Откликнуться',
                      onPressed:
                          _loading ? null : () => _showOfferDialog(request),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricBlock({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primaryColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyTripCard(Map<String, dynamic> trip) {
    final seatsAvailable = (trip['seatsAvailable'] as num?)?.toInt() ?? 0;
    final seatsTotal = (trip['seatsTotal'] as num?)?.toInt() ?? 0;
    final bookingsCount = (trip['bookings'] as List?)?.length ?? 0;
    final pricePerSeat = trip['pricePerSeat'];
    final isTop = _isTopTrip(trip);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                gradient: LinearGradient(
                  colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _pill(
                        icon: Icons.route_rounded,
                        text: 'Моя заявка',
                      ),
                      const Spacer(),
                      if (isTop)
                        _pill(
                          icon: Icons.workspace_premium,
                          text: 'В ТОПЕ',
                          color: Colors.amber,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              AppTheme.secondaryColor,
                              AppTheme.primaryColor,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppTheme.primaryColor.withValues(alpha: 0.26),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.directions_car_filled_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${trip['fromCity'] ?? '-'} → ${trip['toCity'] ?? '-'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                                height: 1.08,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isTop
                                  ? 'В топе до: ${_formatDate(trip['topUntil'])}'
                                  : 'Выезд: ${_formatDate(trip['departureTime'])}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$pricePerSeat ${rideCurrencySymbol(trip)}',
                              style: const TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$seatsAvailable/$seatsTotal мест',
                              style: const TextStyle(
                                color: Color(0xFF7C7590),
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _routeLine(
                    from: (trip['fromCity'] ?? '-').toString(),
                    to: (trip['toCity'] ?? '-').toString(),
                    subtitle: isTop
                        ? 'В топе до: ${_formatDate(trip['topUntil'])}'
                        : 'Выезд: ${_formatDate(trip['departureTime'])}',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _metricBlock(
                          label: 'Цена за место',
                          value: '$pricePerSeat ${rideCurrencySymbol(trip)}',
                          icon: Icons.payments_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _metricBlock(
                          label: 'Места',
                          value: '$seatsAvailable/$seatsTotal',
                          icon: Icons.event_seat_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _metricBlock(
                          label: 'Брони',
                          value: '$bookingsCount',
                          icon: Icons.people_outline,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _metricBlock(
                          label: 'Статус',
                          value: '${trip['status']}',
                          icon: Icons.flag_outlined,
                        ),
                      ),
                    ],
                  ),
                  if (bookingsCount > 0) ...[
                    const SizedBox(height: 12),
                    _bookingBoardList(trip['bookings'] as List),
                  ],
                  if (!isTop &&
                      (trip['status'] ?? '').toString() == 'OPEN') ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: _premiumOutlineButton(
                        label: 'Поднять в топ',
                        icon: Icons.workspace_premium_rounded,
                        onPressed: _loading
                            ? null
                            : () => _promoteTrip(trip['id'].toString()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookingBoardList(List bookings) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Отклики пассажиров',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...bookings.take(4).map((item) {
            final booking = item is Map
                ? Map<String, dynamic>.from(item)
                : <String, dynamic>{};
            final seats = (booking['seats'] as num?)?.toInt() ?? 1;
            final status = (booking['status'] ?? 'PENDING').toString();
            final id = (booking['id'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_rounded,
                    color: AppTheme.primaryColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Пассажир • $seats мест(а)',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    status,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (id.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '#${id.substring(0, id.length < 4 ? id.length : 4)}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          if (bookings.length > 4)
            Text(
              'Ещё откликов: ${bookings.length - 4}',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boardStage = _boardStageOverride;
    final boardOrder = _boardSelectedOrder ??
        (_openRequests.isNotEmpty
            ? Map<String, dynamic>.from(_openRequests.first as Map)
            : (_boardDriverRequests.isNotEmpty
                ? _boardDriverRequests.first
                : <String, dynamic>{}));
    if (boardStage == 'insufficient') {
      return _boardInsufficientFundsScreen(boardOrder);
    }
    if (boardStage == 'commission') {
      return _boardCommissionConfirmScreen(boardOrder);
    }
    if (boardStage == 'detail') {
      return _boardRequestDetailScreen(boardOrder);
    }

    if (_routeStage('insufficient') ||
        _routeStage('commission') ||
        _routeStage('detail') ||
        _useIntercityBoardUi) {
      if (_routeStage('insufficient')) {
        return _boardInsufficientFundsScreen(boardOrder);
      }
      if (_routeStage('commission')) {
        return _boardCommissionConfirmScreen(boardOrder);
      }
      if (_routeStage('detail')) {
        return _boardRequestDetailScreen(boardOrder);
      }
      return _boardAvailableOrdersScreen();
    }

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: const DriverBottomNav(currentIndex: 1),
      body: RefreshIndicator(
        onRefresh: _loadDriverIntercityData,
        child: ICPremiumBackground(
          padding: EdgeInsets.zero,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        goBackOr(context, fallback: '/driver/home'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Expanded(
                    child: ICBrandHeader(
                      compact: true,
                      subtitle: 'Межгород',
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _loadDriverIntercityData,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(
                    color: AppTheme.primaryColor,
                    backgroundColor:
                        theme.colorScheme.outline.withValues(alpha: 0.16),
                  ),
                ),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Межгород',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Создавайте свои заявки и отвечайте пассажирам вручную.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ICGradientButton(
                            label: 'Создать заявку',
                            icon: Icons.add_rounded,
                            onPressed: _loading ? null : _showCreateTripSheet,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _premiumOutlineButton(
                            label: 'Заявки пассажиров',
                            icon: Icons.people_alt_rounded,
                            onPressed:
                                _loading ? null : _loadDriverIntercityData,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_message.isNotEmpty)
                Text(
                  _message,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _tabButton(
                      label: 'Заявки пассажиров',
                      selected: _selectedTab == 0,
                      onTap: () => setState(() => _selectedTab = 0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tabButton(
                      label: 'Мои заявки',
                      selected: _selectedTab == 1,
                      onTap: () => setState(() => _selectedTab = 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_selectedTab == 0) ...[
                _sectionTitle('Заявки пассажиров'),
                if (_openRequests.isEmpty)
                  _emptyState(
                      'Сейчас нет открытых заявок пассажиров и доставки.'),
                ..._openRequests.map(
                  (item) => _buildOpenRequestCard(item as Map<String, dynamic>),
                ),
              ] else ...[
                _sectionTitle('Мои заявки'),
                if (_myTrips.isEmpty)
                  _emptyState('Вы ещё не создавали межгородние заявки.'),
                ..._myTrips.map(
                  (item) => _buildMyTripCard(item as Map<String, dynamic>),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _goTripBoard(String marker) {
    setState(() => _boardStageOverride = marker);
  }

  bool _isDemoRequest(Map<String, dynamic> order) {
    final id = (order['id'] ?? '').toString();
    return id.isEmpty || id.startsWith('MGR-') || id.startsWith('CITY-');
  }

  Future<void> _submitBoardIntercityOffer(Map<String, dynamic> order) async {
    if (_isDemoRequest(order) || _routeStage('commission')) {
      setState(() => _boardStageOverride = 'detail');
      return;
    }
    final price = (order['price'] as num?)?.toDouble() ?? 0;
    if (price <= 0) {
      setState(() => _message = 'В заявке не указана стоимость.');
      return;
    }
    setState(() => _loading = true);
    try {
      final seats = (order['seats'] as num?)?.toInt() ?? 1;
      await ApiClient().post(
        '/intercity/requests/${order['id']}/offers',
        data: {
          'price': price,
          'seats': seats,
        },
      );
      if (!mounted) return;
      setState(() => _message = 'Отклик на заявку отправлен');
      context.go('/driver/home/chosen');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _boardInsufficientFundsScreen(Map<String, dynamic> order) {
    final theme = Theme.of(context);
    const required = 270;
    const available = 120;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: ListView(
            key: const ValueKey('driver_commission_confirm'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        goBackOr(context, fallback: '/driver/trip-create'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Недостаточно средств',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              Center(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF8B2DE), Color(0xFFFF477D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF477D).withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 82,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Text(
                'Недостаточно средств для принятия заявки',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.14,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Для принятия этой межгородской заявки необходимо $required ${rideCurrencySymbol(order)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 24),
              _boardDetailCard(
                child: Column(
                  children: [
                    _boardMoneyRow('Требуется для комиссии',
                        '$required ${rideCurrencySymbol(order)}'),
                    _boardMoneyRow(
                      'Доступно на балансе',
                      '$available ₸',
                      strong: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Пополните баланс, чтобы принимать межгородские заказы и зарабатывать больше.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          height: 1.28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              ICGradientButton(
                label: 'Пополнить баланс',
                onPressed: () => context.go(
                  '/driver/wallet',
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _goTripBoard('detail'),
                child: const Text('Назад к заявке'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardCommissionConfirmScreen(Map<String, dynamic> order) {
    final theme = Theme.of(context);
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final commission = ((order['commissionAmount'] as num?)?.toDouble() ??
        (rideCurrencyCode(order) == 'RUB' ? 0.0 : 270.0));
    final payout = price > commission ? price - commission : 0;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        goBackOr(context, fallback: '/driver/trip-create'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Подтверждение списания',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.04,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE8D8FF), Color(0xFF8D32F4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.20),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white,
                    size: 78,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'За принятие межгородской заявки будет списана комиссия сервиса',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$commission ${rideCurrencySymbol(order)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 22),
              _boardDetailCard(
                child: Column(
                  children: [
                    _boardMoneyRow(
                        'Сумма заказа', '$price ${rideCurrencySymbol(order)}'),
                    _boardMoneyRow('Комиссия сервиса',
                        '-$commission ${rideCurrencySymbol(order)}'),
                    _boardMoneyRow(
                      'К зачислению после поездки',
                      '$payout ${rideCurrencySymbol(order)}',
                      strong: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Списание комиссии происходит сразу после принятия заявки. Средства будут заблокированы на вашем балансе.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          height: 1.28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_message.isNotEmpty) ...[
                const SizedBox(height: 12),
                ICPremiumInfoBanner(text: _message),
              ],
              const SizedBox(height: 24),
              ICGradientButton(
                label: 'Подтвердить и принять',
                loading: _loading,
                onPressed:
                    _loading ? null : () => _submitBoardIntercityOffer(order),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _goTripBoard('detail'),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardAvailableOrdersScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: const DriverBottomNav(currentIndex: 1),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Доступные заказы',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(
                    () => _message = 'Фильтры заявок уже применены',
                  ),
                  icon: const Icon(
                    Icons.filter_alt_outlined,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _intercityRouteApplicationCard(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _boardFilterChip(
                    'Все',
                    _boardTypeFilter == 'Все',
                    onTap: () => setState(() => _boardTypeFilter = 'Все'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _boardFilterChip(
                    'По городу',
                    _boardTypeFilter == 'По городу',
                    onTap: () => setState(() => _boardTypeFilter = 'По городу'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _boardFilterChip(
                    'Межгород',
                    _boardTypeFilter == 'Межгород',
                    onTap: () => setState(() => _boardTypeFilter = 'Межгород'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Оплата',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _boardPayChip('Все'),
                _boardPayChip('Наличные'),
                _boardPayChip('Карта'),
                _boardPayChip('Безнал'),
              ],
            ),
            const SizedBox(height: 14),
            if (_boardFilteredRequests.isEmpty)
              const ICPremiumInfoBanner(
                text: 'Нет заявок по выбранным фильтрам.',
              )
            else
              ..._boardFilteredRequests.map(
                (item) => _boardAvailableOrderCard(
                  Map<String, dynamic>.from(item as Map),
                ),
              ),
            if (_loading) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(minHeight: 4),
              ),
            ],
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 10),
              ICPremiumInfoBanner(text: _message),
            ],
          ],
        ),
      ),
    );
  }

  Widget _boardRequestDetailScreen(Map<String, dynamic> order) {
    final theme = Theme.of(context);
    final from = (order['fromAddress'] ?? 'Точка подачи').toString();
    final to = (order['toAddress'] ?? 'Точка назначения').toString();
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final distance = order['distanceKm'] ?? order['distance'];
    final duration = order['durationMinutes'] ?? order['duration'];
    final distanceText = distance is num
        ? '${distance.toStringAsFixed(0)} км'
        : 'Расстояние уточняется';
    final durationText = duration is num
        ? '~ ${duration.toStringAsFixed(0)} мин'
        : 'Время уточняется';
    final orderId =
        (order['id'] ?? order['orderId'] ?? 'новая заявка').toString();
    final createdAt = (order['departureTime'] ??
            order['scheduledAt'] ??
            order['createdAt'] ??
            'Дата уточняется')
        .toString();
    final passenger = (order['passengerName'] ??
            order['clientName'] ??
            order['customerName'] ??
            order['userName'] ??
            'Пассажир')
        .toString();
    final passengerPhone = (order['passengerPhone'] ??
            order['clientPhone'] ??
            order['customerPhone'] ??
            order['phone'] ??
            'Телефон не указан')
        .toString();
    final passengerRating = (order['passengerRating'] ??
            order['clientRating'] ??
            order['customerRating'] ??
            '—')
        .toString();
    final commission = ((order['commissionAmount'] as num?)?.toDouble() ??
        (rideCurrencyCode(order) == 'RUB' ? 0.0 : 270.0));
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: ListView(
            key: const ValueKey('driver_request_detail'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        goBackOr(context, fallback: '/driver/trip-create'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Детали заявки',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _boardDetailCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Заказ #$orderId',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _boardMiniBadge('Межгород'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      createdAt,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _routeLine(
                      from: from,
                      to: to,
                      subtitle: '$distanceText • $durationText',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _boardDetailCard(
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.secondaryColor,
                            AppTheme.primaryColor
                          ],
                        ),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            passenger,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            passengerPhone,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Color(0xFFFFB545), size: 16),
                              const SizedBox(width: 4),
                              Text(passengerRating,
                                  style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _boardDetailCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Условия и оплата',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _boardMoneyRow('Фиксированная цена',
                        '$price ${rideCurrencySymbol(order)}'),
                    _boardMoneyRow('Комиссия сервиса',
                        '-$commission ${rideCurrencySymbol(order)}'),
                    _boardMoneyRow(
                      'К списанию с баланса',
                      '$commission ${rideCurrencySymbol(order)}',
                      strong: true,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Комиссия будет списана после принятия заявки',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _boardDetailCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Требования к поездке',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _boardRequirement(
                        Icons.smoke_free_rounded, 'Некурящий салон'),
                    const SizedBox(height: 8),
                    _boardRequirement(
                        Icons.work_outline_rounded, 'Багаж в багажнике'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ICGradientButton(
                label: 'Принять заявку',
                onPressed: () => _goTripBoard('commission'),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'У вас есть 00:45 чтобы принять заявку',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardDetailCard({required Widget child}) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF11101D)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: child,
    );
  }

  Widget _boardMiniBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _boardMoneyRow(String label, String value, {bool strong = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color:
                  strong ? AppTheme.primaryColor : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardRequirement(IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 18),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  List<dynamic> get _boardFilteredRequests {
    final source = _openRequests;
    return source.where((raw) {
      final order = Map<String, dynamic>.from(raw as Map);
      final type = (order['requestType'] ?? '').toString();
      final payment = (order['paymentMethod'] ?? '').toString();
      final typeOk = _boardTypeFilter == 'Все' ||
          (_boardTypeFilter == 'Межгород' && type == requestTypeIntercity) ||
          (_boardTypeFilter == 'По городу' && type != requestTypeIntercity);
      final paymentOk = _boardPaymentFilter == 'Все' ||
          (_boardPaymentFilter == 'Наличные' && payment == paymentMethodCash) ||
          (_boardPaymentFilter == 'Карта' &&
              payment == paymentMethodCardTransfer) ||
          (_boardPaymentFilter == 'Безнал' &&
              payment == paymentMethodCardTransfer);
      return typeOk && paymentOk;
    }).toList();
  }

  Widget _boardFilterChip(
    String label,
    bool selected, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                )
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.74),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: selected ? 0 : 0.14),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.primaryColor,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _boardPayChip(String label) {
    final selected = _boardPaymentFilter == label;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 7),
        child: _boardFilterChip(
          label,
          selected,
          onTap: () => setState(() => _boardPaymentFilter = label),
        ),
      ),
    );
  }

  Widget _boardAvailableOrderCard(Map<String, dynamic> order) {
    final theme = Theme.of(context);
    final from = (order['fromAddress'] ?? '').toString();
    final to = (order['toAddress'] ?? '').toString();
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final distance = (order['distanceKm'] as num?)?.toInt() ?? 0;
    final isIntercity = order['requestType'] == requestTypeIntercity;
    return InkWell(
      onTap: () {
        setState(() => _boardSelectedOrder = order);
        _goTripBoard('detail');
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF111426)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.18),
          ),
          boxShadow: [
            if (theme.brightness == Brightness.light)
              BoxShadow(
                color: const Color(0xFF4B2A84).withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.circle, color: AppTheme.primaryColor, size: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$from → $to',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Сегодня, 10:30        $distance км        ${isIntercity ? 'Комфорт+' : 'Бизнес'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 58,
              child: Text(
                '$price ${rideCurrencySymbol(order)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  bool _isTopTrip(Map<String, dynamic> trip) {
    final raw = (trip['topUntil'] ?? '').toString();
    if (raw.isEmpty) return false;
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return false;
    return parsed.isAfter(DateTime.now());
  }
}
