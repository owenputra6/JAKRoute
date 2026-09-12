import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../chat_history.dart';
import '../models.dart';
import '../route_steps.dart';
import '../user_prefs.dart';
import 'app_theme.dart';
import 'route_detail_screen.dart';
import 'widgets.dart';

enum _Role { user, assistant, system }

class _Entry {
  _Entry.text(this.role, this.text)
      : recommendation = null, catalog = null, at = DateTime.now();
  _Entry.result(this.recommendation, this.catalog)
      : role = _Role.assistant, text = null, at = DateTime.now();
  final _Role role;
  final String? text;
  final Recommendation? recommendation;
  final Json? catalog;
  final DateTime at;

  /// Round-trips through `chat_sessions.messages` (Supabase). The catalog
  /// snapshot isn't stored — it's re-attached from the live catalog on load.
  Json toJson() => {'role': role.name, 'text': text, 'recommendation': recommendation?.data, 'at': at.toIso8601String()};

  static _Entry fromJson(Json j, Json? catalog) {
    final rec = j['recommendation'];
    if (rec is Map) return _Entry.result(Recommendation(Map<String, dynamic>.from(rec)), catalog);
    final role = _Role.values.firstWhere((r) => r.name == j['role'], orElse: () => _Role.assistant);
    return _Entry.text(role, j['text'] as String? ?? '');
  }
}

