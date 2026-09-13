import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'models.dart';
import 'station_map.dart';
import 'route_steps.dart';
import 'ui/app_theme.dart';
import 'ui/kinds.dart';
import 'ui/route_detail_screen.dart';
import 'ui/widgets.dart';
import 'user_prefs.dart';

/// Route planner (revised UI UX/pilihan_rute_stasiun_palmerah): origin /
/// destination header with swap, preference pills, hero floor plan with the
/// selected route, "Pilihan Rute Stasiun" cards, AI insight, and
/// Mulai Navigasi / Langkah actions. Every number is a `/recommend-route`
/// field; connector chips come from the real `connectors_used` list.
class JakRouteScreen extends StatefulWidget {
  final JakRouteApi api;
  final String mapStyleUrl;
  final String? initialDestinationId;
  const JakRouteScreen({super.key, required this.api, this.mapStyleUrl = '', this.initialDestinationId});
  @override
  State<JakRouteScreen> createState() => _JakRouteScreenState();
}

class _JakRouteScreenState extends State<JakRouteScreen> {
  final _message = TextEditingController();
  final _walkLimit = TextEditingController();
  Json? _catalog;
  CrowdSnapshot? _crowd;
  Recommendation? _recommendation;
  RouteOption? _selected;
  String? _error;
  bool _loading = true, _busy = false, _advanced = false;
  bool _avoidStairs = UserPrefs.instance.avoidStairs, _stepFree = UserPrefs.instance.stepFree;
  String _origin = '', _destination = '', _access = UserPrefs.instance.stepFree ? 'elevator' : 'any', _focus = 'best_fit';
  int _floor = 0, _requestGeneration = 0;
  double _timeWeight = 1, _walkWeight = 1, _crowdWeight = 1;
  bool _prioritiesChanged = false;
  final Set<String> _via = {};
  Timer? _busyTicker;
  int _busyPhase = 0;
  // Mirrors the real backend pipeline (ai_agent.parse_user_request ->
  // execute_jobs x3 modes -> explain), so the wait reads as "here's what's
  // actually happening" instead of a fake percentage.
  static const _busyMessages = [
    'AI memahami permintaanmu…',
    'Menghitung tiga alternatif rute…',
    'Menyusun penjelasan terbaik…',
  ];

  @override
  void initState() {
    super.initState();
    _walkLimit.text = UserPrefs.instance.maxWalkM?.round().toString() ?? '';
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final loaded = await Future.wait([widget.api.catalog(), widget.api.crowdSnapshot()]);
      final catalog = loaded[0] as Json;
      final crowd = loaded[1] as CrowdSnapshot;
      if (!mounted) return;
      final places = (catalog['places'] as List).cast<Map>();
      final ids = places.map((p) => p['id'] as String).toSet();
      setState(() {
        _catalog = catalog;
        _crowd = crowd;
        // Defaults: the west entrance (hall) -> the accessible toilet door.
        if (!ids.contains(_origin)) {
          _origin = ids.contains('palmerah_lt2_node_009') ? 'palmerah_lt2_node_009' : places.first['id'] as String;
        }
        final wanted = widget.initialDestinationId;
        if (wanted != null && ids.contains(wanted)) {
          _destination = wanted;
        } else if (!ids.contains(_destination)) {
          _destination = ids.contains('palmerah_lt2_node_015') ? 'palmerah_lt2_node_015' : '';
        }
        _floor = ((catalog['floors'] as List).last as Map)['id'] as int;
      });
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _recommend() async {
    final limitText = _walkLimit.text.trim();
    final limit = limitText.isEmpty ? null : double.tryParse(limitText);
    if (limitText.isNotEmpty && (limit == null || limit < 0)) {
      setState(() => _error = 'Isi batas berjalan dengan angka meter yang valid.');
      return;
    }
    final generation = ++_requestGeneration;
    setState(() { _busy = true; _busyPhase = 0; _error = null; _recommendation = null; _selected = null; });
    _busyTicker?.cancel();
    _busyTicker = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (!mounted || _busyPhase >= _busyMessages.length - 1) return;
      setState(() => _busyPhase++);
    });
    try {
      final result = await widget.api.recommend({
        'message': _message.text,
        'origin_id': _origin,
        'destination_id': _destination.isEmpty ? null : _destination,
        'via_indoor_ids': _via.toList(),
        'focus_mode': _focus,
        'preferences': {
          'avoid_stairs': _avoidStairs,
          'step_free': _stepFree,
          if (_access != 'any') 'preferred_access': _access,
          if (_prioritiesChanged) 'time_priority': _timeWeight,
          if (_prioritiesChanged) 'walking_priority': _walkWeight,
          if (_prioritiesChanged) 'crowd_priority': _crowdWeight,
          'max_walk_m': limit,
        },
      });
      if (!mounted || generation != _requestGeneration) return;
      final available = result.routes.where((r) => r.available).toList();
      setState(() {
        _recommendation = result;
        _selected = available.isEmpty ? null : available.firstWhere((r) => r.id == result.selectedId, orElse: () => available.first);
        final floors = _selected == null ? const <int>[] : routeFloors(_selected!);
        if (floors.isNotEmpty) _floor = floors.first;
      });
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally {
      _busyTicker?.cancel();
      if (mounted && generation == _requestGeneration) setState(() => _busy = false);
    }
  }

