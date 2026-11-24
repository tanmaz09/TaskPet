import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../account_service.dart';
import '../auth_service.dart';
import '../firebase_config.dart';
import '../firestore_client.dart';
import '../friends_service.dart';
import '../leaderboard.dart';
import '../models.dart';
import '../sync_service.dart';
import 'creature_painter.dart';

class FriendsPage extends StatefulWidget {
  final GameState state;

  /// True while this tab is showing, so it can refresh when you open it.
  final bool active;
  const FriendsPage({super.key, required this.state, required this.active});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _service = FriendsService.instance;
  final _codeCtrl = TextEditingController();

  List<FriendEntry> _entries = [];
  bool _loading = false;
  bool _sending = false;
  bool _deleting = false;
  String? _error;
  DateTime? _lastLoad;
  String _name = 'Trainer';

  @override
  void initState() {
    super.initState();
    SyncService.instance.displayName().then((n) {
      if (mounted) setState(() => _name = n);
    });
    if (widget.active) _refreshIfStale();
  }

  @override
  void didUpdateWidget(FriendsPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _refreshIfStale();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _refreshIfStale() {
    if (!FirebaseConfig.isConfigured || !SyncService.instance.enabled.value) {
      return;
    }
    // Make sure the profile and friend code exist.
    if (SyncService.instance.friendCode == null) {
      unawaited(SyncService.instance.pushIfChanged(force: true));
    }
    final last = _lastLoad;
    if (last == null ||
        DateTime.now().difference(last) > const Duration(seconds: 20)) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!FirebaseConfig.isConfigured ||
        !SyncService.instance.enabled.value ||
        _loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.load();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _lastLoad = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object e) {
    if (e is AuthException && e.network) return "You're offline. Pull down to try again.";
    if (e is FirestoreException) {
      if (e.network) return "You're offline. Pull down to try again.";
      if (e.denied) {
        return 'The server said no. Check that the Firestore rules from the setup steps are published.';
      }
    }
    return 'Something went wrong. Pull down to try again.';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs a friends action, shows a message, then refreshes the list.
  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      if (!mounted) return;
      if (done != null) _toast(done);
      await _load();
    } catch (e) {
      if (mounted) _toast(_friendlyError(e));
    }
  }

  // ------------------------------------------------------------ actions

