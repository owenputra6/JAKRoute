import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import 'app_theme.dart';
import 'route_detail_screen.dart';

enum _Role { user, assistant, system }

class _Entry {
  _Entry.text(this.role, this.text)
      : recommendation = null, catalog = null;
  _Entry.result(this.recommendation, this.catalog)
      : role = _Role.assistant, text = null;
  final _Role role;
  final String? text;
  final Recommendation? recommendation;
  final Json? catalog;
}

/// Real AI chat: hits POST /recommend-route per message, renders a "typing"
/// indicator while the agent (OpenAI Responses, backend-validated) resolves
/// intent, then renders context-aware widgets inline — not plain bubbles:
/// clarification -> tappable place chips, ok -> tappable route cards that
/// open the map/diagram for that specific route.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.api, required this.mapStyleUrl, this.initialMessage});

  final JakRouteApi api;
  final String mapStyleUrl;
  final String? initialMessage;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _entries = <_Entry>[];
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Json? _catalog;
  bool _busy = false;
  // Last resolved intent from the backend. Threaded into every subsequent
  // request so the agent keeps origin/destination/preferences across turns
  // instead of re-asking the same clarification.
  Json _lastIntent = {};

  @override
  void initState() {
    super.initState();
    _entries.add(_Entry.text(_Role.system,
        'Ceritakan kebutuhanmu — misalnya "saya bawa stroller, mau ke toilet, hindari tangga".'));
    widget.api.catalog().then((c) => setState(() => _catalog = c)).catchError((_) {});
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asisten JAKRoute'),
        backgroundColor: AppColors.surfaceContainerLowest,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(Space.md),
              itemCount: _entries.length + (_busy ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _entries.length) return const _TypingBubble();
                return _EntryView(entry: _entries[i], onSend: _send, mapStyleUrl: widget.mapStyleUrl);
              },
            ),
          ),
          _Composer(controller: _controller, busy: _busy, onSend: _send),
        ],
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
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !busy,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                decoration: InputDecoration(
                  hintText: 'Tulis kebutuhan perjalananmu…',
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.full),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
                ),
              ),
            ),
            const SizedBox(width: Space.xs),
            IconButton.filled(
              onPressed: busy ? null : () => onSend(controller.text),
              icon: const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    return _BubbleShell(
      role: _Role.assistant,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: Space.xs),
          Text('AI sedang mengetik…', style: TextStyle(color: AppColors.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _BubbleShell extends StatelessWidget {
  const _BubbleShell({required this.role, required this.child});
  final _Role role;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isUser = role == _Role.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.only(bottom: Space.sm),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(
          color: isUser ? AppColors.secondary : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(Radii.lg).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: !isUser ? const Radius.circular(4) : null,
          ),
          boxShadow: isUser ? null : const [kSurfaceShadow],
        ),
        child: DefaultTextStyle(
          style: TextStyle(color: isUser ? Colors.white : AppColors.onSurface),
          child: child,
        ),
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
      return _BubbleShell(role: entry.role, child: Text(entry.text!));
    }
    final rec = entry.recommendation!;
    if (rec.status == 'clarification_required') {
      return _ClarificationView(rec: rec, catalog: entry.catalog, onSend: onSend);
    }
    if (rec.status != 'ok' || rec.routes.isEmpty) {
      return _BubbleShell(
        role: _Role.assistant,
        child: Text(rec.question ?? 'Rute tidak ditemukan untuk kondisi saat ini.'),
      );
    }
    return _ResultView(rec: rec, catalog: entry.catalog, mapStyleUrl: mapStyleUrl);
  }
}

class _ClarificationView extends StatelessWidget {
  const _ClarificationView({required this.rec, required this.catalog, required this.onSend});
  final Recommendation rec;
  final Json? catalog;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    // Same-named access points exist on both floors (e.g. "Lift Peron 1" on
    // LT 1 and LT 2), so the chip must carry the floor for the agent.
    final places = ((catalog?['places'] as List?) ?? [])
        .cast<Map>()
        .where((p) => p['label'] != null)
        .map((p) => '${p['label']} (Lantai ${p['floor']})')
        .take(10)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BubbleShell(role: _Role.assistant, child: Text(rec.question ?? 'Bisa perjelas lokasimu?')),
        if (places.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final label in places)
                  ActionChip(
                    label: Text(label),
                    backgroundColor: AppColors.surfaceContainer,
                    onPressed: () => onSend('Saya di $label.'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.rec, required this.catalog, required this.mapStyleUrl});
  final Recommendation rec;
  final Json? catalog;
  final String mapStyleUrl;

  @override
  Widget build(BuildContext context) {
    final insight = rec.aiInsight;
    final insightText = insight['summary']?.toString() ?? insight['explanation']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insightText != null && insightText.isNotEmpty)
          _BubbleShell(
            role: _Role.assistant,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
                const SizedBox(width: Space.xs),
                Flexible(child: Text(insightText)),
              ],
            ),
          )
        else
          const _BubbleShell(role: _Role.assistant, child: Text('Ini tiga alternatif rute yang cocok:')),
        for (final route in rec.routes.where((r) => r.available))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: selected ? AppColors.secondary : AppColors.hairline, width: selected ? 1.5 : 1),
        boxShadow: const [kSurfaceShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route, size: 18, color: AppColors.secondary),
              const SizedBox(width: Space.xs),
              Text(_labels[route.mode] ?? route.mode, style: Theme.of(context).textTheme.labelMedium),
              if (selected) ...[
                const SizedBox(width: Space.xs),
                const Icon(Icons.check_circle, size: 14, color: AppColors.success),
              ],
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${route.walkingMeters.round()} m · ${(route.durationSeconds / 60).toStringAsFixed(1)} menit · crowd ${route.crowdExposure.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (route.explanation.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(route.explanation, style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13)),
          ],
          for (final w in route.warnings)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 14, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Expanded(child: Text(w, style: const TextStyle(fontSize: 12, color: AppColors.warning))),
                ],
              ),
            ),
          const SizedBox(height: Space.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: catalog == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => RouteDetailScreen(route: route, catalog: catalog!, mapStyleUrl: mapStyleUrl),
                      )),
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Lihat di peta'),
            ),
          ),
        ],
      ),
    );
  }
}