/// Tanya AI (revised UI UX/tanya_ai_navigasi). Real AI chat: hits POST
/// /recommend-route per message. The agent's resolved parameters
/// (`intent.preferences`, `focus_mode`) are shown back to the user as a
/// parameter card — nothing displayed is invented; it is what the router
/// actually used. Route cards bind to `/recommend-route` route objects only.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.api,
    required this.mapStyleUrl,
    this.initialMessage,
    this.embedded = false,
    this.onAvatarTap,
  });

  final JakRouteApi api;
  final String mapStyleUrl;
  final String? initialMessage;
  /// True when hosted as a tab (no back button).
  final bool embedded;
  final VoidCallback? onAvatarTap;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _entries = <_Entry>[];
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Json? _catalog;
  String? _agentMode;
  bool _busy = false;
  // Last resolved intent from the backend. Threaded into every subsequent
  // request so the agent keeps origin/destination/preferences across turns
  // instead of re-asking the same clarification.
  Json _lastIntent = {};
  // Current Supabase chat_sessions row id; null until the first message of
  // a conversation is persisted (or when starting a fresh "Chat Baru").
  String? _sessionId;

  static const _quickPrompts = [
    ('Toilet terdekat', Icons.wc, 'Cepat ketemu fasilitas terdekat'),
    ('Musala di lantai 2', Icons.mosque, 'Lokasi & jalur ke musala'),
    ('Jalur ramah kursi roda ke peron', Icons.accessible, 'Rute step-free, tanpa tangga'),
    ('Lift ke Peron 1', Icons.elevator, 'Akses vertikal terdekat'),
  ];

  @override
  void initState() {
    super.initState();
    widget.api.catalog().then((c) => setState(() => _catalog = c)).catchError((_) {});
    widget.api.health().then((h) => setState(() => _agentMode = h['agent_mode']?.toString())).catchError((_) {});
    final initial = widget.initialMessage;
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(initial));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send(String message) async {
    final text = message.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _entries.add(_Entry.text(_Role.user, text));
      _busy = true;
    });
    _controller.clear();
    _scrollToEnd();
    try {
      final rec = await widget.api.recommend({
        'message': text,
        // Profile hard constraints (Profil tab) apply to every turn.
        'preferences': UserPrefs.instance.toRequest(),
        if (_lastIntent.isNotEmpty) 'conversation_context': {'intent': _lastIntent},
        if (_lastIntent['preferences'] is Map)
          'conversation_preferences': Map<String, dynamic>.from(_lastIntent['preferences'] as Map),
      });
      setState(() {
        if (rec.intent.isNotEmpty) _lastIntent = rec.intent;
        _entries.add(_Entry.result(rec, _catalog));
      });
    } on JakRouteApiException catch (e) {
      setState(() => _entries.add(_Entry.text(_Role.system, e.message)));
    } finally {
      setState(() => _busy = false);
      _scrollToEnd();
      unawaited(_persist());
    }
  }

  /// Best-effort save to Supabase (`chat_sessions`) — see chat_history.dart.
  /// Never blocks or surfaces errors into the chat; history is a bonus, not
  /// a requirement for the conversation to work.
  Future<void> _persist() async {
    if (_entries.isEmpty) return;
    final firstUser = _entries.firstWhere((e) => e.role == _Role.user, orElse: () => _entries.first);
    final rawTitle = (firstUser.text ?? 'Percakapan').trim();
    final title = rawTitle.length > 60 ? '${rawTitle.substring(0, 60)}…' : rawTitle;
    final id = await ChatHistoryStore.instance.save(
      sessionId: _sessionId,
      title: title.isEmpty ? 'Percakapan' : title,
      messages: _entries.map((e) => e.toJson()).toList(),
    );
    if (mounted) setState(() => _sessionId = id);
  }

  void _newChat() {
    setState(() {
      _entries.clear();
      _sessionId = null;
      _lastIntent = {};
    });
  }

  Future<void> _openHistory() async {
    final picked = await showModalBottomSheet<_HistoryPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HistorySheet(),
    );
    if (picked == null || !mounted) return;
    if (picked.newChat) {
      _newChat();
      return;
    }
    final id = picked.sessionId!;
    final raw = await ChatHistoryStore.instance.loadMessages(id);
    if (!mounted) return;
    setState(() {
      _sessionId = id;
      _entries
        ..clear()
        ..addAll(raw.map((j) => _Entry.fromJson(j, _catalog)));
      _lastIntent = {};
      for (final e in _entries.reversed) {
        if (e.recommendation?.intent.isNotEmpty ?? false) {
          _lastIntent = e.recommendation!.intent;
          break;
        }
      }
    });
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: BrandBar(
        context: 'Tanya AI',
        leading: widget.embedded ? null : const BackButton(),
        onAvatarTap: widget.onAvatarTap,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Riwayat percakapan',
            icon: const Icon(Icons.history, color: AppColors.secondary),
            onPressed: _openHistory,
          ),
          IconButton(
            tooltip: 'Chat baru',
            icon: const Icon(Icons.add_comment_outlined, color: AppColors.secondary),
            onPressed: _entries.isEmpty ? null : _newChat,
          ),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
              itemCount: (_entries.isEmpty ? 2 : _entries.length + 1) + (_busy ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) return _AssistantHeader(agentMode: _agentMode, ready: _catalog != null);
                if (_entries.isEmpty) {
                  return i == 1 ? _EmptyState(quickPrompts: _quickPrompts, onSend: _busy ? null : _send) : const _TypingBubble();
                }
                if (i == _entries.length + 1) return const _TypingBubble();
                return _EntryView(entry: _entries[i - 1], onSend: _send, mapStyleUrl: widget.mapStyleUrl);
              },
            ),
          ),
          if (_entries.isNotEmpty && _entries.last.role != _Role.assistant)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                children: [
                  for (final (label, icon, _) in _quickPrompts) ...[
                    Pill(label: label, icon: icon, onTap: _busy ? null : () => _send(label)),
                    const SizedBox(width: Space.xs),
                  ],
                ],
              ),
            ),
          _Composer(controller: _controller, busy: _busy, onSend: _send),
        ],
      ),
    );
  }
}