  Future<void> _send() async {
    final raw = _codeCtrl.text;
    if (raw.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final result = await _service.sendRequest(raw);
      if (!mounted) return;
      _toast(switch (result) {
        SendResult.sent => 'Request sent ✅',
        SendResult.nowFriends => "You're now friends! 🎉",
        SendResult.alreadyFriends => "You're already friends.",
        SendResult.alreadySent => 'You already sent them a request.',
        SendResult.notFound => 'No one has that code.',
        SendResult.selfCode => "That's your own code.",
        SendResult.invalidCode => 'Codes have 6 letters or numbers.',
      });
      if (result == SendResult.sent || result == SendResult.nowFriends) {
        _codeCtrl.clear();
        await _load();
      }
    } catch (e) {
      if (mounted) _toast(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
              helperText: 'Friends see this next to your pet'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    await SyncService.instance.setDisplayName(result);
    final n = await SyncService.instance.displayName();
    if (mounted) setState(() => _name = n);
  }

  Future<void> _confirmRemove(FriendEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${e.displayName}?'),
        content: const Text(
            "You won't see each other's pets any more. You can add each other again with a code."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _run(() => _service.remove(e.uid));
  }

  void _openFriend(FriendEntry e) {
    final p = e.profile;
    if (p == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FriendSheet(profile: p),
    );
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
        return ValueListenableBuilder<bool>(
      valueListenable: SyncService.instance.enabled,
      builder: (context, on, _) =>
          (on || !FirebaseConfig.isConfigured) ? _onlineBody() : _offBody(),
    );
  }

    /// Shown until the user opts in, and again after the online profile is
  /// deleted.
  Widget _offBody() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👫', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            const Text(
              'Play with friends',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Online features are optional and off by default. Turn them on '
              'to get a friend code, see your friends\' pets and compete on a '
              'weekly leaderboard.\n\n'
              'Friends you accept can see your name and your pet\'s stats '
              '(stage, energy, streak, perfect days). Your tasks never leave '
              'this phone. You can delete your online profile any time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                await SyncService.instance.turnOn();
                if (mounted) {
                  setState(() {
                    _entries = [];
                    _lastLoad = null;
                  });
                  _refreshIfStale();
                }
              },
              child: const Text('Turn on online features'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _onlineBody() {
    if (!FirebaseConfig.isConfigured) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            "🌐 Online features aren't set up yet.\n\nOnce the Firebase keys are added, you'll be able to add friends and see their pets here.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    final incoming =
        _entries.where((e) => e.status == FriendStatus.incoming).toList();
    final friends =
        _entries.where((e) => e.status == FriendStatus.friend).toList();
    final outgoing =
        _entries.where((e) => e.status == FriendStatus.outgoing).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _myCodeCard(),
          const SizedBox(height: 12),
          _addCard(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
          if (incoming.isNotEmpty) ...[
            _sectionTitle('Friend requests'),
            for (final e in incoming) _incomingCard(e),
          ],
          if (friends.isNotEmpty) ...[
            _sectionTitle('Leaderboard'),
            _leaderboardCard(friends),
          ],
          _sectionTitle('Friends'),
          if (friends.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _loading
                    ? 'Loading…'
                    : 'No friends yet. Share your code, or type theirs above.',
                style: const TextStyle(color: Colors.grey),
              ),
            )
          else
            for (final e in friends) _friendCard(e),
          if (outgoing.isNotEmpty) ...[
            _sectionTitle('Waiting for a reply'),
            for (final e in outgoing) _outgoingCard(e),
          ],
          _sectionTitle('Online profile'),
          _privacyCard(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _privacyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Friends you accept can see your name and your pet's stats. Your tasks never leave this phone.",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _deleting ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline),
              label: Text(_deleting ? 'Deleting…' : 'Delete my online profile'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your online profile?'),
        content: const Text(
          'This removes your friend code, your pet snapshot and all your '
          'friendships from the server. Friends will no longer see you.\n\n'
          'Your tasks and progress on this phone are NOT deleted. You can '
          'turn online features back on later with a new code.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _deleting = true);
    try {
      await AccountService.instance.deleteOnlineProfile();
      if (!mounted) return;
      setState(() {
        _entries = [];
        _lastLoad = null;
      });
      _toast('Online profile deleted');
    } catch (e) {
      if (mounted) {
        _toast("Couldn't finish deleting. Check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  Widget _myCodeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<SyncState>(
          valueListenable: SyncService.instance.status,
          builder: (context, state, _) {
            final code = SyncService.instance.friendCode;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      tooltip: 'Change name',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: _editName,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Your friend code',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 4),
                if (code != null)
                  Row(
                    children: [
                      Text(code,
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4)),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          _toast('Code copied');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          switch (state) {
                            SyncState.offline =>
                              "You're offline. Your code appears once you're back online.",
                            SyncState.error =>
                              "Couldn't set up your profile: ${SyncService.instance.lastError ?? 'unknown error'}",
                            _ => 'Setting up your profile…',
                          },
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      if (state == SyncState.error || state == SyncState.offline)
                        TextButton(
                          onPressed: () => SyncService.instance
                              .pushIfChanged(force: true),
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _addCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  labelText: "Friend's code",
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(_sending ? '…' : 'Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leaderboardCard(List<FriendEntry> friends) {
    final monday = FriendsService.currentMonday();
    final rows = rankLeaderboard([
      LeaderboardRow(
        uid: 'me',
        name: _name,
        stage: GameState.stages.indexOf(widget.state.stage),
        week: rankedThisWeek(widget.state),
        streak: widget.state.streak,
        isMe: true,
      ),
      for (final e in friends)
        if (e.profile != null)
          LeaderboardRow(
            uid: e.uid,
            name: e.profile!.name,
            stage: e.profile!.stage,
            week: e.profile!.effectiveWeekPerfect(monday),
            streak: e.profile!.streak,
          ),
    ]);
    final anyScore = rows.any((r) => r.week > 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🏆 This week',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Perfect days with 3+ effort points (Easy 1, Medium 2, Hard 3). Resets every Monday.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (!anyScore)
              const Text('No perfect days yet this week. Be the first! 🌱')
            else
              for (final r in rows) _leaderboardRow(r),
          ],
        ),
      ),
    );
  }

  Widget _leaderboardRow(LeaderboardRow r) {
    final medal = switch (r.rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      null => '–',
      _ => '${r.rank}',
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: r.isMe ? Colors.teal.withOpacity(0.15) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(medal, style: const TextStyle(fontSize: 18)),
          ),
          Text(GameState.stages[r.stage.clamp(0, 4)].emoji,
              style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.isMe ? '${r.name} (you)' : r.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: r.isMe ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          Text('${r.week}/7',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _incomingCard(FriendEntry e) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${e.displayName} wants to be friends',
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _run(() => _service.remove(e.uid)),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _run(() => _service.accept(e.uid),
                      done: 'You and ${e.displayName} are friends 🎉'),
                  child: const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _outgoingCard(FriendEntry e) {
    return Card(
      child: ListTile(
        title: Text('Waiting for ${e.code ?? 'a reply'}'),
        trailing: TextButton(
          onPressed: () => _run(() => _service.remove(e.uid)),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _friendCard(FriendEntry e) {
    final p = e.profile;
    final now = DateTime.now();
    final hour = now.hour + now.minute / 60.0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: p == null ? null : () => _openFriend(e),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: p == null
                      ? const Center(
                          child: Text('🥚', style: TextStyle(fontSize: 36)))
                      : CustomPaint(
                          painter: CreaturePainter(
                            stage: p.stage,
                            energy: p.energy,
                            t: 0.1,
                            hour: hour,
                            golden: p.feast,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: p == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.displayName,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text("Hasn't synced their pet yet",
                              style: TextStyle(color: Colors.grey)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${GameState.stages[p.stage].emoji} ${p.name}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                              '🔥 ${p.streak} streak · ${p.effectiveWeekPerfect(FriendsService.currentMonday())}/7 this week'),
                          const SizedBox(height: 2),
                          Text(_todayLine(p),
                              style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(_ago(p.updatedAt),
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ],
                      ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'remove') _confirmRemove(e);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'remove', child: Text('Remove friend')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _todayLine(FriendProfile p) {
    if (p.restToday) return '🌙 Resting today';
    if (p.totalToday == 0) return 'No tasks yet';
    return 'Today: ${p.doneToday}/${p.totalToday}';
  }

  static String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 2) return 'Active just now';
    if (d.inHours < 1) return 'Active ${d.inMinutes} min ago';
    if (d.inDays < 1) return 'Active ${d.inHours} h ago';
    return 'Active ${d.inDays} d ago';
  }
}

/// Bigger, animated view of a friend's pet with their stats.
class _FriendSheet extends StatefulWidget {
  final FriendProfile profile;
  const _FriendSheet({required this.profile});

  @override
  State<_FriendSheet> createState() => _FriendSheetState();
}

class _FriendSheetState extends State<_FriendSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.of(context).disableAnimations && !_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final stage = GameState.stages[p.stage];
    final now = DateTime.now();
    final hour = now.hour + now.minute / 60.0;
    final week = p.effectiveWeekPerfect(FriendsService.currentMonday());

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 240,
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => CustomPaint(
                    painter: CreaturePainter(
                      stage: p.stage,
                      energy: p.energy,
                      t: _c.value,
                      hour: hour,
                      golden: p.feast,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text('${stage.emoji} ${p.name}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            Center(
              child: Text(stage.name,
                  style: const TextStyle(color: Colors.grey)),
            ),
            const SizedBox(height: 14),
            Text('Energy ${p.energy}/100'),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: p.energy / 100,
              color: p.energy < 25 ? Colors.red : Colors.teal,
            ),
            const SizedBox(height: 14),
            Text('🔥 Streak: ${p.streak} (best ${p.longestStreak})'),
            const SizedBox(height: 4),
            Text('🏆 Perfect days: ${p.totalPerfectDays}'),
            const SizedBox(height: 4),
            Text('⚔️ This week: $week/7 perfect days'),
            const SizedBox(height: 4),
            if (p.perfectWeeks > 0) ...[
              Text('🌟 Perfect weeks: ${p.perfectWeeks}'),
              const SizedBox(height: 4),
            ],
            Text(p.restToday
                ? '🌙 Resting today'
                : (p.totalToday == 0
                    ? 'No tasks yet today'
                    : '✅ Today: ${p.doneToday}/${p.totalToday} done')),
            if (p.feast) ...[
              const SizedBox(height: 4),
              const Text('🌟 Golden feast: glowing!'),
            ],
          ],
        ),
      ),
    );
  }
}