  @override
  void dispose() { _message.dispose(); _walkLimit.dispose(); _busyTicker?.cancel(); super.dispose(); }

  Map? _place(String id) {
    final places = (_catalog!['places'] as List).cast<Map>();
    final match = places.where((p) => p['id'] == id);
    return match.isEmpty ? null : match.first;
  }

  Future<void> _pickPlace({required bool origin}) async {
    final places = (_catalog!['places'] as List).cast<Map>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      builder: (ctx) => _PlacePicker(places: places, catalog: _catalog!, allowAuto: !origin),
    );
    if (picked == null) return;
    setState(() { if (origin) { _origin = picked; } else { _destination = picked; } });
  }

  void _openDetail() {
    if (_selected == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RouteDetailScreen(route: _selected!, catalog: _catalog!, mapStyleUrl: widget.mapStyleUrl),
    ));
  }

  void _showSteps() {
    if (_selected == null) return;
    final steps = routeSteps(_selected!, _catalog!);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SheetHandle(),
          Text('Langkah perjalanan', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: Space.sm),
          for (final (i, s) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 12, backgroundColor: AppColors.secondary, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11))),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(s)),
              ]),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const BrandBar(context: 'Perencana Rute', leading: BackButton()),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _catalog == null
              ? Center(child: Padding(padding: const EdgeInsets.all(Space.lg), child: Text(_error ?? 'Gagal memuat.', style: const TextStyle(color: AppColors.danger))))
              : _buildBody(context, t),
    );
  }

  Widget _buildBody(BuildContext context, TextTheme t) {
    final catalog = _catalog!;
    final floors = (catalog['floors'] as List).cast<Map>();
    final routes = _recommendation?.routes.where((r) => r.available).toList() ?? const <RouteOption>[];
    final insight = _recommendation?.aiInsight;
    final insightText = insight?['summary']?.toString() ?? insight?['explanation']?.toString();
    final origin = _place(_origin), dest = _destination.isEmpty ? null : _place(_destination);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xl),
      children: [
        // Origin / destination header card.
        SurfaceCard(
          padding: const EdgeInsets.all(Space.sm),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Column(children: [
                  _PlaceField(
                    label: 'TITIK ASAL',
                    icon: Icons.trip_origin,
                    iconColor: AppColors.secondary,
                    value: origin == null ? 'Pilih titik awal' : '${origin['label']} • ${floorShort(origin['floor'])}',
                    onTap: _busy ? null : () => _pickPlace(origin: true),
                  ),
                  const SizedBox(height: Space.xs),
                  _PlaceField(
                    label: 'TUJUAN',
                    icon: Icons.place,
                    iconColor: AppColors.danger,
                    value: dest == null ? 'Dari pesan saya (AI menafsirkan)' : '${dest['label']} • ${floorShort(dest['floor'])}',
                    onTap: _busy ? null : () => _pickPlace(origin: false),
                  ),
                ]),
              ),
              const SizedBox(width: Space.xs),
              RoundControl(
                icon: Icons.swap_vert,
                tooltip: 'Tukar asal & tujuan',
                onTap: _busy || _destination.isEmpty
                    ? null
                    : () => setState(() { final o = _origin; _origin = _destination; _destination = o; }),
              ),
            ]),
            const SizedBox(height: Space.sm),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                Pill(label: 'Step-Free / Lift', icon: Icons.accessible, selected: _stepFree,
                    onTap: () => setState(() { _stepFree = !_stepFree; if (_stepFree) { _avoidStairs = true; _access = 'elevator'; } else if (_access == 'elevator') { _access = 'any'; } })),
                const SizedBox(width: Space.xs),
                Pill(label: 'Hindari Tangga', icon: Icons.block, selected: _avoidStairs,
                    onTap: () => setState(() { _avoidStairs = !_avoidStairs; if (!_avoidStairs) _stepFree = false; })),
                const SizedBox(width: Space.xs),
                Pill(label: 'Paling Cepat', icon: Icons.bolt, selected: _focus == 'fastest',
                    onTap: () => setState(() => _focus = _focus == 'fastest' ? 'best_fit' : 'fastest')),
                const SizedBox(width: Space.xs),
                Pill(label: 'Minim Jalan Kaki', icon: Icons.directions_walk, selected: _focus == 'min_walk',
                    onTap: () => setState(() => _focus = _focus == 'min_walk' ? 'best_fit' : 'min_walk')),
                const SizedBox(width: Space.xs),
                Pill(label: 'Lainnya', icon: Icons.tune, selected: _advanced, onTap: () => setState(() => _advanced = !_advanced)),
              ]),
            ),
            if (_advanced) ...[
              const SizedBox(height: Space.sm),
              _advancedForm(t),
            ],
            const SizedBox(height: Space.sm),
            FilledButton.icon(
              onPressed: _busy ? null : _recommend,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.alt_route),
              label: Text(_busy ? _busyMessages[_busyPhase] : 'Bandingkan Tiga Rute'),
            ),
            if (_busy) ...[
              const SizedBox(height: Space.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.std),
                child: const LinearProgressIndicator(minHeight: 3, backgroundColor: AppColors.surfaceContainer),
              ),
            ],
            if (_error != null)
              Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13))),
          ]),
        ),
        const SizedBox(height: Space.md),
        // Hero floor plan.
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.lg),
          child: SizedBox(
            height: 300,
            child: Stack(children: [
              Positioned.fill(
                child: StationMap(styleUrl: widget.mapStyleUrl, catalog: catalog, floor: _floor, route: _selected, crowd: _crowd),
              ),
              Positioned(
                right: Space.xs, top: Space.xs,
                child: FloorSwitcher(floors: floors, active: _floor, onChanged: (f) => setState(() => _floor = f)),
              ),
              Positioned(
                left: Space.xs, bottom: Space.xs,
                child: Wrap(spacing: 6, children: [
                  const Tag('Rute', icon: Icons.circle, color: Colors.white, fg: AppColors.secondary),
                  const Tag('Pindah lantai', icon: Icons.circle, color: Colors.white, fg: Colors.orange),
                  Tag('Kepadatan simulasi (${_crowd?.userCount ?? 0})', icon: Icons.circle, color: Colors.white, fg: AppColors.danger),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: Space.md),
        // Route options.
        Row(children: [
          const Icon(Icons.alt_route, color: AppColors.secondary),
          const SizedBox(width: Space.xs),
          Text('Pilihan Rute Stasiun', style: t.headlineMedium),
          const Spacer(),
          if (_recommendation != null)
            Tag('${routes.length} rute valid', color: AppColors.accentLight, fg: AppColors.secondary),
        ]),
        const SizedBox(height: Space.xs),
        if (_recommendation == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Text('Pilih asal & tujuan lalu bandingkan. Tiga mode dihitung backend: paling sesuai, paling cepat, minim jalan kaki.',
                style: t.bodyMedium?.copyWith(color: AppColors.slate, fontSize: 14)),
          ),
        if (routesIdentical(routes)) ...[
          const SourceNote(kIdenticalRoutesNote, icon: Icons.info_outline),
          const SizedBox(height: Space.xs),
        ],
        if (_recommendation != null && routes.isEmpty)
          const SourceNote('Tidak ada rute yang memenuhi seluruh batasan. Longgarkan preferensi.', icon: Icons.info_outline),
        for (final r in routes)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: _RouteOptionCard(
              route: r,
              catalog: catalog,
              recommended: r.id == _recommendation!.selectedId,
              selected: r.id == _selected?.id,
              onTap: () => setState(() { _selected = r; final f = routeFloors(r); if (f.isNotEmpty) _floor = f.first; }),
            ),
          ),
        if (insightText != null && insightText.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(Radii.lg)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Insight AI', style: t.labelMedium?.copyWith(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(insightText, style: t.bodyMedium?.copyWith(color: Colors.white, fontSize: 14)),
                ]),
              ),
            ]),
          ),
        ],
        if (_selected != null) ...[
          const SizedBox(height: Space.md),
          Row(children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(onPressed: _openDetail, icon: const Icon(Icons.navigation), label: const Text('Mulai Navigasi')),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.surfaceContainer, foregroundColor: AppColors.primary),
                onPressed: _showSteps,
                icon: const Icon(Icons.list),
                label: const Text('Langkah'),
              ),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _advancedForm(TextTheme t) {
    final places = (_catalog!['places'] as List).cast<Map>();
    final viaCandidates = places.where((p) => p['kind'] == 'toilet' || p['kind'] == 'mushola').toList();
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _message,
          decoration: const InputDecoration(labelText: 'Kebutuhan perjalanan (opsional, ditafsirkan AI)', fillColor: Colors.white),
        ),
        const SizedBox(height: Space.xs),
        DropdownButtonFormField<String>(
          initialValue: _access,
          decoration: const InputDecoration(labelText: 'Akses antarlantai', fillColor: Colors.white),
          items: const [
            DropdownMenuItem(value: 'any', child: Text('Otomatis')),
            DropdownMenuItem(value: 'elevator', child: Text('Lift')),
            DropdownMenuItem(value: 'escalator', child: Text('Eskalator')),
            DropdownMenuItem(value: 'stairs', child: Text('Tangga')),
          ],
          onChanged: _busy ? null : (v) => setState(() => _access = v ?? 'any'),
        ),
        const SizedBox(height: Space.xs),
        TextField(
          controller: _walkLimit,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Batas jalan kaki (meter)', fillColor: Colors.white),
        ),
        const SizedBox(height: Space.xs),
        Text('Singgah wajib', style: t.labelSmall?.copyWith(color: AppColors.slate)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in viaCandidates)
            Pill(
              label: '${p['label']} • ${floorShort(p['floor'])}',
              selected: _via.contains(p['id']),
              onTap: () => setState(() { _via.contains(p['id']) ? _via.remove(p['id']) : _via.add(p['id'] as String); }),
            ),
        ]),
        const SizedBox(height: Space.xs),
        Text('Bobot prioritas', style: t.labelSmall?.copyWith(color: AppColors.slate)),
        _priority('Waktu', _timeWeight, (v) => setState(() { _timeWeight = v; _prioritiesChanged = true; })),
        _priority('Jalan kaki', _walkWeight, (v) => setState(() { _walkWeight = v; _prioritiesChanged = true; })),
        _priority('Keramaian', _crowdWeight, (v) => setState(() { _crowdWeight = v; _prioritiesChanged = true; })),
      ]),
    );
  }

  Widget _priority(String label, double value, ValueChanged<double> changed) => Row(children: [
    SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 13))),
    Expanded(child: Slider(value: value, min: 0, max: 5, divisions: 10, label: value.toStringAsFixed(1), onChanged: _busy ? null : changed)),
    SizedBox(width: 30, child: Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 13))),
  ]);
}