/// Navy status card. "Online" only once the catalog has actually loaded.
class _AssistantHeader extends StatelessWidget {
  const _AssistantHeader({required this.agentMode, required this.ready});
  final String? agentMode;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mode = switch (agentMode) { 'openai' => 'OpenAI agent', 'demo' => 'parser demo', null => '…', _ => agentMode! };
    return Container(
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF0B2E5C)]),
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: const [kRaisedShadow],
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: const Icon(Icons.auto_awesome, color: Colors.white),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Asisten Navigasi AI', style: t.headlineSmall?.copyWith(color: Colors.white)),
              const SizedBox(width: 6),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: ready ? AppColors.success : AppColors.warning, shape: BoxShape.circle)),
            ]),
            Text('$mode • solver A* Python • data Supabase Palmerah',
                style: t.labelSmall?.copyWith(color: Colors.white70)),
          ]),
        ),
        Tag(ready ? 'ONLINE' : 'MEMUAT', color: Colors.white.withValues(alpha: 0.14), fg: Colors.white),
      ]),
    );
  }
}

/// Shown only before the first message: quick-suggestion cards (real
/// pre-written prompts, not fabricated stats) plus a one-line tip.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.quickPrompts, required this.onSend});
  final List<(String, IconData, String)> quickPrompts;
  final ValueChanged<String>? onSend;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bolt, size: 16, color: AppColors.secondary),
          const SizedBox(width: 4),
          Text('REKOMENDASI PERTANYAAN', style: t.labelSmall?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        ]),
        const SizedBox(height: Space.xs),
        for (final (label, icon, subtitle) in quickPrompts) ...[
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
            onTap: onSend == null ? null : () => onSend!(label),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(Radii.std)),
                child: Icon(icon, size: 18, color: AppColors.secondary),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: t.labelMedium),
                  Text(subtitle, style: t.labelSmall?.copyWith(color: AppColors.slate)),
                ]),
              ),
              const Icon(Icons.arrow_forward, size: 16, color: AppColors.outline),
            ]),
          ),
          const SizedBox(height: Space.xs),
        ],
        SurfaceCard(
          padding: const EdgeInsets.all(Space.sm),
          color: AppColors.surfaceContainerLow,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.tips_and_updates_outlined, size: 18, color: AppColors.secondary),
            const SizedBox(width: Space.xs),
            Expanded(
              child: RichText(
                text: TextSpan(style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant), children: [
                  const TextSpan(text: 'Tip: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: 'sebutkan kondisi seperti bawa koper, kursi roda, atau mau ke tempat makan luar stasiun.'),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _HistoryPick {
  const _HistoryPick.session(this.sessionId) : newChat = false;
  const _HistoryPick.newChat() : sessionId = null, newChat = true;
  final String? sessionId;
  final bool newChat;
}

/// Riwayat Percakapan drawer (revised UI UX/tanya_ai_riwayat_chat_history):
/// past sessions grouped Hari ini / Sebelumnya, newest first.
class _HistorySheet extends StatefulWidget {
  const _HistorySheet();
  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  List<ChatSessionSummary>? _sessions;

  @override
  void initState() {
    super.initState();
    ChatHistoryStore.instance.listSessions().then((s) {
      if (mounted) setState(() => _sessions = s);
    });
  }

  Future<void> _delete(ChatSessionSummary s) async {
    setState(() => _sessions = _sessions!.where((x) => x.id != s.id).toList());
    await ChatHistoryStore.instance.deleteSession(s.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sessions = _sessions;
    final today = DateTime.now();
    bool isToday(DateTime d) => d.year == today.year && d.month == today.month && d.day == today.day;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
          boxShadow: [kRaisedShadow],
        ),
        child: Column(children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Row(children: [
              Expanded(child: Text('Riwayat Percakapan', style: t.headlineMedium)),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(const _HistoryPick.newChat()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Chat Baru'),
              ),
            ]),
          ),
          const SizedBox(height: Space.xs),
          Expanded(
            child: sessions == null
                ? const Center(child: CircularProgressIndicator())
                : sessions.isEmpty
                    ? Center(child: Text('Belum ada riwayat percakapan.', style: t.bodyMedium?.copyWith(color: AppColors.slate)))
                    : ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg),
                        children: [
                          for (final s in sessions)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.xs),
                              child: SurfaceCard(
                                padding: const EdgeInsets.all(Space.sm),
                                onTap: () => Navigator.of(context).pop(_HistoryPick.session(s.id)),
                                child: Row(children: [
                                  const Icon(Icons.chat_bubble_outline, color: AppColors.secondary),
                                  const SizedBox(width: Space.sm),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelMedium),
                                      Text(
                                        isToday(s.updatedAt)
                                            ? 'Hari ini • ${s.updatedAt.hour.toString().padLeft(2, '0')}:${s.updatedAt.minute.toString().padLeft(2, '0')}'
                                            : '${s.updatedAt.day}/${s.updatedAt.month}/${s.updatedAt.year}',
                                        style: t.labelSmall?.copyWith(color: AppColors.slate),
                                      ),
                                    ]),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.outline),
                                    onPressed: () => _delete(s),
                                  ),
                                ]),
                              ),
                            ),
                        ],
                      ),
          ),
        ]),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.busy, required this.onSend});
  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.sm),
        child: Container(
          padding: const EdgeInsets.fromLTRB(Space.md, 4, 4, 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: AppColors.hairline),
            boxShadow: const [kSurfaceShadow],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !busy,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: onSend,
                  decoration: const InputDecoration(
                    hintText: 'Ketik tujuan atau kebutuhan rute…',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: Space.sm),
                  ),
                ),
              ),
              const SizedBox(width: Space.xs),
              Material(
                color: busy ? AppColors.surfaceContainer : AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: busy ? null : () => onSend(controller.text),
                  child: const SizedBox(width: 44, height: 44, child: Icon(Icons.send, color: Colors.white, size: 20)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    return _AssistantRow(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: Space.xs),
          Text('Menghitung rute…', style: TextStyle(color: AppColors.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text, required this.at});
  final String text;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm, left: Space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(Radii.lg).copyWith(bottomRight: const Radius.circular(4)),
          ),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
        ),
        const SizedBox(height: 2),
        Text(_clock(at), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.slateLight)),
      ]),
    );
  }
}

