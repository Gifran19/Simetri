// File: lib/config/emulator_config.dart
//
// ============================================================
//  KONFIGURASI FIREBASE EMULATOR UNTUK PENGUJIAN LOKAL
//
//  Aktifkan mode emulator dengan flag compile-time:
//    flutter run --dart-define=USE_FIREBASE_EMULATOR=true
//
//  JANGAN aktifkan emulator di build produksi/release.
//  Emulator hanya untuk pengujian lokal dengan Firebase Emulator Suite.
//
//  Panduan menjalankan emulator:
//    cd backend
//    firebase emulators:start
// ============================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Apakah mode emulator diaktifkan via --dart-define=USE_FIREBASE_EMULATOR=true
const bool _kUseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);

/// Alamat host emulator (dapat di-override via --dart-define)
const String _kEmulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '127.0.0.1',
);

const int _kAuthEmulatorPort = 9099;
const int _kDatabaseEmulatorPort = 9000;
const int _kFunctionsEmulatorPort = 5001;

/// Project ID emulator yang konsisten — gunakan demo-* agar tidak ada billing
const String kEmulatorProjectId = 'simetri-app';

/// Namespace database emulator
const String kEmulatorDatabaseNamespace = 'simetri-app-default-rtdb';

/// Apakah saat ini berjalan dalam mode emulator
bool get isEmulatorMode => _kUseEmulator;

/// Konfigurasi seluruh layanan Firebase ke emulator lokal.
///
/// WAJIB dipanggil SEBELUM Firebase.initializeApp() atau sebelum
/// autentikasi dan listener database dimulai.
///
/// Urutan yang benar:
///   1. WidgetsFlutterBinding.ensureInitialized()
///   2. await Firebase.initializeApp(...)
///   3. await EmulatorConfig.configure()   ← harus di sini
///   4. await AuthService.ensureAnonymousSession()
///   5. SensorStreamService / listener lain
Future<void> configureEmulatorIfNeeded() async {
  if (!_kUseEmulator) {
    return; // Tidak dalam mode emulator — tidak ada yang diubah
  }

  debugPrint('');
  debugPrint('════════════════════════════════════════════════════');
  debugPrint('  MODE EMULATOR AKTIF — Tidak ada akses ke produksi');
  debugPrint('  Host: $_kEmulatorHost');
  debugPrint('  Auth Port      : $_kAuthEmulatorPort');
  debugPrint('  Database Port  : $_kDatabaseEmulatorPort');
  debugPrint('  Functions Port : $_kFunctionsEmulatorPort');
  debugPrint('  Project ID     : $kEmulatorProjectId');
  debugPrint('════════════════════════════════════════════════════');

  // 1. Auth Emulator — harus dikonfigurasi sebelum signIn apa pun
  await FirebaseAuth.instance.useAuthEmulator(
    _kEmulatorHost,
    _kAuthEmulatorPort,
  );

  // 2. Realtime Database Emulator
  FirebaseDatabase.instance.useDatabaseEmulator(
    _kEmulatorHost,
    _kDatabaseEmulatorPort,
  );

  // 3. Cloud Functions Emulator
  FirebaseFunctions.instance.useFunctionsEmulator(
    _kEmulatorHost,
    _kFunctionsEmulatorPort,
  );

  debugPrint('  ✓ Semua layanan Firebase dikonfigurasi ke emulator lokal.');
  debugPrint('');
}
