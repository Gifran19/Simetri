import { describe, it } from 'node:test';
import * as assert from 'node:assert';
import * as path from 'node:path';

const {
  OFFICIAL_PRODUCTION_PROJECT_ID,
  OFFICIAL_PRODUCTION_RTDB_URL,
  validateProductionTarget,
  applyGrantOwner,
  applyAddMember,
  applyTransferOwner,
  applyRecover,
  applyRevoke,
} = require(path.resolve(__dirname, '../../../../scripts/admin_manage_access.js'));

/**
 * Mock Realtime Database In-Memory sederhana untuk menguji logika
 * konsistensi tanpa ketergantungan pada runtime Java / Emulator eksternal.
 */
class MockDatabase {
  private store: Map<string, any> = new Map();

  ref(pathStr: string) {
    const cleanPath = pathStr.replace(/^\/+|\/+$/g, '');
    const self = this;

    return {
      async get() {
        const val = self.store.get(cleanPath);
        return {
          exists: () => val !== undefined && val !== null,
          val: () => (val !== undefined ? JSON.parse(JSON.stringify(val)) : null),
        };
      },

      async set(data: any) {
        self.store.set(cleanPath, JSON.parse(JSON.stringify(data)));
      },

      async update(partialData: any) {
        const existing = self.store.get(cleanPath) || {};
        const merged = { ...existing, ...JSON.parse(JSON.stringify(partialData)) };
        self.store.set(cleanPath, merged);
      },
    };
  }

  getSnapshot(pathStr: string) {
    const cleanPath = pathStr.replace(/^\/+|\/+$/g, '');
    const val = this.store.get(cleanPath);
    return val !== undefined ? JSON.parse(JSON.stringify(val)) : null;
  }
}