/// Robot avatar + white card, used for every assistant message.
class _AssistantRow extends StatelessWidget {
  const _AssistantRow({required this.child, this.at});
  final Widget child;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm, right: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(radius: 16, backgroundColor: AppColors.primary, child: Icon(Icons.smart_toy_outlined, color: Colors.white, size: 18)),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(Radii.lg).copyWith(topLeft: const Radius.circular(4)),
                border: Border.all(color: AppColors.hairline),
                boxShadow: const [kSurfaceShadow],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (at != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Text('JAKRoute', style: t.labelMedium),
                      const SizedBox(width: 6),
                      const Tag('A* solver', color: AppColors.accentLight, fg: AppColors.secondary),
                      const Spacer(),
                      Text(_clock(at!), style: t.labelSmall?.copyWith(color: AppColors.slateLight)),
                    ]),
                  ),
                child,
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryView extends StatelessWidget {
  const _EntryView({required this.entry, required this.onSend, required this.mapStyleUrl});
  final _Entry entry;
  final ValueChanged<String> onSend;
  final String mapStyleUrl;

  @override
  Widget build(BuildContext context) {
    if (entry.text != null) {
      if (entry.role == _Role.user) return _UserBubble(text: entry.text!, at: entry.at);
      return _AssistantRow(child: Text(entry.text!, style: const TextStyle(color: AppColors.danger)));
    }
    final rec = entry.recommendation!;
    if (rec.status == 'clarification_required') {
      return _ClarificationView(rec: rec, catalog: entry.catalog, onSend: onSend, at: entry.at);
    }
    if (rec.status != 'ok' || rec.routes.isEmpty) {
      return _AssistantRow(at: entry.at, child: Text(rec.question ?? 'Rute tidak ditemukan untuk kondisi saat ini.'));
    }
    return _ResultView(rec: rec, catalog: entry.catalog, mapStyleUrl: mapStyleUrl, at: entry.at);
  }
}

