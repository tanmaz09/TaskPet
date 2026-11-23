import 'auth_service.dart';
import 'firestore_client.dart';
import 'sync_service.dart';

enum FriendStatus { friend, incoming, outgoing }

enum SendResult {
  sent, // request created
  nowFriends, // they had already asked you, so it was accepted
  alreadyFriends,
  alreadySent,
  notFound,
  selfCode,
  invalidCode,
}

/// What a friend's public snapshot says. Task titles are never part of it.
class FriendProfile {
  final String name;
  final String friendCode;
  final int stage;
  final int energy;
  final int streak;
  final int longestStreak;
  final int totalPerfectDays;
  final int perfectWeeks;
  final String weekStart;
  final int weekPerfect;
  final int doneToday;
  final int totalToday;
  final bool restToday;
  final bool feast;
  final DateTime? updatedAt;

  const FriendProfile({
    required this.name,
    required this.friendCode,
    required this.stage,
    required this.energy,
    required this.streak,
    required this.longestStreak,
    required this.totalPerfectDays,
    required this.perfectWeeks,
    required this.weekStart,
    required this.weekPerfect,
    required this.doneToday,
    required this.totalToday,
    required this.restToday,
    required this.feast,
    required this.updatedAt,
  });

  static int _i(Object? v) => v is int ? v : 0;

  factory FriendProfile.fromMap(Map<String, Object?> m) => FriendProfile(
        name: m['name'] is String ? m['name'] as String : 'Friend',
        friendCode: m['friendCode'] is String ? m['friendCode'] as String : '',
        stage: _i(m['stage']).clamp(0, 4),
        energy: _i(m['energy']).clamp(0, 100),
        streak: _i(m['streak']),
        longestStreak: _i(m['longestStreak']),
        totalPerfectDays: _i(m['totalPerfectDays']),
        perfectWeeks: _i(m['perfectWeeks']),
        weekStart: m['weekStart'] is String ? m['weekStart'] as String : '',
        weekPerfect: _i(m['weekPerfect']).clamp(0, 7),
        doneToday: _i(m['doneToday']),
        totalToday: _i(m['totalToday']),
        restToday: m['restToday'] == true,
        feast: m['feast'] == true,
        updatedAt: m['updatedAt'] is DateTime ? m['updatedAt'] as DateTime : null,
      );

  /// This week's perfect days. If the friend hasn't opened the app since the
  /// week rolled over, their saved count belongs to an old week, so it is 0.
  int effectiveWeekPerfect(String currentMonday) =>
      weekStart == currentMonday ? weekPerfect : 0;
}

class FriendEntry {
  final String uid;
  final FriendStatus status;

  /// Incoming requests: the name of the person asking.
  final String? requesterName;

  /// Outgoing requests: the code you typed.
  final String? code;

  /// Accepted friends: their snapshot (null if they haven't synced yet).
  FriendProfile? profile;

  FriendEntry({
    required this.uid,
    required this.status,
    this.requesterName,
    this.code,
    this.profile,
  });

  String get displayName => profile?.name ?? requesterName ?? 'Friend';
}

/// Friend requests: send by code, accept, decline, remove. Needs the
/// Firestore rules from the setup steps. Calls throw [AuthException] or
/// [FirestoreException] when something goes wrong (offline, rules, ...).
class FriendsService {
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final AuthService auth;
  final FirestoreClient fs;
  final Future<String> Function() nameProvider;

  FriendsService({
    required this.auth,
    required this.fs,
    required this.nameProvider,
  });

  static final FriendsService instance = FriendsService(
    auth: AuthService.instance,
    fs: FirestoreClient(tokenProvider: AuthService.instance.idToken),
    nameProvider: SyncService.instance.displayName,
  );

  /// Same pairing rule the Firestore rules use, so both people get one
  /// shared document.
  static String pairId(String a, String b) =>
      a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  static String normalizeCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  static bool isValidCode(String code) =>
      code.length == 6 && code.split('').every(_alphabet.contains);

