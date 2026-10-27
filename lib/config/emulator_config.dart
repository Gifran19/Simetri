// File: lib/config/emulator_config.dart
//
// ============================================================
//  KONFIGURASI FIREBASE EMULATOR UNTUK PENGUJIAN LOKAL
//
//  Aktifkan mode emulator dengan flag compile-time:
//    flutter run --dart-define=USE_FIREBASE_EMULATOR=true
//
//  Host Konfigurasi Berdasarkan Target Perangkat:
//  - Android Emulator (AVD) : Otomatis menggunakan "10.0.2.2"
//  - iOS Simulator / Web    : Menggunakan "127.0.0.1"
//  - Ponsel Fisik (Android/iOS):
//      flutter run --dart-define=USE_FIREBASE_EMULATOR=true \
//                  --dart-define=EMULATOR_HOST=192.168.1.50
//      (Ganti 192.168.1.50 dengan IP komputer pengembang di Wi-Fi yang sama)
// ============================================================

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Apakah mode emulator diaktifkan via --dart-define=USE_FIREBASE_EMULATOR=true
const bool _kUseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);

/// Alamat host eksplisit jika ditentukan via --dart-define=EMULATOR_HOST=...
const String _kExplicitHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '');

const int kAuthEmulatorPort = 9099;
const int kDatabaseEmulatorPort = 9000;
const int kFunctionsEmulatorPort = 5001;

/// Project ID emulator yang konsisten dan terisolasi
const String kEmulatorProjectId = 'simetri-app';

/// Namespace database emulator
const String kEmulatorDatabaseNamespace = 'simetri-app-default-rtdb';

/// Mendapatkan host yang sesuai dengan platform pengujian
String get emulatorHost {
  if (_kExplicitHost.isNotEmpty) {
    return _kExplicitHost;
  }
  // Android Emulator (AVD) memetakan 10.0.2.2 ke 127.0.0.1 komputer host
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return '10.0.2.2';
  }
  // iOS Simulator, macOS Desktop, Windows Desktop, dan Web
  return '127.0.0.1';
}

/// Status apakah aplikasi saat ini berjalan dalam mode emulator
bool get isEmulatorMode => _kUseEmulator;

class EmulatorConfig {
  /// FirebaseOptions khusus untuk lingkungan emulator lokal.
  /// Memastikan project ID dan database URL (beserta parameter namespace)
  /// benar-benar digunakan saat Firebase.initializeApp dipanggil.
  static FirebaseOptions get emulatorFirebaseOptions {
    final host = emulatorHost;
    return FirebaseOptions(
      apiKey: 'fake-emulator-api-key',
      appId: '1:1234567890:android:simetri_emulator_app',
      messagingSenderId: '1234567890',
      projectId: kEmulatorProjectId,
      databaseURL: 'http://$host:$kDatabaseEmulatorPort?ns=$kEmulatorDatabaseNamespace',
      storageBucket: '$kEmulatorProjectId.appspot.com',
    );
  }

  /// Konfigurasi seluruh layanan Firebase SDK (Auth, RTDB, Functions) ke emulator lokal.
  static Future<void> configure() async {
    if (!_kUseEmulator) return;

    final host = emulatorHost;

    debugPrint('');
    debugPrint('════════════════════════════════════════════════════');
    debugPrint('  MODE EMULATOR AKTIF');
    debugPrint('  Target Host    : $host');
    debugPrint('  Auth Port      : $kAuthEmulatorPort');
    debugPrint('  Database Port  : $kDatabaseEmulatorPort (ns: $kEmulatorDatabaseNamespace)');
    debugPrint('  Functions Port : $kFunctionsEmulatorPort');
    debugPrint('  Project ID     : $kEmulatorProjectId');
    debugPrint('════════════════════════════════════════════════════');

    // 1. Auth Emulator
    await FirebaseAuth.instance.useAuthEmulator(host, kAuthEmulatorPort);

    // 2. Realtime Database Emulator
    FirebaseDatabase.instance.useDatabaseEmulator(host, kDatabaseEmulatorPort);

    // 3. Cloud Functions Emulator
    FirebaseFunctions.instance.useFunctionsEmulator(host, kFunctionsEmulatorPort);

    debugPrint('  ✓ Layanan Firebase terhubung ke emulator lokal.');
    debugPrint('');
  }
}

/// Helper fungsi untuk backward compatibility panggilan di main.dart
Future<void> configureEmulatorIfNeeded() async {
  await EmulatorConfig.configure();
}