/// Parameter card: exactly what the backend resolved for this turn.
class _ParamCard extends StatelessWidget {
  const _ParamCard({required this.intent});
  final Json intent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final prefs = (intent['preferences'] as Map?) ?? {};
    final focus = switch (intent['focus_mode']) { 'fastest' => 'Paling cepat', 'min_walk' => 'Minim jalan kaki', _ => 'Paling sesuai (seimbang)' };
    final access = switch (prefs['preferred_access']) { 'elevator' => 'Lift', 'escalator' => 'Eskalator', 'stairs' => 'Tangga', _ => 'Otomatis' };
    Widget row(IconData icon, String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 16, color: AppColors.secondary),
            const SizedBox(width: Space.xs),
            Text(k, style: t.bodyMedium?.copyWith(fontSize: 14, color: AppColors.slate)),
            const Spacer(),
            Text(v, style: t.labelMedium?.copyWith(color: color ?? AppColors.onSurface)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: Space.xs),
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(children: [
        row(Icons.block, 'Hindari tangga', prefs['avoid_stairs'] == true ? 'Aktif' : 'Tidak', color: prefs['avoid_stairs'] == true ? AppColors.secondary : null),
        row(Icons.accessible, 'Bebas anak tangga', prefs['step_free'] == true ? 'Aktif (lift)' : 'Tidak', color: prefs['step_free'] == true ? AppColors.secondary : null),
        row(Icons.tune, 'Prioritas', focus),
        row(Icons.elevator_outlined, 'Akses antarlantai', access),
        if (prefs['max_walk_m'] != null) row(Icons.straighten, 'Batas jalan kaki', '${prefs['max_walk_m']} m'),
      ]),
    );
  }
}