  /// Monday of the current week as yyyy-MM-dd (matches the app's weekStart).
  static String currentMonday() {
    final n = DateTime.now();
    final m = DateTime(n.year, n.month, n.day)
        .subtract(Duration(days: n.weekday - 1));
    return '${m.year}-${m.month.toString().padLeft(2, '0')}-'
        '${m.day.toString().padLeft(2, '0')}';
  }

  // -------------------------------------------------------------- load

  /// Everyone connected to you: incoming requests first, then friends
  /// (A to Z), then requests you sent.
  Future<List<FriendEntry>> load() async {
    final me = (await auth.ensureSignedIn()).uid;
    final rows = await fs.queryArrayContains('friendships', 'members', me);

    final entries = <FriendEntry>[];
    final fetches = <Future<void>>[];
    for (final r in rows) {
      final d = r.data;
      final members = (d['members'] is List)
          ? (d['members'] as List).whereType<String>().toList()
          : <String>[];
      final other = members.firstWhere((m) => m != me, orElse: () => '');
      if (other.isEmpty) continue;

      if (d['status'] == 'accepted') {
        final e = FriendEntry(uid: other, status: FriendStatus.friend);
        entries.add(e);
        fetches.add(fs
            .getDoc('users/$other')
            .then((m) {
              if (m != null) e.profile = FriendProfile.fromMap(m);
            })
            .catchError((Object _) {})); // one failure shouldn't hide the rest
      } else if (d['requester'] == me) {
        entries.add(FriendEntry(
          uid: other,
          status: FriendStatus.outgoing,
          code: d['toCode'] is String ? d['toCode'] as String : null,
        ));
      } else {
        entries.add(FriendEntry(
          uid: other,
          status: FriendStatus.incoming,
          requesterName:
              d['requesterName'] is String ? d['requesterName'] as String : null,
        ));
      }
    }
    await Future.wait(fetches);

    int rank(FriendStatus s) => switch (s) {
          FriendStatus.incoming => 0,
          FriendStatus.friend => 1,
          FriendStatus.outgoing => 2,
        };
    entries.sort((a, b) {
      final c = rank(a.status).compareTo(rank(b.status));
      return c != 0
          ? c
          : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return entries;
  }

  // -------------------------------------------------------------- send

  Future<SendResult> sendRequest(String rawCode) async {
    final code = normalizeCode(rawCode);
    if (!isValidCode(code)) return SendResult.invalidCode;

    final me = (await auth.ensureSignedIn()).uid;
    final owner = await fs.getDoc('friendCodes/$code');
    final theirUid = owner?['uid'];
    if (theirUid is! String) return SendResult.notFound;
    if (theirUid == me) return SendResult.selfCode;

    final pair = pairId(me, theirUid);
    Map<String, Object?>? existing;
    try {
      existing = await fs.getDoc('friendships/$pair');
    } on FirestoreException catch (e) {
      // Firestore answers "denied" instead of "not found" for a document
      // that doesn't exist yet, because the rules can't read it.
      if (!e.denied) rethrow;
    }

    if (existing != null) {
      if (existing['status'] == 'accepted') return SendResult.alreadyFriends;
      if (existing['requester'] == me) return SendResult.alreadySent;
      // They already asked you: adding their code accepts it.
      await fs.patchFields('friendships/$pair', {'status': 'accepted'});
      return SendResult.nowFriends;
    }

    final members = [me, theirUid]..sort();
    try {
      await fs.createDoc('friendships', pair, {
        'members': members,
        'requester': me,
        'requesterName': await nameProvider(),
        'toCode': code,
        'status': 'pending',
        'createdAt': DateTime.now().toUtc(),
      });
    } on FirestoreException catch (e) {
      if (e.alreadyExists) return SendResult.alreadySent; // lost a race
      rethrow;
    }
    return SendResult.sent;
  }

  // ----------------------------------------------------------- respond

  Future<void> accept(String otherUid) async {
    final me = (await auth.ensureSignedIn()).uid;
    await fs.patchFields(
        'friendships/${pairId(me, otherUid)}', {'status': 'accepted'});
  }

  /// Declines an incoming request, cancels one you sent, or removes a friend.
  Future<void> remove(String otherUid) async {
    final me = (await auth.ensureSignedIn()).uid;
    await fs.deleteDoc('friendships/${pairId(me, otherUid)}');
  }
}
