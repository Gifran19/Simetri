import 'package:flutter_test/flutter_test.dart';
import 'package:my_test_app/services/access_approval_service.dart';

void main() {
  group('Owner vs Member Permission Access Logic Tests', () {
    test('AccessApprovalResult correctly identifies owner role only when active', () {
      const ownerActive = AccessApprovalResult(
        status: AccessStatus.active,
        deviceId: 'SIMETRI_ESP32_001',
        role: 'owner',
        message: 'Owner granted',
      );
      expect(ownerActive.isOwner, isTrue);
      expect(ownerActive.isGranted, isTrue);

      const memberActive = AccessApprovalResult(
        status: AccessStatus.active,
        deviceId: 'SIMETRI_ESP32_001',
        role: 'member',
        message: 'Member granted',
      );
      expect(memberActive.isOwner, isFalse);
      expect(memberActive.isGranted, isTrue);

      const ownerRevoked = AccessApprovalResult(
        status: AccessStatus.revoked,
        deviceId: 'SIMETRI_ESP32_001',
        role: 'owner',
        message: 'Owner revoked',
      );
      expect(ownerRevoked.isOwner, isFalse);
      expect(ownerRevoked.isGranted, isFalse);

      const ownerPending = AccessApprovalResult(
        status: AccessStatus.pending,
        deviceId: 'SIMETRI_ESP32_001',
        role: 'owner',
        message: 'Pending approval',
      );
      expect(ownerPending.isOwner, isFalse);
      expect(ownerPending.isGranted, isFalse);
    });

    test('DeviceMember serialization and deserialization preserves all fields', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final memberMap = {
        'uid': 'user_test_uid_123',
        'role': 'member',
        'status': 'active',
        'label': 'Kamar Anak',
        'addedAt': now,
        'addedBy': 'owner_test_uid_999',
      };

      final member = DeviceMember.fromMap('user_test_uid_123', memberMap);
      expect(member.uid, equals('user_test_uid_123'));
      expect(member.role, equals('member'));
      expect(member.status, equals('active'));
      expect(member.isActive, isTrue);
      expect(member.label, equals('Kamar Anak'));
      expect(member.addedAt, equals(now));
      expect(member.addedBy, equals('owner_test_uid_999'));

      final serialized = member.toMap();
      expect(serialized['uid'], equals('user_test_uid_123'));
      expect(serialized['role'], equals('member'));
      expect(serialized['status'], equals('active'));
      expect(serialized['label'], equals('Kamar Anak'));
      expect(serialized['addedBy'], equals('owner_test_uid_999'));
    });

    test('DeviceMember correctly handles revoked status and default labels', () {
      final revokedMap = {
        'role': 'member',
        'status': 'revoked',
      };

      final revokedMember = DeviceMember.fromMap('revoked_user_456', revokedMap);
      expect(revokedMember.uid, equals('revoked_user_456'));
      expect(revokedMember.isActive, isFalse);
      expect(revokedMember.label, isEmpty);
      expect(revokedMember.addedBy, isNull);
    });
  });
}
