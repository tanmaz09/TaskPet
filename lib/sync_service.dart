import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'firestore_client.dart';
import 'leaderboard.dart';
import 'models.dart';

enum SyncState { off, connecting, synced, offline, error }

/// Keeps a small public snapshot of your pet (stage, energy, streak, this
/// week's perfect days) in Firestore so friends can see it. Your tasks never
/// leave the phone. Everything here fails quietly: if you're offline or the
/// setup isn't finished, the app just carries on locally.
class SyncService {
  static const _kCode = 'friend_code';
  static const _kCodeUid = 'friend_code_uid';
  static const _kName = 'display_name';
  static const _kEnabled = 'online_enabled';
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I

  final AuthService auth;
  final FirestoreClient fs;

  SyncService({required this.auth, required this.fs});

  static final SyncService instance = SyncService(
    auth: AuthService.instance,
    fs: FirestoreClient(tokenProvider: AuthService.instance.idToken),
  );

  final ValueNotifier<SyncState> status = ValueNotifier(SyncState.off);

    /// Online features are opt-in. This stays false until the user turns them
  /// on (and again after the online profile is deleted). Nothing is sent to
  /// the server, and no anonymous account is created, while it is false.
  final ValueNotifier<bool> enabled = ValueNotifier(false);
  /// Set briefly while an account deletion is running, so a sync can't
  /// recreate the profile half-way through.
  bool suspended = false;
  DateTime? lastSyncAt;
  String? friendCode;
  String? lastError;

  GameState? _state;
  Timer? _timer;
  bool _busy = false;
  String? _lastSig;
  DateTime? _backoffUntil;
  String? _name;

  /// Call once at startup. Does nothing until Firebase is configured.
  Future<void> start(GameState state) async {
    _state = state;
    if (!auth.isConfigured) {
      status.value = SyncState.off;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_kEnabled) ?? false;
    if (!enabled.value) {
      status.value = SyncState.off;
      return;
    }
    _timer?.cancel();
    // Cheap check every 30 s: only talks to the server when something changed.
    _timer = Timer.periodic(
        const Duration(seconds: 30), (_) => pushIfChanged());
    await pushIfChanged(force: true);
  }

