// File: lib/services/access_approval_service.dart

import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'device_service.dart';
import 'sensor_stream_service.dart';

/// Status izin akses perangkat oleh admin lokal
enum AccessStatus {
  /// Pengguna belum memiliki entri izin pada database
  notGranted,

  /// Izin sedang dalam antrean atau review
  pending,

  /// Izin telah disetujui dan aktif oleh admin
  active,

  /// Izin telah dicabut oleh admin
  revoked,

  /// Terjadi kesalahan saat memeriksa izin (misal offline/permission denied)
  error,
}

/// Hasil evaluasi izin akses perangkat
class AccessApprovalResult {
  final AccessStatus status;
  final String deviceId;
  final String role;
  final String message;
  final int? grantedAt;

  const AccessApprovalResult({
    required this.status,
    required this.deviceId,
    this.role = 'member',
    required this.message,
    this.grantedAt,
  });

  bool get isGranted => status == AccessStatus.active;
}

/// Service untuk memverifikasi persetujuan izin akses perangkat secara lokal
/// pada Firebase Spark tanpa ketergantungan pada Cloud Functions claimDevice.
class AccessApprovalService {
  static final AccessApprovalService instance = AccessApprovalService._internal();
  factory AccessApprovalService() => instance;
  AccessApprovalService._internal();

  /// Mengambil UID sesi anonim saat ini.
  Future<String?> getCurrentAnonymousUid() async {
    final user = await AuthService.instance.ensureAnonymousSession();
    return user?.uid;
  }

  /// Memeriksa izin akses perangkat pada path: permissions/$uid/$deviceId.
  /// Aplikasi HANYA menyatakan terhubung jika status bernilai 'active'.
  Future<AccessApprovalResult> verifyDeviceAccess(String targetDeviceId) async {
    final cleanDeviceId = targetDeviceId.trim();
    if (cleanDeviceId.isEmpty) {
      return const AccessApprovalResult(
        status: AccessStatus.error,
        deviceId: '',
        message: 'Device ID tidak boleh kosong.',
      );
    }

    final uid = await getCurrentAnonymousUid();
    if (uid == null || uid.isEmpty) {
      return AccessApprovalResult(
        status: AccessStatus.error,
        deviceId: cleanDeviceId,
        message: 'Gagal membuat sesi anonim. Periksa koneksi internet Anda.',
      );
    }

    try {
      final dbRef = FirebaseDatabase.instance.ref('permissions/$uid/$cleanDeviceId');
      final snapshot = await dbRef.get().timeout(const Duration(seconds: 4));

      if (!snapshot.exists || snapshot.value == null) {
        return AccessApprovalResult(
          status: AccessStatus.notGranted,
          deviceId: cleanDeviceId,
          message: 'Izin akses belum diberikan oleh administrator. '
              'Tunjukkan UID anonim Anda kepada admin untuk disetujui.',
        );
      }

      final data = snapshot.value as Map<dynamic, dynamic>;
      final statusStr = (data['status'] ?? '').toString().toLowerCase();
      final roleStr = (data['role'] ?? 'member').toString();
      final grantedAtVal = data['grantedAt'] is int ? data['grantedAt'] as int : null;

      if (statusStr == 'active') {
        // Izin aktif: perbarui state lokal dan arahkan stream aktif
        await DeviceService.savePairedDeviceId(cleanDeviceId);
        SensorStreamService.instance.setActiveDeviceId(cleanDeviceId);
        await DeviceService.saveConnectionState(true);

        return AccessApprovalResult(
          status: AccessStatus.active,
          deviceId: cleanDeviceId,
          role: roleStr,
          grantedAt: grantedAtVal,
          message: 'Izin akses aktif. Perangkat berhasil dihubungkan.',
        );
      } else if (statusStr == 'revoked') {
        // Izin dicabut: putuskan state lokal
        await DeviceService.saveConnectionState(false);

        return AccessApprovalResult(
          status: AccessStatus.revoked,
          deviceId: cleanDeviceId,
          role: roleStr,
          message: 'Izin akses perangkat telah dicabut oleh administrator.',
        );
      } else {
        await DeviceService.saveConnectionState(false);

        return AccessApprovalResult(
          status: AccessStatus.pending,
          deviceId: cleanDeviceId,
          role: roleStr,
          message: 'Status izin saat ini: $statusStr. Menunggu persetujuan admin.',
        );
      }
    } catch (e) {
      debugPrint('AccessApprovalService check error: $e');
      return AccessApprovalResult(
        status: AccessStatus.error,
        deviceId: cleanDeviceId,
        message: 'Gagal memeriksa status izin: $e',
      );
    }
  }

  /// Mendengarkan perubahan izin akses secara real-time.
  /// Berguna agar antarmuka otomatis berubah saat admin menjalankan perintah grant di konsol.
  Stream<AccessApprovalResult> streamDeviceAccess(String targetDeviceId) async* {
    final cleanDeviceId = targetDeviceId.trim();
    if (cleanDeviceId.isEmpty) return;

    final uid = await getCurrentAnonymousUid();
    if (uid == null || uid.isEmpty) return;

    final dbRef = FirebaseDatabase.instance.ref('permissions/$uid/$cleanDeviceId');
    yield* dbRef.onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        return AccessApprovalResult(
          status: AccessStatus.notGranted,
          deviceId: cleanDeviceId,
          message: 'Izin akses belum diberikan.',
        );
      }

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final statusStr = (data['status'] ?? '').toString().toLowerCase();
      final roleStr = (data['role'] ?? 'member').toString();

      if (statusStr == 'active') {
        return AccessApprovalResult(
          status: AccessStatus.active,
          deviceId: cleanDeviceId,
          role: roleStr,
          message: 'Izin akses terverifikasi aktif.',
        );
      } else if (statusStr == 'revoked') {
        return AccessApprovalResult(
          status: AccessStatus.revoked,
          deviceId: cleanDeviceId,
          role: roleStr,
          message: 'Izin akses telah dicabut.',
        );
      } else {
        return AccessApprovalResult(
          status: AccessStatus.pending,
          deviceId: cleanDeviceId,
          role: roleStr,
          message: 'Status izin: $statusStr.',
        );
      }
    });
  }
}
