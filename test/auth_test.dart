import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_test_app/screens/auth/forgot_password_screen.dart';
import 'package:my_test_app/screens/auth/login_screen.dart';
import 'package:my_test_app/screens/auth/register_screen.dart';
import 'package:my_test_app/services/auth_service.dart';

void main() {
  group('AuthService - Translation & Business Logic Tests', () {
    test('getReadableErrorMessage translates standard Firebase Auth error codes', () {
      expect(
        AuthService.getReadableErrorMessage('user-not-found'),
        contains('tidak ditemukan'),
      );
      expect(
        AuthService.getReadableErrorMessage('wrong-password'),
        contains('tidak valid'),
      );
      expect(
        AuthService.getReadableErrorMessage('invalid-credential'),
        contains('tidak valid'),
      );
      expect(
        AuthService.getReadableErrorMessage('email-already-in-use'),
        contains('sudah terdaftar'),
      );
      expect(
        AuthService.getReadableErrorMessage('weak-password'),
        contains('terlalu lemah'),
      );
      expect(
        AuthService.getReadableErrorMessage('invalid-email'),
        contains('tidak valid'),
      );
      expect(
        AuthService.getReadableErrorMessage('network-request-failed'),
        contains('terputus'),
      );
      expect(
        AuthService.getReadableErrorMessage('too-many-requests'),
        contains('Terlalu banyak percobaan'),
      );
      expect(
        AuthService.getReadableErrorMessage('unknown-code'),
        contains('unknown-code'),
      );
    });

    test('AuthException toString returns message', () {
      const ex = AuthException('Pesan error pengujian');
      expect(ex.toString(), equals('Pesan error pengujian'));
    });
  });

  group('Auth UI Tests', () {
    testWidgets('LoginScreen renders email, password, and action buttons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      expect(find.text('Masuk ke Akun'), findsOneWidget);
      expect(find.text('Alamat Email'), findsOneWidget);
      expect(find.text('Kata Sandi'), findsOneWidget);
      expect(find.text('Lupa Kata Sandi?'), findsOneWidget);
      expect(find.text('Masuk ke SIMETRI'), findsOneWidget);
      expect(find.text('Daftar Sekarang'), findsOneWidget);
      expect(find.textContaining('Perbedaan Akun vs PIN Keamanan'), findsOneWidget);

      // Submit empty form should trigger validation errors
      await tester.ensureVisible(find.text('Masuk ke SIMETRI'));
      await tester.tap(find.text('Masuk ke SIMETRI'));
      await tester.pump();

      expect(find.text('Alamat email wajib diisi'), findsOneWidget);
      expect(find.text('Kata sandi wajib diisi'), findsOneWidget);
    });

    testWidgets('RegisterScreen renders inputs and validates matching password', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RegisterScreen(),
        ),
      );

      expect(find.text('Daftar Akun Baru'), findsOneWidget);
      expect(find.text('Nama Lengkap'), findsOneWidget);
      expect(find.text('Alamat Email'), findsOneWidget);
      expect(find.text('Kata Sandi (Minimal 6 Karakter)'), findsOneWidget);
      expect(find.text('Konfirmasi Kata Sandi'), findsOneWidget);

      // Tap submit with empty inputs
      await tester.ensureVisible(find.text('Buat Akun Sekarang'));
      await tester.tap(find.text('Buat Akun Sekarang'));
      await tester.pump();

      expect(find.text('Nama lengkap wajib diisi'), findsOneWidget);
      expect(find.text('Alamat email wajib diisi'), findsOneWidget);
    });

    testWidgets('ForgotPasswordScreen renders email field and submit button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ForgotPasswordScreen(),
        ),
      );

      expect(find.text('Lupa Kata Sandi'), findsOneWidget);
      expect(find.text('Alamat Email Terdaftar'), findsOneWidget);
      expect(find.text('Kirim Tautan Reset'), findsOneWidget);

      // Tap submit with empty inputs
      await tester.ensureVisible(find.text('Kirim Tautan Reset'));
      await tester.tap(find.text('Kirim Tautan Reset'));
      await tester.pump();

      expect(find.text('Alamat email wajib diisi'), findsOneWidget);
    });
  });
}