class _ClarificationView extends StatelessWidget {
  const _ClarificationView({required this.rec, required this.catalog, required this.onSend, required this.at});
  final Recommendation rec;
  final Json? catalog;
  final ValueChanged<String> onSend;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    // Same-named access points exist on both floors (e.g. "Lift Peron 1" on
    // LT 1 and LT 2), so the chip must carry the floor for the agent.
    final places = ((catalog?['places'] as List?) ?? [])
        .cast<Map>()
        .where((p) => p['label'] != null && (p['node_type'] == 'entrance_access' || p['kind'] == 'elevator' || p['kind'] == 'stairs'))
        .map((p) => '${p['label']} (Lantai ${p['floor']})')
        .take(10)
        .toList();
    return _AssistantRow(
      at: at,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rec.question ?? 'Bisa perjelas lokasimu?'),
          if (places.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text('Pilih titik awal:', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.slate)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final label in places) Pill(label: label, onTap: () => onSend('Saya di $label.')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.rec, required this.catalog, required this.mapStyleUrl, required this.at});
  final Recommendation rec;
  final Json? catalog;
  final String mapStyleUrl;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final insight = rec.aiInsight;
    final insightText = insight['summary']?.toString() ?? insight['explanation']?.toString();
    final routes = rec.routes.where((r) => r.available).toList();
    // Selected first, then the alternatives.
    routes.sort((a, b) => (a.id == rec.selectedId ? 0 : 1) - (b.id == rec.selectedId ? 0 : 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AssistantRow(
          at: at,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(insightText != null && insightText.isNotEmpty
                ? insightText
                : 'Parameter rute sudah disesuaikan. Ini alternatif yang memenuhi batasanmu:'),
            _ParamCard(intent: rec.intent),
            if (routesIdentical(routes))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(kIdenticalRoutesNote, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.slate)),
              ),
          ]),
        ),
        for (final route in routes)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm, left: 40),
            child: _RouteCard(
              route: route,
              selected: route.id == rec.selectedId,
              catalog: catalog,
              mapStyleUrl: mapStyleUrl,
            ),
          ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.selected, required this.catalog, required this.mapStyleUrl});
  final RouteOption route;
  final bool selected;
  final Json? catalog;
  final String mapStyleUrl;

  static const _labels = {'best_fit': 'Paling Sesuai', 'fastest': 'Paling Cepat', 'min_walk': 'Minim Jalan Kaki'};
  static const _icons = {'best_fit': Icons.auto_awesome, 'fastest': Icons.bolt, 'min_walk': Icons.directions_walk};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final connectors = {for (final c in (catalog?['connectors'] as List? ?? []).cast<Map>()) c['id']: c};
    final used = (route.data['connectors_used'] as List? ?? []).cast<String>().map((id) => connectors[id]).whereType<Map>().toList();
    final via = used.map((c) => c['label']).join(', ');
    final floorChanges = used.length;
    final usesStairs = used.any((c) => c['kind'] == 'stairs');
    final steps = catalog == null ? const <String>[] : routeSteps(route, catalog!);
    final minutes = route.durationSeconds / 60;

    return SurfaceCard(
      padding: const EdgeInsets.all(Space.sm),
      border: selected ? AppColors.secondary : null,
      elevated: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: selected ? AppColors.secondary : AppColors.accentLight, borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(_icons[route.mode] ?? Icons.route, color: selected ? Colors.white : AppColors.secondary),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 2),
                    child: Tag('Rekomendasi Utama', color: Color(0xFFDCFCE7), fg: Color(0xFF166534)),
                  ),
                Text(_labels[route.mode] ?? route.label, style: t.headlineSmall?.copyWith(fontSize: 18)),
                Text(via.isEmpty ? 'Tanpa pindah lantai' : 'via $via',
                    style: t.labelSmall?.copyWith(color: AppColors.slate), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          const SizedBox(height: Space.sm),
          Row(children: [
            Expanded(child: StatBox(label: 'Estimasi', value: '~${minutes < 1 ? '<1' : minutes.toStringAsFixed(minutes < 10 ? 1 : 0)} mnt')),
            const SizedBox(width: Space.xs),
            Expanded(child: StatBox(label: 'Jarak', value: '${route.walkingMeters.round()} m')),
            const SizedBox(width: Space.xs),
            Expanded(
              child: StatBox(
                label: 'Tangga',
                value: usesStairs ? 'Ya' : (floorChanges == 0 ? '0' : '0 (${used.first['kind'] == 'elevator' ? 'lift' : 'eskalator'})'),
                valueColor: usesStairs ? AppColors.warning : AppColors.success,
              ),
            ),
          ]),
          if (route.explanation.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(route.explanation, style: t.labelSmall?.copyWith(color: AppColors.slate, fontWeight: FontWeight.w400)),
          ],
          if (steps.length > 1) ...[
            const SizedBox(height: Space.xs),
            for (final (i, s) in steps.skip(1).take(3).indexed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: AppColors.accentLight,
                    child: Text('${i + 1}', style: t.labelSmall?.copyWith(color: AppColors.secondary, fontSize: 10)),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(child: Text(s, style: t.bodyMedium?.copyWith(fontSize: 13))),
                ]),
              ),
          ],
          for (final w in route.warnings)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber, size: 14, color: AppColors.warning),
                const SizedBox(width: 4),
                Expanded(child: Text(w, style: const TextStyle(fontSize: 11, color: AppColors.warning))),
              ]),
            ),
          const SizedBox(height: Space.sm),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              backgroundColor: selected ? AppColors.secondary : AppColors.surfaceContainer,
              foregroundColor: selected ? Colors.white : AppColors.primary,
            ),
            onPressed: catalog == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RouteDetailScreen(route: route, catalog: catalog!, mapStyleUrl: mapStyleUrl),
                    )),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(selected ? 'Pilih Rute Ini & Buka Peta' : 'Lihat di peta'),
          ),
        ],
      ),
    );
  }
}
