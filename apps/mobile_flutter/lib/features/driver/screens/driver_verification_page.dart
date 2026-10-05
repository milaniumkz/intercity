import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/vehicle_catalog_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/app_mode_manager.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/utils/route_query.dart';
import '../../../core/widgets/ic_premium.dart';
import '../widgets/driver_bottom_nav.dart';
import 'driver_doc_web_file_picker_stub.dart'
    if (dart.library.html) 'driver_doc_web_file_picker_html.dart';

class DriverVerificationPage extends StatefulWidget {
  const DriverVerificationPage({super.key, this.routeStage});

  final String? routeStage;

  @override
  State<DriverVerificationPage> createState() => _DriverVerificationPageState();
}

class _DriverVerificationPageState extends State<DriverVerificationPage> {
  final _docTypeCtrl = TextEditingController(text: 'selfie');
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();
  final _carBrandCtrl = TextEditingController();
  final _carModelCtrl = TextEditingController();
  final _carColorCtrl = TextEditingController();
  final _carNumberCtrl = TextEditingController();
  final _carClassCtrl = TextEditingController();
  String _message = '';
  String _accountPhone = '';
  bool _loading = false;
  String? _docUploadingType;
  final Set<String> _uploadedDocTypes = {};
  String? _boardStageOverride;
  static const _docTypes = [
    ('selfie', Icons.person_pin_rounded, 'Селфи'),
    ('passport', Icons.badge_rounded, 'Удостоверение личности / паспорт РК'),
    ('driverLicense', Icons.drive_eta_rounded, 'Водительское удостоверение РК'),
    (
      'techPassportFront',
      Icons.directions_car_rounded,
      'Техпаспорт автомобиля'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadAccountProfile();
    _loadDriverDocs();
  }

  @override
  void dispose() {
    _docTypeCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _birthDateCtrl.dispose();
    _carBrandCtrl.dispose();
    _carModelCtrl.dispose();
    _carColorCtrl.dispose();
    _carNumberCtrl.dispose();
    _carClassCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccountProfile() async {
    try {
      final res = await ApiClient().get('/me');
      final data = res.data;
      if (!mounted || data is! Map) return;
      final name = (data['name'] ?? '').toString().trim();
      final phone = (data['phone'] ?? '').toString().trim();
      setState(() {
        _accountPhone = phone;
        if (name.isNotEmpty && _firstNameCtrl.text.trim().isEmpty) {
          final parts = name.split(RegExp(r'\s+'));
          _firstNameCtrl.text = parts.first;
          if (parts.length > 1 && _lastNameCtrl.text.trim().isEmpty) {
            _lastNameCtrl.text = parts.skip(1).join(' ');
          }
        }
      });
    } catch (_) {
      // Регистрацию водителя не блокируем, если профиль временно недоступен.
    }
  }

  Future<void> _loadDriverDocs() async {
    try {
      final res = await ApiClient().get('/driver/profile');
      final data = res.data;
      if (!mounted || data is! Map) return;
      setState(() {
        if ((data['selfieUrl'] ?? '').toString().isNotEmpty) {
          _uploadedDocTypes.add('selfie');
        }
        if ((data['passportUrl'] ?? '').toString().isNotEmpty) {
          _uploadedDocTypes.add('passport');
        }
        if ((data['driverLicenseUrl'] ?? '').toString().isNotEmpty) {
          _uploadedDocTypes.add('driverLicense');
        }
        if ((data['techPassportFrontUrl'] ?? '').toString().isNotEmpty) {
          _uploadedDocTypes.add('techPassportFront');
        }
      });
    } catch (_) {
      // Если профиль еще создается, статусы появятся после первой загрузки.
    }
  }

  Future<void> _pickAndUploadDoc(String docType) async {
    if (kIsWeb) {
      await _pickAndUploadDocFile(docType);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Загрузить документ',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded,
                      color: AppTheme.primaryColor),
                  title: const Text('Сделать фото'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadDocFromSource(docType, ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded,
                      color: AppTheme.primaryColor),
                  title: const Text('Выбрать из галереи'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadDocFromSource(docType, ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadDocFromSource(
    String docType,
    ImageSource source,
  ) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (picked == null) return;

      await _uploadDocBytes(
        docType: docType,
        bytes: await picked.readAsBytes(),
        fileName: picked.name.isNotEmpty
            ? picked.name
            : '${docType}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    }
  }

  Future<void> _pickAndUploadDocFile(String docType) async {
    try {
      final file = await pickDriverDocFileWeb();
      if (file == null || file.bytes.isEmpty) return;

      await _uploadDocBytes(
        docType: docType,
        bytes: file.bytes,
        fileName: file.name.trim().isNotEmpty
            ? file.name
            : '${docType}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    }
  }

  Future<void> _uploadDocBytes({
    required String docType,
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      setState(() {
        _loading = true;
        _docUploadingType = docType;
        _message = '';
      });

      await ApiClient().post(
        '/driver/docs/upload',
        data: FormData.fromMap({
          'docType': docType,
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
        }),
        options: Options(contentType: 'multipart/form-data'),
      );
      if (!mounted) return;
      setState(() {
        _uploadedDocTypes.add(docType);
        _docTypeCtrl.text = docType;
        _message = 'Документ загружен. Можно загрузить следующий.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _docUploadingType = null;
        });
      }
    }
  }

  Future<void> _complete() async {
    const requiredDocs = {'passport', 'driverLicense', 'techPassportFront'};
    final missingDocs = requiredDocs.difference(_uploadedDocTypes);
    if (missingDocs.isNotEmpty) {
      setState(() => _message = 'Загрузите все документы перед отправкой.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiClient().post('/driver/docs/complete', data: {});
      await AppModeManager.rememberPassengerMode();
      if (!mounted) return;
      const message =
          'Документы отправлены на проверку. Пока проверка идет, вы остаетесь в режиме пассажира.';
      setState(() => _message = message);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text(message),
          duration: Duration(seconds: 3),
        ));
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      context.go('/order');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveDriverProfileAndContinue() async {
    final carModel =
        '${_carBrandCtrl.text.trim()} ${_carModelCtrl.text.trim()}'.trim();
    final carNumber = _carNumberCtrl.text.trim();
    if (carModel.isEmpty || carNumber.isEmpty) {
      setState(() => _message = 'Укажите автомобиль и гос. номер.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiClient().post('/driver/profile', data: {
        'carModel': carModel,
        'carNumber': carNumber,
        'acceptCityFixed': true,
        'acceptCityAuction': true,
        'acceptIntercity': true,
        'acceptDelivery': false,
        'acceptCargo': false,
      });
      if (!mounted) return;
      setState(() => _message = 'Анкета водителя сохранена');
      _goVerificationBoard('driver_docs');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _continueDriverPersonal() {
    if (_firstNameCtrl.text.trim().isEmpty ||
        _lastNameCtrl.text.trim().isEmpty) {
      setState(() => _message = 'Укажите имя и фамилию.');
      return;
    }
    setState(() => _message = '');
    _goVerificationBoard('driver_car');
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return ICCard(padding: padding ?? const EdgeInsets.all(16), child: child);
  }

  void _goVerificationBoard(String marker) {
    final dark = routeHas(context, 'dark=1') ? '?dark=1' : '';
    setState(() => _boardStageOverride = marker);
    final stage = marker.replaceFirst('driver_', '');
    context.go('/driver/verification/$stage$dark');
  }

  bool _routeStage(String marker) {
    final stage = marker.replaceFirst('driver_', '');
    return widget.routeStage == stage || routeHas(context, '$marker=1');
  }

  bool get _useIntercityBoardUi => true;

  @override
  Widget build(BuildContext context) {
    final boardStage = _boardStageOverride;
    if (boardStage == 'driver_personal' ||
        _routeStage('driver_personal') ||
        (_useIntercityBoardUi &&
            boardStage == null &&
            !_routeStage('driver_car') &&
            !_routeStage('driver_docs'))) {
      return _boardDriverPersonalScreen();
    }
    if (boardStage == 'driver_car' || _routeStage('driver_car')) {
      return _boardDriverCarScreen();
    }
    if (boardStage == 'driver_docs' || _routeStage('driver_docs')) {
      return _boardDriverDocsScreen();
    }
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: const DriverBottomNav(currentIndex: 0),
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => goBackOr(context, fallback: '/driver/home'),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const Expanded(
                  child: ICBrandHeader(
                    compact: true,
                    subtitle: 'Документы и проверка',
                  ),
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
            _verificationHero(theme),
            const SizedBox(height: 12),
            _documentsChecklist(theme),
            const SizedBox(height: 12),
            _card(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(22)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.cloud_upload_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Загрузите документы',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Проверка обычно занимает до 24 часов',
                                style: TextStyle(color: Colors.white70),
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
                        _docTypeSelector(theme),
                        const SizedBox(height: 14),
                        ICGradientButton(
                          label: 'Выбрать и загрузить документ',
                          icon: Icons.cloud_upload_rounded,
                          loading: _loading,
                          onPressed: _loading
                              ? null
                              : () => _pickAndUploadDoc(_docTypeCtrl.text),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: _premiumOutlineButton(
                            label: 'Подтвердить документы',
                            icon: Icons.verified_user_outlined,
                            onPressed: _loading ? null : _complete,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_message.isNotEmpty)
              _card(
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _message,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
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

  Widget _boardDriverPersonalScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _boardTopBack(),
              const SizedBox(height: 20),
              Text(
                'Личные данные',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Заполните информацию о себе',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              _boardProgress(0),
              const SizedBox(height: 22),
              _boardInput('Имя', controller: _firstNameCtrl),
              _boardInput('Фамилия', controller: _lastNameCtrl),
              _boardInput('Дата рождения',
                  controller: _birthDateCtrl,
                  icon: Icons.calendar_month_rounded,
                  trailing: Icons.calendar_month_rounded),
              _accountPhoneInfo(theme),
              if (_message.isNotEmpty) ...[
                const SizedBox(height: 8),
                ICPremiumInfoBanner(text: _message),
              ],
              const Spacer(),
              ICGradientButton(
                label: 'Далее',
                icon: Icons.arrow_forward_rounded,
                onPressed: _continueDriverPersonal,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardDriverCarScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _boardTopBack(),
                const SizedBox(height: 20),
                Text(
                  'Информация\nоб автомобиле',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Укажите данные вашего автомобиля',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                _boardProgress(1),
                const SizedBox(height: 22),
                _boardInput('Марка',
                    controller: _carBrandCtrl,
                    onTap: _pickVehicleMake,
                    trailing: Icons.chevron_right_rounded),
                _boardInput('Модель',
                    controller: _carModelCtrl,
                    onTap: _pickVehicleModel,
                    trailing: Icons.chevron_right_rounded),
                _boardColorInput(theme),
                _boardInput('Гос. номер',
                    controller: _carNumberCtrl,
                    trailing: Icons.chevron_right_rounded),
                _boardInput('Класс',
                    controller: _carClassCtrl,
                    onTap: () => _pickBoardValue(
                          title: 'Класс',
                          controller: _carClassCtrl,
                          values: const [
                            'Эконом',
                            'Оптимал',
                            'Комфорт',
                            'Комфорт+',
                            'Бизнес',
                          ],
                        ),
                    trailing: Icons.chevron_right_rounded),
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ICPremiumInfoBanner(text: _message),
                ],
                const SizedBox(height: 18),
                ICGradientButton(
                  label: 'Далее',
                  icon: Icons.arrow_forward_rounded,
                  loading: _loading,
                  onPressed: _loading ? null : _saveDriverProfileAndContinue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardDriverDocsScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          children: [
            _boardTopBack(),
            const SizedBox(height: 20),
            Text(
              'Документы и проверка',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Загрузите документы для проверки',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            _boardProgress(2),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Проверка аккаунта',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Повышайте уровень и получайте больше заказов',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            value: 0.75,
                            color: Colors.white,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    '75%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Необходимые документы',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            _boardDocRow(
              'Удостоверение личности / паспорт РК',
              _uploadedDocTypes.contains('passport')
                  ? 'Загружен'
                  : 'Нужно загрузить',
              _uploadedDocTypes.contains('passport'),
              Icons.badge_rounded,
              docType: 'passport',
            ),
            _boardDocRow(
              'Водительское удостоверение РК',
              _uploadedDocTypes.contains('driverLicense')
                  ? 'Загружен'
                  : 'Нужно загрузить',
              _uploadedDocTypes.contains('driverLicense'),
              Icons.credit_card_rounded,
              docType: 'driverLicense',
            ),
            _boardDocRow(
              'Техпаспорт автомобиля',
              _uploadedDocTypes.contains('techPassportFront')
                  ? 'Загружен'
                  : 'Нужно загрузить',
              _uploadedDocTypes.contains('techPassportFront'),
              Icons.car_repair_rounded,
              docType: 'techPassportFront',
            ),
            const SizedBox(height: 12),
            if (_loading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(minHeight: 4),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined,
                      color: AppTheme.primaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Проверка занимает до 24 часов',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _pickAndUploadDoc(_docTypeCtrl.text),
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text('Загрузить выбранный'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ICGradientButton(
                    label: 'Отправить',
                    onPressed: _loading ? null : _complete,
                  ),
                ),
              ],
            ),
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 10),
              ICPremiumInfoBanner(text: _message),
            ],
          ],
        ),
      ),
    );
  }

  Widget _boardDocRow(
    String title,
    String status,
    bool done,
    IconData icon, {
    required String docType,
  }) {
    final theme = Theme.of(context);
    final selected = _docTypeCtrl.text == docType;
    final uploading = _docUploadingType == docType;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _loading
          ? null
          : () {
              setState(() => _docTypeCtrl.text = docType);
              _pickAndUploadDoc(docType);
            },
      child: Container(
        height: 56,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : AppTheme.primaryColor.withValues(alpha: 0.10),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (uploading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                done ? 'Загружен' : status,
                style: TextStyle(
                  color:
                      done ? Colors.green : theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            const SizedBox(width: 6),
            Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: done ? Colors.green : AppTheme.primaryColor,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardTopBack() {
    return InkWell(
      onTap: () => goBackOr(context, fallback: '/driver/home'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child:
            const Icon(Icons.arrow_back_rounded, color: AppTheme.primaryColor),
      ),
    );
  }

  Widget _boardProgress(int activeIndex) {
    return Row(
      children: List.generate(3, (index) {
        final active = index <= activeIndex;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
            decoration: BoxDecoration(
              color: active
                  ? AppTheme.primaryColor
                  : AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        );
      }),
    );
  }

  Widget _boardInput(
    String label, {
    required TextEditingController controller,
    IconData? icon,
    IconData? trailing,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: 1,
        readOnly: onTap != null,
        onTap: onTap,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
          prefixIcon:
              Icon(icon ?? Icons.edit_rounded, color: AppTheme.primaryColor),
          suffixIcon: trailing == null
              ? null
              : Icon(trailing, color: AppTheme.primaryColor),
          filled: true,
          fillColor:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(
              color: AppTheme.primaryColor,
              width: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountPhoneInfo(ThemeData theme) {
    final phone =
        _accountPhone.isEmpty ? 'Телефон текущего аккаунта' : _accountPhone;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_rounded, color: AppTheme.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Телефон аккаунта',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  phone,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.lock_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _boardColorInput(ThemeData theme) {
    final color = switch (_carColorCtrl.text) {
      'Белый' => Colors.white,
      'Серый' => Colors.grey,
      'Синий' => Colors.blueGrey,
      _ => Colors.black,
    };
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pickBoardValue(
          title: 'Цвет',
          controller: _carColorCtrl,
          values: const ['Черный металлик', 'Белый', 'Серый', 'Синий'],
        ),
        child: Container(
          height: 58,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Цвет',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _carColorCtrl.text,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.18),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickBoardValue({
    required String title,
    required TextEditingController controller,
    required List<String> values,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              for (final value in values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: controller.text == value
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: AppTheme.primaryColor,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, value),
                ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      controller.text = selected;
      _message = '$title: $selected';
    });
  }

  Future<void> _pickVehicleMake() async {
    setState(() => _message = 'Загружаем марки...');
    try {
      final makes = await VehicleCatalogService.instance.getMakes();
      if (!mounted) return;
      final values = makes
          .map((item) => (item['name'] ?? '').toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (values.isEmpty) {
        setState(() => _message = 'Марки авто временно недоступны.');
        return;
      }
      final previousMake = _carBrandCtrl.text;
      await _pickBoardValue(
        title: 'Марка',
        controller: _carBrandCtrl,
        values: values,
      );
      if (!mounted) return;
      if (_carBrandCtrl.text != previousMake) {
        setState(() => _carModelCtrl.clear());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    }
  }

  Future<void> _pickVehicleModel() async {
    final make = _carBrandCtrl.text.trim();
    if (make.isEmpty) {
      setState(() => _message = 'Сначала выберите марку авто.');
      return;
    }
    setState(() => _message = 'Загружаем модели...');
    try {
      final values =
          await VehicleCatalogService.instance.getModelsForMake(make);
      if (!mounted) return;
      if (values.isEmpty) {
        setState(() => _message = 'Для этой марки модели пока не найдены.');
        return;
      }
      await _pickBoardValue(
        title: 'Модель',
        controller: _carModelCtrl,
        values: values,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    }
  }

  Widget _verificationHero(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF271044), Color(0xFF100B1F)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x552C174C),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Шаг 3 из 3',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Документы и проверка',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Загрузите документы для проверки аккаунта',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '75%',
                  style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(
              3,
              (index) => Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: index < 3 ? 0.92 : 0.22,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: 0.75,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Загрузите документы, чтобы получать городские и межгородские заказы.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.48,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF8F6FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.24),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _docTypeSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Выберите документ',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        ..._docTypes.map((doc) {
          final selected = _docTypeCtrl.text == doc.$1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _docTypeRow(
              value: doc.$1,
              icon: doc.$2,
              title: doc.$3,
              selected: selected,
              onTap: () => setState(() => _docTypeCtrl.text = doc.$1),
            ),
          );
        }),
      ],
    );
  }

  Widget _docTypeRow({
    required String value,
    required IconData icon,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: isDark ? 0.22 : 0.10)
              : isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF8F6FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : AppTheme.primaryColor.withValues(alpha: 0.12),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: selected
                    ? const LinearGradient(
                        colors: [
                          AppTheme.secondaryColor,
                          AppTheme.primaryColor,
                        ],
                      )
                    : null,
                color: selected ? null : theme.colorScheme.surface,
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected
                  ? AppTheme.primaryColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentsChecklist(ThemeData theme) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Необходимые документы',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _docRow(
            theme,
            Icons.person_pin_rounded,
            'Селфи',
            'Загружено',
            true,
          ),
          _docRow(
            theme,
            Icons.badge_rounded,
            'Удостоверение личности / паспорт РК',
            'Загружен',
            true,
          ),
          _docRow(
            theme,
            Icons.drive_eta_rounded,
            'Водительское удостоверение РК',
            'Загружен',
            true,
          ),
          _docRow(
            theme,
            Icons.directions_car_rounded,
            'Техпаспорт автомобиля',
            'На проверке',
            true,
          ),
          const SizedBox(height: 4),
          Text(
            'Проверка занимает до 24 часов. После подтверждения водитель получает больше доступных заказов.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _docRow(
    ThemeData theme,
    IconData icon,
    String title,
    String status,
    bool done,
  ) {
    final color = done ? Colors.greenAccent : AppTheme.primaryColor;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFFDFBFF),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: done
                  ? const LinearGradient(
                      colors: [Color(0xFF30E18A), Color(0xFF18C5A9)],
                    )
                  : LinearGradient(
                      colors: [
                        AppTheme.secondaryColor.withValues(alpha: 0.18),
                        AppTheme.primaryColor.withValues(alpha: 0.10),
                      ],
                    ),
            ),
            child:
                Icon(icon, color: done ? Colors.white : AppTheme.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status == 'На проверке'
                      ? 'Документ проверяется модератором'
                      : done
                          ? 'Документ принят системой'
                          : 'Требуется загрузка',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  done ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                  color: color,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