class _PlaceField extends StatelessWidget {
  const _PlaceField({required this.label, required this.icon, required this.iconColor, required this.value, required this.onTap});
  final String label, value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
          child: Row(children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: t.labelSmall?.copyWith(letterSpacing: 0.6, color: AppColors.slate)),
                Text(value, style: t.labelMedium?.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const Icon(Icons.expand_more, color: AppColors.outline, size: 20),
          ]),
        ),
      ),
    );
  }
}

/// Searchable place picker: groups by floor, shows real kind and floor.
class _PlacePicker extends StatefulWidget {
  const _PlacePicker({required this.places, required this.catalog, required this.allowAuto});
  final List<Map> places;
  final Json catalog;
  final bool allowAuto;
  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final visible = widget.places.where((p) => _q.isEmpty || p['label'].toString().toLowerCase().contains(_q.toLowerCase())).toList();
    final byFloor = <Object?, List<Map>>{};
    for (final p in visible) { byFloor.putIfAbsent(p['floor'], () => []).add(p); }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, controller) => Column(children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(hintText: 'Cari titik…', prefixIcon: Icon(Icons.search)),
          ),
        ),
        const SizedBox(height: Space.xs),
        Expanded(
          child: ListView(controller: controller, padding: const EdgeInsets.symmetric(horizontal: Space.gutter), children: [
            if (widget.allowAuto)
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: AppColors.secondary),
                title: const Text('Dari pesan saya (AI menafsirkan tujuan)'),
                onTap: () => Navigator.of(ctx).pop(''),
              ),
            for (final e in byFloor.entries.toList()..sort((a, b) => ((b.key as int?) ?? -1).compareTo((a.key as int?) ?? -1))) ...[
              SectionHeader(title: floorLabel(widget.catalog, e.key), badge: '${e.value.length}'),
              for (final p in e.value)
                ListTile(
                  dense: true,
                  leading: Icon(iconForKind(p['kind']?.toString()), color: AppColors.secondary),
                  title: Text(p['label'].toString(), style: t.labelMedium),
                  subtitle: Text(kindLabel(p['kind']?.toString()), style: t.labelSmall?.copyWith(color: AppColors.slate)),
                  onTap: () => Navigator.of(ctx).pop(p['id'] as String),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _RouteOptionCard extends StatelessWidget {
  const _RouteOptionCard({required this.route, required this.catalog, required this.recommended, required this.selected, required this.onTap});
  final RouteOption route;
  final Json catalog;
  final bool recommended, selected;
  final VoidCallback onTap;

  static const _titles = {'best_fit': 'Rute Paling Sesuai', 'fastest': 'Rute Paling Cepat', 'min_walk': 'Rute Minim Jalan Kaki'};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final connectors = {for (final c in (catalog['connectors'] as List? ?? []).cast<Map>()) c['id']: c};
    final used = (route.data['connectors_used'] as List? ?? []).cast<String>().map((id) => connectors[id]).whereType<Map>().toList();
    final kinds = {for (final c in used) c['kind'].toString()};
    final minutes = route.durationSeconds / 60;
    return SurfaceCard(
      border: selected ? AppColors.secondary : null,
      elevated: selected,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Wrap(spacing: Space.xs, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(_titles[route.mode] ?? route.label, style: t.headlineSmall?.copyWith(fontSize: 17)),
              if (recommended) const Tag('Rekomendasi', color: AppColors.secondary, fg: Colors.white),
            ]),
          ),
          const SizedBox(width: Space.xs),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${minutes < 10 ? minutes.toStringAsFixed(1) : minutes.round()} mnt',
                style: t.headlineMedium?.copyWith(color: selected ? AppColors.secondary : AppColors.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
            Text('${route.walkingMeters.round()} m', style: t.labelSmall?.copyWith(color: AppColors.slate)),
          ]),
        ]),
        if (route.explanation.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(route.explanation, style: t.bodyMedium?.copyWith(fontSize: 14, color: AppColors.slate)),
        ],
        const SizedBox(height: Space.xs),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (kinds.isEmpty) const Tag('Tanpa pindah lantai', icon: Icons.layers_clear_outlined),
          if (kinds.contains('elevator')) const Tag('Lift', icon: Icons.elevator_outlined, color: AppColors.accentLight, fg: AppColors.secondary),
          if (kinds.contains('escalator')) const Tag('Eskalator', icon: Icons.escalator),
          if (kinds.contains('stairs')) const Tag('Tangga', icon: Icons.stairs, color: Color(0xFFFFF4E0), fg: Color(0xFF9A5B00)),
          if (kinds.isNotEmpty && !kinds.contains('stairs')) const Tag('Bebas tangga', icon: Icons.accessible, color: Color(0xFFDCFCE7), fg: Color(0xFF166534)),
          if ((route.data['sources'] as List? ?? []).contains('osrm_foot_openstreetmap'))
            const Tag('Jalan kaki luar (OpenStreetMap)', icon: Icons.public, color: Color(0xFFFFF4E0), fg: Color(0xFF9A5B00)),
          Tag('crowd ${route.crowdExposure.toStringAsFixed(2)} (simulasi)', icon: Icons.groups_outlined),
        ]),
        for (final w in route.warnings)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber, size: 14, color: AppColors.warning),
              const SizedBox(width: 4),
              Expanded(child: Text(w, style: const TextStyle(fontSize: 11, color: AppColors.warning))),
            ]),
          ),
      ]),
    );
  }
}
