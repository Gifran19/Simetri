import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'device_service.dart';
import '../widgets/security_pin_dialog.dart';

/// Layanan keamanan aplikasi SIMETRI:
/// - Otentikasi Biometrik (Fingerprint / Face ID via local_auth)
/// - Verifikasi PIN Keamanan Terenkripsi (via flutter_secure_storage)
/// - Token Keamanan Pairing IoT ESP32 (Hardware Key)
/// - Pencatatan Jejak Audit Keamanan (Security Audit Trail)
class SecurityService {
  static const _storage = FlutterSecureStorage();

  static final _localAuth = LocalAuthentication();

  static const String _keyPin = 'simetri_security_pin';
  static const String _keyDeviceToken = 'simetri_secure_device_token';
  static const String _keyAuditLogs = 'simetri_security_audit_logs';

  static const String defaultPin = '1234';

  // ----------------------------------------------------
  // VERIFIKASI & OTENTIKASI UTAMA (Biometrik / PIN Fallback)
  // ----------------------------------------------------

  /// Meminta otorisasi pengguna sebelum melakukan aksi kritis:
  /// 1. Mencoba otentikasi Biometrik HANYA jika diaktifkan oleh pengguna DAN didukung perangkat.
  /// 2. Jika biometrik dinonaktifkan di pengaturan atau gagal, langsung gunakan dialog PIN Keamanan.
  static Future<bool> requestAuthorization({
    required BuildContext context,
    required String actionTitle,
    required String actionDescription,
  }) async {
    // 1. Cek apakah biometrik diaktifkan oleh pengguna dan didukung perangkat
    final isBioEnabled = await DeviceService.isBiometricEnabled();
    final canBio = isBioEnabled && await hasBiometricSupport();

    if (canBio) {
      try {
        final didAuth = await _localAuth.authenticate(
          localizedReason: '$actionTitle: $actionDescription',
          biometricOnly: true,
        );

        if (didAuth) {
          await logSecurityEvent(actionTitle, '$actionDescription (Diverifikasi via Biometrik)');
          return true;
        }
      } catch (_) {
        // Fallback ke PIN dialog jika biometrik error / dibatalkan
      }
    }

    // 2. Fallback: Dialog PIN Keamanan
    if (!context.mounted) return false;

    final pinVerified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SecurityPinDialog(
        actionTitle: actionTitle,
        actionDescription: actionDescription,
        canUseBiometric: canBio,
        onBiometricTap: () async {
          try {
            final auth = await _localAuth.authenticate(
              localizedReason: '$actionTitle: $actionDescription',
              biometricOnly: true,
            );
            if (auth && ctx.mounted) {
              Navigator.pop(ctx, true);
            }
          } catch (_) {}
        },
      ),
    );

    if (pinVerified == true) {
      await logSecurityEvent(actionTitle, '$actionDescription (Diverifikasi via PIN)');
      return true;
    }

    return false;
  }

  // ----------------------------------------------------
  // BIOMETRIC HELPERS
  // ----------------------------------------------------

  static Future<bool> hasBiometricSupport() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!canCheck && !isDeviceSupported) return false;

      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------------------------------
  // PIN MANAGEMENT (Terenkripsi)
  // ----------------------------------------------------

  static Future<bool> verifyPin(String enteredPin) async {
    final storedPin = await _storage.read(key: _keyPin) ?? defaultPin;
    return enteredPin == storedPin;
  }

  static Future<void> changePin(String newPin) async {
    await _storage.write(key: _keyPin, value: newPin);
    await logSecurityEvent('Ganti PIN', 'PIN keamanan SIMETRI berhasil diperbarui');
  }

  // ----------------------------------------------------
  // IOT DEVICE SECURITY TOKEN (Hardware Pairing Key)
  // ----------------------------------------------------

  /// Menghasilkan atau mengambil token kriptografis perangkat IoT
  static Future<String> getOrGenerateDeviceToken() async {
    var token = await _storage.read(key: _keyDeviceToken);
    if (token == null || token.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      token = 'SMTR-SEC-$now-${(now % 9999).toString().padLeft(4, '0')}';
      await _storage.write(key: _keyDeviceToken, value: token);
    }
    return token;
  }

  // ----------------------------------------------------
  // AUDIT TRAIL LOGGING
  // ----------------------------------------------------

  static Future<void> logSecurityEvent(String action, String details) async {
    try {
      final raw = await _storage.read(key: _keyAuditLogs);
      List<dynamic> logs = [];
      if (raw != null) {
        logs = jsonDecode(raw) as List<dynamic>;
      }

      final now = DateTime.now();
      final dateFormatted =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      logs.insert(0, {
        'time': dateFormatted,
        'action': action,
        'details': details,
      });

      // Simpan maksimal 20 log terakhir
      if (logs.length > 20) {
        logs = logs.sublist(0, 20);
      }

      await _storage.write(key: _keyAuditLogs, value: jsonEncode(logs));
    } catch (_) {}
  }

  static Future<List<Map<String, String>>> getAuditLogs() async {
    try {
      final raw = await _storage.read(key: _keyAuditLogs);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }
}
