import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/push_notifications_service.dart';
import '../../../core/utils/app_mode_manager.dart';
import '../../../core/utils/startup_trace.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final _api = ApiClient();
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    startupTraceMark('bootstrap.start');
    try {
      final token = await _api.getAccessToken();
      startupTraceMark(
        'bootstrap.token',
        data: <String, Object?>{'hasToken': token != null && token.isNotEmpty},
      );
      if (token == null || token.isEmpty) {
        startupTraceMark('bootstrap.route',
            data: <String, Object?>{'route': '/login'});
        _go('/login');
        return;
      }

      final res = await _api.get('/me');
      startupTraceMark('bootstrap.me.ok');
      await PushNotificationsService.instance.syncTokenIfAuthorized();
      startupTraceMark('bootstrap.push.synced');
      final user =
          res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      final role = (user?['role'] ?? '').toString();
      startupTraceMark('bootstrap.role', data: <String, Object?>{'role': role});
      final route = await AppModeManager.resolveHomeRoute(_api, role: role);
      startupTraceMark('bootstrap.route',
          data: <String, Object?>{'route': route});
      _go(route);
    } catch (error) {
      startupTraceMark(
        'bootstrap.error',
        data: <String, Object?>{'error': error.toString()},
      );
      await _api.clearTokens();
      startupTraceMark('bootstrap.route',
          data: <String, Object?>{'route': '/login'});
      _go('/login');
    }
  }

  void _go(String route) {
    if (!mounted || _didNavigate) return;
    _didNavigate = true;
    startupTraceMark('go.schedule', data: <String, Object?>{'route': route});

    void navigate() {
      if (!mounted) return;
      startupTraceMark('go.navigate', data: <String, Object?>{'route': route});
      context.go(route);
    }

    scheduleMicrotask(navigate);
    WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
    Future<void>.delayed(const Duration(milliseconds: 150), navigate);
    Future<void>.delayed(const Duration(milliseconds: 500), navigate);
    Future<void>.delayed(const Duration(seconds: 1), navigate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/branding/splash.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 30, 28),
              child: Column(
                children: [
                  const Spacer(),
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
