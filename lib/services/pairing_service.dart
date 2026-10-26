// File: lib/services/pairing_service.dart

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

/// Hasil dari proses klaim / pairing perangkat
class PairingResult {
  final bool success;
  final String deviceId;
  final String message;

  const PairingResult({
    required this.success,
    required this.deviceId,
    required this.message,
  });
}

/// Service untuk memverifikasi kode pairing ke Cloud Functions backend
class PairingService {
  static final PairingService instance = PairingService._internal();
  PairingService._internal();

  FirebaseFunctions get _functions => FirebaseFunctions.instance;

  /// Memverifikasi kode pairing ke Cloud Functions backend secara aman.
  /// Backend akan memeriksa hash kode, masa berlaku, status used,
  /// dan memberikan izin owner kepada UID anonim yang aktif.
  Future<PairingResult> claimDevice(String pairingCode) async {
    final cleanCode = pairingCode.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      throw const PairingException('Kode pairing tidak boleh kosong.');
    }

    // 1. Pastikan pengguna memiliki sesi autentikasi anonim yang valid
    final user = await AuthService.instance.ensureAnonymousSession();
    if (user == null) {
      throw const PairingException(
        'Gagal mendapatkan sesi autentikasi pengguna. Periksa koneksi internet.',
      );
    }

    try {
      final callable = _functions.httpsCallable('claimDevice');
      final response = await callable.call<Map<dynamic, dynamic>>({
        'pairingCode': cleanCode,
      });

      final data = response.data;
      final isSuccess = data['success'] == true;
      final deviceId = data['deviceId'] as String? ?? '';
      final message = data['message'] as String? ?? 'Perangkat berhasil dipasangkan.';

      if (!isSuccess || deviceId.isEmpty) {
        throw PairingException(message.isNotEmpty ? message : 'Gagal memasangkan perangkat.');
      }

      return PairingResult(
        success: true,
        deviceId: deviceId,
        message: message,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('PairingService FirebaseFunctionsException: ${e.code} - ${e.message}');
      throw PairingException(_translateFunctionsError(e));
    } catch (e) {
      debugPrint('PairingService unexpected error: $e');
      if (e is PairingException) rethrow;
      throw PairingException('Terjadi kendala saat menghubungi server: $e');
    }
  }

  /// Menerjemahkan kode error dari Cloud Functions ke pesan ramah pengguna
  String _translateFunctionsError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Sesi autentikasi tidak valid. Buka ulang aplikasi.';
      case 'invalid-argument':
        return e.message ?? 'Format kode pairing tidak valid.';
      case 'not-found':
        return 'Kode pairing tidak valid atau tidak ditemukan. Periksa kembali kode Anda.';
      case 'failed-precondition':
        return 'Kode pairing ini sudah pernah digunakan sebelumnya.';
      case 'deadline-exceeded':
        return 'Kode pairing telah kedaluwarsa. Mintalah kode baru kepada admin.';
      case 'resource-exhausted':
        return e.message ?? 'Terlalu banyak percobaan gagal. Silakan tunggu beberapa menit.';
      case 'unavailable':
        return 'Layanan server sedang tidak dapat dijangkau. Periksa koneksi internet Anda.';
      default:
        return e.message ?? 'Gagal memverifikasi kode pairing (${e.code}).';
    }
  }
}

class PairingException implements Exception {
  final String message;
  const PairingException(this.message);

  @override
  String toString() => message;
}
