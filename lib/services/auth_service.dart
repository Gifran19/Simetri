// File: lib/services/auth_service.dart

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'device_service.dart';
import 'sensor_stream_service.dart';

/// Layanan Autentikasi Pengguna SIMETRI berbasis Firebase Authentication.
///
/// PERBEDAAN FUNGSI (Penting):
/// 1. **Akun Pengguna (Firebase Auth / Email & Password)**:
///    - Berfungsi untuk autentikasi tingkat cloud.
///    - Menetapkan kepemilikan perangkat IoT (ownership) secara aman di backend.
///    - Memungkinkan sinkronisasi status perangkat antar jaringan internet berbeda
///      (misal: ESP32 di WiFi rumah, ponsel menggunakan data seluler di luar rumah).
///
/// 2. **PIN Keamanan & Biometrik Lokal (On-Device)**:
///    - Berfungsi sebagai otorisasi lapis kedua (local second-factor authorization)
///      di dalam ponsel.
///    - Mencegah aksi fisik kritis (saklar relay daya, perubahan tarif, reset pairing)
///      jika ponsel sedang dipinjam atau dibuka orang lain.
class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  /// Cek apakah Firebase sudah terinisialisasi
  bool get isFirebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseAuth? get _auth {
    if (!isFirebaseReady) return null;
    return FirebaseAuth.instance;
  }

  /// Stream status autentikasi aktif
  Stream<User?> get authStateChanges {
    final auth = _auth;
    if (auth == null) {
      return Stream.value(null);
    }
    return auth.authStateChanges();
  }

  /// Pengguna yang sedang login saat ini
  User? get currentUser => _auth?.currentUser;

  /// UID pengguna aktif saat ini
  String? get currentUid => currentUser?.uid;

  /// Apakah pengguna sudah memiliki sesi login aktif
  bool get isLoggedIn => currentUser != null;

  // ----------------------------------------------------
  // SESI ANONIM OTOMATIS (PERSISTEN)
  // ----------------------------------------------------
  /// Memastikan sesi pengguna aktif tanpa memaksa pendaftaran/login akun manual.
  /// - Jika sudah ada sesi aktif sebelumnya, sesi tersebut dipulihkan (UID TIDAK BERUBAH).
  /// - Jika belum ada sesi, melakukan signInAnonymously() secara otomatis.
  /// - Kegagalan koneksi/Firebase akan dilempar sebagai exception, tidak memberikan status sukses palsu.
  Future<User?> ensureAnonymousSession() async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthException(
        'Layanan Firebase belum terhubung. Periksa konfigurasi proyek Firebase.',
      );
    }

    // 1. Cek sesi lokal yang sudah tersimpan
    final existingUser = auth.currentUser;
    if (existingUser != null) {
      debugPrint('AuthService: Memulihkan sesi pengguna yang sudah ada (UID: ${existingUser.uid})');
      return existingUser;
    }

    // 2. Jika belum ada sesi, buat sesi anonim baru
    try {
      debugPrint('AuthService: Memulai signInAnonymously() baru...');
      final credential = await auth.signInAnonymously();
      final newUser = credential.user;
      if (newUser == null) {
        throw const AuthException('Gagal mendapatkan identitas anonim dari Firebase.');
      }
      debugPrint('AuthService: Sesi anonim berhasil dibuat (UID: ${newUser.uid})');
      return newUser;
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService.signInAnonymously error: ${e.code} - ${e.message}');
      throw AuthException(getReadableErrorMessage(e.code));
    } catch (e) {
      debugPrint('AuthService.signInAnonymously unknown error: $e');
      throw const AuthException('Gagal membuat sesi autentikasi otomatis. Periksa jaringan Anda.');
    }
  }

  // ----------------------------------------------------
  // MASUK (LOGIN)
  // ----------------------------------------------------
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthException(
        'Layanan Firebase belum terhubung. Periksa konfigurasi proyek Firebase.',
      );
    }

    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService.signIn error: ${e.code} - ${e.message}');
      throw AuthException(getReadableErrorMessage(e.code));
    } catch (e) {
      debugPrint('AuthService.signIn unknown error: $e');
      throw const AuthException('Terjadi kesalahan saat masuk. Periksa jaringan Anda.');
    }
  }

  // ----------------------------------------------------
  // DAFTAR (REGISTER)
  // ----------------------------------------------------
  Future<UserCredential> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthException(
        'Layanan Firebase belum terhubung. Periksa konfigurasi proyek Firebase.',
      );
    }

    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      if (displayName != null && displayName.trim().isNotEmpty) {
        await credential.user?.updateDisplayName(displayName.trim());
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService.register error: ${e.code} - ${e.message}');
      throw AuthException(getReadableErrorMessage(e.code));
    } catch (e) {
      debugPrint('AuthService.register unknown error: $e');
      throw const AuthException('Gagal mendaftarkan akun. Silakan coba lagi.');
    }
  }

  // ----------------------------------------------------
  // LUPA KATA SANDI (FORGOT PASSWORD)
  // ----------------------------------------------------
  Future<void> sendPasswordResetEmail({required String email}) async {
    final auth = _auth;
    if (auth == null) {
      throw const AuthException(
        'Layanan Firebase belum terhubung. Periksa konfigurasi proyek Firebase.',
      );
    }

    try {
      await auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      debugPrint('AuthService.resetPassword error: ${e.code} - ${e.message}');
      throw AuthException(getReadableErrorMessage(e.code));
    } catch (e) {
      debugPrint('AuthService.resetPassword unknown error: $e');
      throw const AuthException('Gagal mengirimkan email reset. Periksa format email.');
    }
  }

  // ----------------------------------------------------
  // KELUAR (LOGOUT)
  // ----------------------------------------------------
  /// Logout aman:
  /// 1. Menghentikan listener stream sensor dan timer telemetri.
  /// 2. Mengosongkan data pembacaan sensor aktif.
  /// 3. Menghapus status koneksi lokal pengguna sebelumnya.
  /// 4. Memanggil Firebase signOut.
  Future<void> signOut() async {
    try {
      // 1. Hentikan listener perangkat IoT & timer simulasi
      SensorStreamService.instance.stopStreaming();
      SensorStreamService.instance.pauseStreamingToZero();

      // 2. Bersihkan status koneksi lokal pengguna
      await DeviceService.saveConnectionState(false);
      await DeviceService.saveDevicePower(false);

      // 3. Logout dari sesi Firebase jika tersedia
      final auth = _auth;
      if (auth != null) {
        await auth.signOut();
      }
    } catch (e) {
      debugPrint('AuthService.signOut error: $e');
      final auth = _auth;
      if (auth != null) {
        await auth.signOut();
      }
    }
  }

  // ----------------------------------------------------
  // PENERJEMAH ERROR FIREBASE KE INDONESIA
  // ----------------------------------------------------
  static String getReadableErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Akun dengan email ini tidak ditemukan.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email atau kata sandi tidak valid. Silakan periksa kembali.';
      case 'email-already-in-use':
        return 'Email ini sudah terdaftar. Silakan login atau gunakan menu lupa kata sandi.';
      case 'invalid-email':
        return 'Format email tidak valid. Masukkan email yang benar.';
      case 'weak-password':
        return 'Kata sandi terlalu lemah. Gunakan minimal 6 karakter kombinasi.';
      case 'user-disabled':
        return 'Akun ini telah dinonaktifkan. Hubungi administrator SIMETRI.';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan gagal. Silakan tunggu beberapa saat lagi.';
      case 'network-request-failed':
        return 'Koneksi internet terputus. Pastikan perangkat Anda online.';
      case 'operation-not-allowed':
        return 'Metode login Email/Password belum diaktifkan di Firebase Console.';
      default:
        return 'Terjadi kendala autentikasi ($code). Silakan coba lagi.';
    }
  }
}

/// Kelas error khusus untuk pesan autentikasi ramah pengguna
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}
