// File: lib/firebase_options.example.dart
//
// ============================================================
//  PETUNJUK SETUP FIREBASE:
//
//  1. Salin file ini menjadi lib/firebase_options.dart:
//       cp lib/firebase_options.example.dart lib/firebase_options.dart
//
//  2. Ganti semua nilai YOUR_* dengan kredensial Firebase Anda.
//     Kredensial dapat diperoleh dari:
//     https://console.firebase.google.com → Project Settings → Your Apps
//
//  3. JANGAN commit lib/firebase_options.dart ke repository.
//     File tersebut sudah dikecualikan via .gitignore.
//
//  ALTERNATIF (Direkomendasikan):
//  Gunakan FlutterFire CLI untuk generate otomatis:
//    dart pub global activate flutterfire_cli
//    flutterfire configure
// ============================================================

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError(
            'DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  /// Cek apakah Firebase sudah dikonfigurasi dengan kredensial asli
  static bool get isConfigured {
    try {
      final opts = currentPlatform;
      return !opts.apiKey.contains('YOUR_') &&
          !opts.projectId.contains('YOUR_') &&
          opts.apiKey.isNotEmpty &&
          opts.projectId.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // GANTI SEMUA NILAI DI BAWAH INI DENGAN DATA FIREBASE ANDA
  // ============================================================

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    databaseURL: 'YOUR_DATABASE_URL',
    storageBucket: 'YOUR_STORAGE_BUCKET',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    databaseURL: 'YOUR_DATABASE_URL',
    storageBucket: 'YOUR_STORAGE_BUCKET',
    iosBundleId: 'YOUR_IOS_BUNDLE_ID',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY',
    appId: 'YOUR_WEB_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    databaseURL: 'YOUR_DATABASE_URL',
    storageBucket: 'YOUR_STORAGE_BUCKET',
    authDomain: 'YOUR_AUTH_DOMAIN',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: 'YOUR_MACOS_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    databaseURL: 'YOUR_DATABASE_URL',
    storageBucket: 'YOUR_STORAGE_BUCKET',
    iosBundleId: 'YOUR_MACOS_BUNDLE_ID',
  );
}
