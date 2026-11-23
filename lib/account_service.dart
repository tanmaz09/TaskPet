import 'auth_service.dart';
import 'firestore_client.dart';
import 'sync_service.dart';

/// Deleting your online presence. Your tasks and progress live on the phone
/// and are never touched here.
class AccountService {
  final AuthService auth;
  final FirestoreClient fs;
  final SyncService sync;

  AccountService({required this.auth, required this.fs, required this.sync});

  static final AccountService instance = AccountService(
    auth: AuthService.instance,
    fs: FirestoreClient(tokenProvider: AuthService.instance.idToken),
    sync: SyncService.instance,
  );

  /// Removes everything stored online for this phone: all friendships and
  /// requests, the pet snapshot, the friend code, and the account itself.
  /// Safe to run again if it was interrupted: steps that are already done
  /// are skipped. Throws if the phone is offline, and leaves online
  /// features on so the user can simply retry.
  Future<void> deleteOnlineProfile() async {
    sync.suspended = true; // nothing may recreate the profile meanwhile
    try {
      final me = (await auth.ensureSignedIn()).uid;

      // Find the friend code first, because it lives in the profile.
      var code = sync.friendCode;
      if (code == null) {
        final profile = await fs.getDoc('users/$me');
        final c = profile?['friendCode'];
        if (c is String) code = c;
      }

      // 1. every friendship and request involving me
      final links = await fs.queryArrayContains('friendships', 'members', me);
      for (final l in links) {
        await fs.deleteDoc('friendships/${l.id}');
      }

      // 2. my pet snapshot
      await fs.deleteDoc('users/$me');

      // 3. my friend code (already gone counts as done)
      if (code != null) {
        try {
          await fs.deleteDoc('friendCodes/$code');
        } on FirestoreException catch (e) {
          if (!e.denied && !e.notFound) rethrow;
        }
      }

      // 4. the sign-in account, then switch online features off
      await auth.deleteAccount();
      await sync.turnOff();
    } finally {
      sync.suspended = false;
    }
  }
}
