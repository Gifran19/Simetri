// File: lib/firebase_options.dart
//
// ============================================================
//  LANGKAH SETUP FIREBASE:
//  1. Buka https://console.firebase.google.com
//  2. Buat project baru atau pilih project yang sudah ada
//  3. Tambahkan App Android/iOS/Web
//  4. Salin nilai konfigurasi dari Firebase Console ke sini
//  5. Aktifkan "Realtime Database" di Firebase Console
//
//  ATAU gunakan FlutterFire CLI (direkomendasikan):
//  > dart pub global activate flutterfire_cli
//  > flutterfire configure
//  Perintah ini akan otomatis generate file ini.
// ============================================================

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
        throw UnsupportedError('DefaultFirebaseOptions are not supported for this platform.');
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
    apiKey: 'AIzaSyA1DHNn6czhr4850M7Ai2V2DfdO9zWs4tA',
    appId: '1:732808497619:web:3a1a2f2e5b9cdc3b75c726',
    messagingSenderId: '732808497619',
    projectId: 'simentri-b1a4a',
    databaseURL: 'https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'simentri-b1a4a.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA1DHNn6czhr4850M7Ai2V2DfdO9zWs4tA',
    appId: '1:732808497619:web:3a1a2f2e5b9cdc3b75c726',
    messagingSenderId: '732808497619',
    projectId: 'simentri-b1a4a',
    databaseURL: 'https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'simentri-b1a4a.firebasestorage.app',
    iosBundleId: 'com.example.myTestApp',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA1DHNn6czhr4850M7Ai2V2DfdO9zWs4tA',
    appId: '1:732808497619:web:3a1a2f2e5b9cdc3b75c726',
    messagingSenderId: '732808497619',
    projectId: 'simentri-b1a4a',
    databaseURL: 'https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'simentri-b1a4a.firebasestorage.app',
    authDomain: 'simentri-b1a4a.firebaseapp.com',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyA1DHNn6czhr4850M7Ai2V2DfdO9zWs4tA',
    appId: '1:732808497619:web:3a1a2f2e5b9cdc3b75c726',
    messagingSenderId: '732808497619',
    projectId: 'simentri-b1a4a',
    databaseURL: 'https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'simentri-b1a4a.firebasestorage.app',
    iosBundleId: 'com.example.myTestApp',
  );
}