describe('SIMETRI Local Admin Unit Tests: Poin 1, 2, dan Konsistensi Hak Akses', () => {

  // ==========================================================================
  // POIN 2: VALIDASI TARGET PRODUKSI SECARA TEPAT
  // ==========================================================================
  describe('Validasi Target Produksi Resmi', () => {
    it('1. Target resmi produksi wajib simentri-b1a4a dan URL Asia Tenggara', () => {
      assert.strictEqual(OFFICIAL_PRODUCTION_PROJECT_ID, 'simentri-b1a4a');
      assert.strictEqual(
        OFFICIAL_PRODUCTION_RTDB_URL,
        'https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app'
      );

      // Verifikasi lolos validasi jika sesuai
      assert.doesNotThrow(() => {
        validateProductionTarget(
          'simentri-b1a4a',
          'https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app'
        );
      });

      // Trailing slash ditoleransi dengan normalisasi otomatis
      assert.doesNotThrow(() => {
        validateProductionTarget(
          'simentri-b1a4a',
          'https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app/'
        );
      });
    });

    it('2. Menolak project ID selain simentri-b1a4a sebelum terjadi penulisan', () => {
      assert.throws(
        () => {
          validateProductionTarget(
            'simentri-staging',
            'https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app'
          );
        },
        /Target Project ID "simentri-staging" tidak valid/i
      );

      assert.throws(
        () => {
          validateProductionTarget(
            'simentri-b1a4a-clone',
            'https://simentri-b1a4a-default-rtdb.asia-southeast1.firebasedatabase.app'
          );
        },
        /Target Project ID "simentri-b1a4a-clone" tidak valid/i
      );
    });

    it('3. Menolak Database URL selain target produksi Asia Tenggara resmi', () => {
      assert.throws(
        () => {
          validateProductionTarget(
            'simentri-b1a4a',
            'https://simentri-b1a4a.firebaseio.com'
          );
        },
        /Target Database URL .* tidak valid/i
      );

      assert.throws(
        () => {
          validateProductionTarget(
            'simentri-b1a4a',
            'https://simentri-b1a4a-default-rtdb.us-central1.firebasedatabase.app'
          );
        },
        /Target Database URL .* tidak valid/i
      );
    });
  });

  // ==========================================================================
  // POIN 1: PEMISAHAN OPERASI & KONSISTENSI ownerUid DAN permissions
  // ==========================================================================
  describe('Pemisahan Operasi: grant-owner, add-member, transfer-owner, recover, revoke', () => {
    const DEV_ID = 'SIMETRI_ESP32_MOCK_01';

    it('4. grant-owner awal berhasil menetapkan pemilik pertama dan role owner', async () => {
      const mockDb = new MockDatabase();
      const userA = 'uid_anon_user_A';

      const res = await applyGrantOwner(mockDb, DEV_ID, userA, 'ESP32 Ruang Tamu');
      assert.strictEqual(res.ownerUid, userA);

      // Verifikasi devices/$deviceId/meta
      const meta = mockDb.getSnapshot(`devices/${DEV_ID}/meta`);
      assert.strictEqual(meta.ownerUid, userA);
      assert.strictEqual(meta.label, 'ESP32 Ruang Tamu');

      // Verifikasi permissions/$uid/$deviceId
      const permA = mockDb.getSnapshot(`permissions/${userA}/${DEV_ID}`);
      assert.strictEqual(permA.status, 'active');
      assert.strictEqual(permA.role, 'owner');
      assert.strictEqual(permA.grantedBy, 'local_admin');
    });

    it('5. grant-owner kedua dengan UID berbeda DITOLAK (tidak boleh diam-diam memindahkan pemilik)', async () => {
      const mockDb = new MockDatabase();
      const userA = 'uid_anon_user_A';
      const userB = 'uid_anon_user_B';

      // User A sudah menjadi owner
      await applyGrantOwner(mockDb, DEV_ID, userA);

      // User B mencoba grant-owner pada perangkat yang sama -> WAJIB DITOLAK
      let rejected = false;
      try {
        await applyGrantOwner(mockDb, DEV_ID, userB);
      } catch (err: any) {
        rejected = true;
        assert.match(err.message, /sudah memiliki pemilik/i);
      }
      assert.strictEqual(rejected, true, 'grant-owner kedua harus ditolak!');

      // Pastikan owner tetap User A
      const meta = mockDb.getSnapshot(`devices/${DEV_ID}/meta`);
      assert.strictEqual(meta.ownerUid, userA);

      // Pastikan User B tidak mendapatkan izin diam-diam
      const permB = mockDb.getSnapshot(`permissions/${userB}/${DEV_ID}`);
      assert.strictEqual(permB, null);
    });

    it('6. add-member menambahkan akses anggota (member) tanpa mengubah ownerUid', async () => {
      const mockDb = new MockDatabase();
      const userOwner = 'uid_anon_owner';
      const userMember = 'uid_anon_member';

      // 1. Set owner awal
      await applyGrantOwner(mockDb, DEV_ID, userOwner);

      // 2. Tambahkan userMember via add-member
      const resMember = await applyAddMember(mockDb, DEV_ID, userMember);
      assert.strictEqual(resMember.ownerUid, userOwner);

      // 3. Verifikasi role member aktif
      const permMember = mockDb.getSnapshot(`permissions/${userMember}/${DEV_ID}`);
      assert.strictEqual(permMember.status, 'active');
      assert.strictEqual(permMember.role, 'member');

      // 4. Pastikan ownerUid pada meta TIDAK BERUBAH
      const meta = mockDb.getSnapshot(`devices/${DEV_ID}/meta`);
      assert.strictEqual(meta.ownerUid, userOwner, 'add-member tidak boleh mengubah ownerUid!');
    });

    it('7. transfer-owner menolak jika oldUserUid tidak sesuai dengan owner saat ini', async () => {
      const mockDb = new MockDatabase();
      const userRealOwner = 'uid_real_owner';
      const userImpostor = 'uid_impostor';
      const userNewOwner = 'uid_new_owner';

      await applyGrantOwner(mockDb, DEV_ID, userRealOwner);

      let rejected = false;
      try {
        await applyTransferOwner(mockDb, DEV_ID, userNewOwner, userImpostor);
      } catch (err: any) {
        rejected = true;
        assert.match(err.message, /Verifikasi pemilik lama gagal/i);
      }
      assert.strictEqual(rejected, true);

      // Owner tetap real owner
      const meta = mockDb.getSnapshot(`devices/${DEV_ID}/meta`);
      assert.strictEqual(meta.ownerUid, userRealOwner);
    });

    it('8. transfer-owner berhasil memindahkan ownerUid, menaikkan newOwner ke owner, dan menurunkan oldOwner ke member', async () => {
      const mockDb = new MockDatabase();
      const userOldOwner = 'uid_old_owner';
      const userNewOwner = 'uid_new_owner';

      await applyGrantOwner(mockDb, DEV_ID, userOldOwner);

      const transferRes = await applyTransferOwner(mockDb, DEV_ID, userNewOwner, userOldOwner);
      assert.strictEqual(transferRes.newOwner, userNewOwner);
      assert.strictEqual(transferRes.oldOwner, userOldOwner);

      // Verifikasi meta.ownerUid berganti
      const meta = mockDb.getSnapshot(`devices/${DEV_ID}/meta`);
      assert.strictEqual(meta.ownerUid, userNewOwner);

      // Verifikasi permissions userNewOwner menjadi owner
      const permNew = mockDb.getSnapshot(`permissions/${userNewOwner}/${DEV_ID}`);
      assert.strictEqual(permNew.status, 'active');
      assert.strictEqual(permNew.role, 'owner');

      // Verifikasi permissions userOldOwner diturunkan ke member
      const permOld = mockDb.getSnapshot(`permissions/${userOldOwner}/${DEV_ID}`);
      assert.strictEqual(permOld.status, 'active');
      assert.strictEqual(permOld.role, 'member');
      assert.match(permOld.note, /Ownership transferred to uid_new_owner/i);
    });

    it('9. recover memindahkan kepemilikan dan mencabut (revoked) UID lama secara eksplisit', async () => {
      const mockDb = new MockDatabase();
      const userLostPhone = 'uid_lost_phone';
      const userNewPhone = 'uid_new_phone';

      // Mula-mula userLostPhone adalah owner
      await applyGrantOwner(mockDb, DEV_ID, userLostPhone);

      // HP hilang, user install app di HP baru -> Jalankan recover dengan mencabut userLostPhone
      const recoverRes = await applyRecover(mockDb, DEV_ID, userNewPhone, userLostPhone);
      assert.strictEqual(recoverRes.newOwner, userNewPhone);
      assert.strictEqual(recoverRes.revokedOldUid, userLostPhone);

      // Verifikasi meta.ownerUid berganti ke userNewPhone
      const meta = mockDb.getSnapshot(`devices/${DEV_ID}/meta`);
      assert.strictEqual(meta.ownerUid, userNewPhone);

      // Verifikasi permissions userNewPhone aktif sebagai owner
      const permNew = mockDb.getSnapshot(`permissions/${userNewPhone}/${DEV_ID}`);
      assert.strictEqual(permNew.status, 'active');
      assert.strictEqual(permNew.role, 'owner');

      // Verifikasi permissions userLostPhone EKSPLISIT DICABUT (revoked)
      const permLost = mockDb.getSnapshot(`permissions/${userLostPhone}/${DEV_ID}`);
      assert.strictEqual(permLost.status, 'revoked');
      assert.strictEqual(permLost.revokedBy, 'local_admin_recovery');
    });

    it('10. revoke mencabut hak akses; jika user adalah owner, meta.ownerUid dikosongkan (null)', async () => {
      const mockDb = new MockDatabase();
      const userOwner = 'uid_owner_to_revoke';
      const userMember = 'uid_member_to_revoke';

      // Daftarkan owner dan member
      await applyGrantOwner(mockDb, DEV_ID, userOwner);
      await applyAddMember(mockDb, DEV_ID, userMember);

      // 1. Cabut member
      const revokeMemberRes = await applyRevoke(mockDb, DEV_ID, userMember);
      assert.strictEqual(revokeMemberRes.wasOwner, false);
      assert.strictEqual(mockDb.getSnapshot(`permissions/${userMember}/${DEV_ID}`).status, 'revoked');
      // meta.ownerUid tetap ada
      assert.strictEqual(mockDb.getSnapshot(`devices/${DEV_ID}/meta`).ownerUid, userOwner);

      // 2. Cabut owner
      const revokeOwnerRes = await applyRevoke(mockDb, DEV_ID, userOwner);
      assert.strictEqual(revokeOwnerRes.wasOwner, true);
      assert.strictEqual(mockDb.getSnapshot(`permissions/${userOwner}/${DEV_ID}`).status, 'revoked');
      // meta.ownerUid menjadi null
      assert.strictEqual(mockDb.getSnapshot(`devices/${DEV_ID}/meta`).ownerUid, null);
    });
  });

  // ==========================================================================
  // POIN 3: KEAMANAN SECURITY RULES PADA PARENT LEVEL devices/$deviceId
  // ==========================================================================
  describe('Audit Keamanan database.rules.json (Pencegahan Kebocoran Parent Cascade)', () => {
    const fs = require('node:fs');
    const rulesPath = path.resolve(__dirname, '../../../../database.rules.json');
    const rawJson = fs.readFileSync(rulesPath, 'utf8');
    const parsed = JSON.parse(rawJson);
    const rules = parsed.rules;

    it('11. Root database rules wajib .read: false dan .write: false', () => {
      assert.strictEqual(rules['.read'], false, 'Root .read wajib false');
      assert.strictEqual(rules['.write'], false, 'Root .write wajib false');
    });

    it('12. Parent collection devices TIDAK MEMILIKI .read maupun .write', () => {
      assert.strictEqual(rules.devices['.read'], undefined, 'Collection devices tidak boleh memiliki .read');
      assert.strictEqual(rules.devices['.write'], undefined, 'Collection devices tidak boleh memiliki .write');
    });

    it('13. Parent node devices/$deviceId TIDAK MEMILIKI .read maupun .write (Mencegah Bypass Child Rules)', () => {
      const devNode = rules.devices['$deviceId'];
      assert.ok(devNode, 'Path devices/$deviceId wajib terdefinisi');

      // VERIFIKASI KRITIS: Tidak ada .read atau .write di level devices/$deviceId
      assert.strictEqual(
        devNode['.read'],
        undefined,
        'devices/$deviceId TIDAK BOLEH memiliki .read karena akan meng-override pembatasan child node'
      );
      assert.strictEqual(
        devNode['.write'],
        undefined,
        'devices/$deviceId TIDAK BOLEH memiliki .write karena akan meng-override pembatasan child node'
      );
    });

    it('14. Pembatasan akses terisolasi ketat hanya pada masing-masing child node', () => {
      const devNode = rules.devices['$deviceId'];

      // 1. meta: .read dibatasi, .write wajib false
      assert.ok(devNode.meta['.read'], 'meta wajib memiliki .read berbasis permission/deviceUid');
      assert.strictEqual(devNode.meta['.write'], false, 'meta .write wajib false (hanya Admin SDK)');

      // 2. live: .read berbasis permission/deviceUid, .write hanya deviceUid
      assert.ok(devNode.live['.read']);
      assert.match(devNode.live['.write'], /'esp32_'\s*\+\s*\$deviceId/);

      // 3. control: .read berbasis permission/deviceUid, .write hanya user dengan status active
      assert.ok(devNode.control['.read']);
      assert.match(devNode.control['.write'], /permissions.*status.*===.*'active'/);

      // 4. permissions node: user hanya bisa baca miliknya sendiri, write false
      assert.ok(rules.permissions['$uid']['.read']);
      assert.strictEqual(rules.permissions['$uid']['.write'], false);
    });
  });
});
