import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Registro del dispositivo en FCM y asociación del token al perfil del staff.
/// Requiere `google-services.json` (Android) y `GoogleService-Info.plist` (iOS),
/// generados con `flutterfire configure`.
class PushService {
  PushService._();
  static final instance = PushService._();

  StreamSubscription<String>? _tokenSub;
  final _taps = StreamController<Map<String, dynamic>>.broadcast();

  /// Emite el `data` de las notificaciones tocadas (p. ej. {'route': '/agenda'}).
  Stream<Map<String, dynamic>> get taps => _taps.stream;

  Future<void> init() async {
    if (!Env.enablePush || kIsWeb) return;
    try {
      await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, badge: true, sound: true);
      await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

      FirebaseMessaging.onMessageOpenedApp.listen((m) => _taps.add(m.data));
      final initial = await fm.getInitialMessage();
      if (initial != null) _taps.add(initial.data);
    } catch (e) {
      debugPrint('Push deshabilitado: $e');
    }
  }

  /// Llamar después del login.
  Future<void> registerToken(SupabaseClient db) async {
    if (!Env.enablePush || kIsWeb || Firebase.apps.isEmpty) return;
    final fm = FirebaseMessaging.instance;
    final token = await fm.getToken();
    if (token != null) await db.rpc<void>('register_fcm_token', params: {'p_token': token});
    await _tokenSub?.cancel();
    _tokenSub = fm.onTokenRefresh.listen((t) => db.rpc<void>('register_fcm_token', params: {'p_token': t}));
  }
}