  /// Switches online features off and forgets the local copy of the friend
  /// code. Used after the online profile was deleted.
  Future<void> turnOff() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, false);
    await prefs.remove(_kCode);
    await prefs.remove(_kCodeUid);
    enabled.value = false;
    stop();
    friendCode = null;
    _codeUid = null;
    _lastSig = null;
    _backoffUntil = null;
    status.value = SyncState.off;
  }

  /// Switches online features back on; a new profile and friend code are
  /// created on the next sync.
  Future<void> turnOn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, true);
    enabled.value = true;
    final state = _state;
    if (state != null) await start(state);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  // ------------------------------------------------------------- name

  Future<String> displayName() async {
    if (_name != null) return _name!;
    final p = await SharedPreferences.getInstance();
    _name = _cleanName(p.getString(_kName) ?? '');
    return _name!;
  }

  Future<void> setDisplayName(String raw) async {
    _name = _cleanName(raw);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kName, _name!);
    unawaited(pushIfChanged());
  }

  static String _cleanName(String raw) {
    var n = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.length > 20) n = n.substring(0, 20).trim();
    return n.isEmpty ? 'Trainer' : n;
  }

  // ------------------------------------------------------------- push

  Future<void> pushIfChanged({bool force = false}) async {
    final state = _state;
    if (state == null || !auth.isConfigured || _busy) return;
    if (!enabled.value || suspended) return;
    final backoff = _backoffUntil;
    if (!force && backoff != null && DateTime.now().isBefore(backoff)) return;

    _busy = true;
    if (status.value != SyncState.synced) status.value = SyncState.connecting;
    try {
      final session = await auth.ensureSignedIn();
      final code = await _ensureFriendCode(session.uid);
      final data = _snapshot(state, code, await displayName());
      final sig = jsonEncode(data);
      if (!force && sig == _lastSig) {
        status.value = SyncState.synced;
        return;
      }
      data['updatedAt'] = DateTime.now().toUtc();
      await _write(session.uid, data);
      _lastSig = sig;
      lastSyncAt = DateTime.now();
      lastError = null;
      _backoffUntil = null;
      status.value = SyncState.synced;
    } on AuthException catch (e) {
      _fail(e.message, e.network);
    } on FirestoreException catch (e) {
      _fail(e.message, e.network);
    } catch (e) {
      _fail('$e', false);
    } finally {
      _busy = false;
    }
  }

  void _fail(String message, bool network) {
    if (network) {
      status.value = SyncState.offline; // try again on the next tick
      return;
    }
    lastError = message;
    status.value = SyncState.error;
    // Don't hammer the server over a problem that retrying won't fix.
    _backoffUntil = DateTime.now().add(const Duration(minutes: 5));
    debugPrint('Sync failed: $message');
  }

  Future<void> _write(String uid, Map<String, Object?> data) async {
    final path = 'users/$uid';
    try {
      await fs.setDoc(path, data);
    } on FirestoreException catch (e) {
      if (!e.denied) rethrow;
      // The rules limit how fast numbers may jump (for example after
      // restoring a backup). Recreating the profile starts it fresh.
      await fs.deleteDoc(path);
      await fs.setDoc(path, data);
    }
  }

  Map<String, Object?> _snapshot(GameState s, String code, String name) {
    int c(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
    var week = s.weekStart;
    if (week.length != 10) {
      final n = DateTime.now();
      week = '${n.year}-${n.month.toString().padLeft(2, '0')}-'
          '${n.day.toString().padLeft(2, '0')}';
    }
    return {
      'name': name,
      'friendCode': code,
      'stage': c(GameState.stages.indexOf(s.stage), 0, 4),
      'energy': c(s.energy, 0, 100),
      'streak': c(s.streak, 0, 3650),
      'longestStreak': c(s.longestStreak, 0, 3650),
      'totalPerfectDays': c(s.totalPerfectDays, 0, 3650),
      'perfectWeeks': c(s.perfectWeeks, 0, 520),
      'weekStart': week,
      'weekPerfect': c(rankedThisWeek(s), 0, 7),
      'doneToday': c(s.doneToday, 0, 50),
      'totalToday': c(s.tasks.length, 0, 50),
      'restToday': s.isRestToday,
      'feast': s.feastActive,
    };
  }

  // ------------------------------------------------------ friend code

  static String generateCode([Random? rnd]) {
    final r = rnd ?? Random.secure();
    return List.generate(6, (_) => _alphabet[r.nextInt(_alphabet.length)])
        .join();
  }

  Future<String> _ensureFriendCode(String uid) async {
    if (friendCode != null && _codeUid == uid) return friendCode!;
    final p = await SharedPreferences.getInstance();
    final stored = p.getString(_kCode);
    if (stored != null && p.getString(_kCodeUid) == uid) {
      return _remember(p, uid, stored);
    }

    // The account may already have a profile (for example after clearing
    // app data), so reuse its code if there is one.
    final existing = await fs.getDoc('users/$uid');
    final existingCode = existing?['friendCode'];
    if (existingCode is String && existingCode.length == 6) {
      return _remember(p, uid, existingCode);
    }

    for (var i = 0; i < 8; i++) {
      final code = generateCode();
      try {
        await fs.createDoc('friendCodes', code, {'uid': uid});
        return _remember(p, uid, code);
      } on FirestoreException catch (e) {
        if (!e.alreadyExists) rethrow; // taken: try another
      }
    }
    throw FirestoreException('Could not find a free friend code');
  }

  String? _codeUid;

  Future<String> _remember(SharedPreferences p, String uid, String code) async {
    await p.setString(_kCode, code);
    await p.setString(_kCodeUid, uid);
    friendCode = code;
    _codeUid = uid;
    return code;
  }
}
