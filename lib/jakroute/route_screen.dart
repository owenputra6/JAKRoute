import 'package:flutter/material.dart';
import 'api_client.dart';
import 'models.dart';
import 'route_diagram.dart';
import 'mapid_route_map.dart';

class JakRouteScreen extends StatefulWidget {
  final JakRouteApi api;
  final String mapStyleUrl;
  const JakRouteScreen({super.key, required this.api, this.mapStyleUrl = ''});
  @override
  State<JakRouteScreen> createState() => _JakRouteScreenState();
}

class _JakRouteScreenState extends State<JakRouteScreen> {
  final _message = TextEditingController(text: 'Saya mau ke peron.');
  final _walkLimit = TextEditingController();
  Json? _catalog;
  CrowdSnapshot? _crowd;
  Recommendation? _recommendation;
  RouteOption? _selected;
  String? _error;
  bool _loading = true, _busy = false, _avoidStairs = false, _stepFree = false;
  String _origin = 'entrance_west', _destination = 'platform_1', _access = 'any';
  int _floor = 0, _requestGeneration = 0;
  double _timeWeight = 1, _walkWeight = 1, _crowdWeight = 1;
  bool _prioritiesChanged = false;
  final Set<String> _via = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final loaded = await Future.wait([
        widget.api.catalog(),
        widget.api.crowdSnapshot(),
      ]);
      final catalog = loaded[0] as Json;
      final crowd = loaded[1] as CrowdSnapshot;
      if (!mounted) return;
      final places = (catalog['places'] as List).cast<Map>();
      final ids = places.map((p) => p['id'] as String).toSet();
      setState(() {
        _catalog = catalog;
        _crowd = crowd;
        if (!ids.contains(_origin)) _origin = places.first['id'] as String;
        if (!ids.contains(_destination)) _destination = '';
        _floor = ((catalog['floors'] as List).first as Map)['id'] as int;
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
    setState(() { _busy = true; _error = null; _recommendation = null; _selected = null; });
    try {
      final result = await widget.api.recommend({
        'message': _message.text,
        'origin_id': _origin,
        'destination_id': _destination.isEmpty ? null : _destination,
        'via_indoor_ids': _via.toList(),
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
        _selected = available.isEmpty ? null : available.firstWhere(
            (r) => r.id == result.selectedId, orElse: () => available.first);
      });
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted && generation == _requestGeneration) setState(() => _busy = false); }
  }

  @override
  void dispose() { _message.dispose(); _walkLimit.dispose(); super.dispose(); }

  Widget _placeSelector(String label, String value, ValueChanged<String> changed, {bool automatic = false}) {
    final places = (_catalog!['places'] as List).cast<Map>();
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        if (automatic) const DropdownMenuItem(value: '', child: Text('Dari pesan saya')),
        ...places.map((p) => DropdownMenuItem(value: p['id'] as String,
            child: Text(p['label'] as String, overflow: TextOverflow.ellipsis))),
      ],
      onChanged: _busy ? null : (v) { if (v != null) changed(v); },
    );
  }

  Widget _priority(String label, double value, ValueChanged<double> changed) => Row(children: [
    SizedBox(width: 115, child: Text(label)),
    Expanded(child: Slider(value: value, min: 0, max: 5, divisions: 10,
        label: value.toStringAsFixed(1), onChanged: _busy ? null : changed)),
    SizedBox(width: 30, child: Text(value.toStringAsFixed(1))),
  ]);

  Widget _crowdCard(BuildContext context) {
    final crowd = _crowd;
    if (crowd == null) return const SizedBox.shrink();
    final sourceFile = crowd.source['file']?.toString() ?? 'GeoJSON';
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.groups_2_outlined),
        title: Text('Keramaian simulasi · ${crowd.userCount} titik'),
        subtitle: Text('Total bobot ${crowd.totalWeight.toStringAsFixed(2)} · $sourceFile'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Setiap titik memiliki bobot sendiri. Nilai area dihitung sebagai total bobot dibagi luas area asli—tanpa label low/medium/high.'),
          const SizedBox(height: 12),
          for (final area in crowd.areas) Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(children: [
              Expanded(child: Text('${area['label']} · ${area['user_count']} titik')),
              Text('${(area['weighted_users'] as num).toStringAsFixed(2)} / ${(area['area_m2'] as num).toStringAsFixed(1)} m²'),
            ]),
          ),
          Text('Snapshot: ${crowd.observedAt}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _insightCard(BuildContext context, RouteOption route) {
    final insight = route.insight;
    final facts = (insight['facts'] as List? ?? []).cast<Map>();
    final personalization = (insight['personalization'] as List? ?? []).cast<String>();
    final generator = insight['generator']?.toString() ?? 'backend_evidence';
    final sourceLabel = generator == 'openai_reason_selection'
        ? 'OpenAI'
        : generator == 'deterministic_demo' ? 'Simulasi logika' : 'Data backend';
    return Card(
      color: const Color(0xfff2f7ff),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: Color(0xff176bdf)),
            const SizedBox(width: 8),
            const Expanded(child: Text('AI Insight', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
            Chip(label: Text(sourceLabel)),
          ]),
          const SizedBox(height: 8),
          Text(insight['headline']?.toString() ?? route.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(insight['summary']?.toString() ?? route.explanation),
          if (personalization.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Disesuaikan untuk: ${personalization.join(', ')}.'),
          ],
          const Divider(height: 24),
          Wrap(spacing: 8, runSpacing: 8, children: facts.map((fact) => Chip(
            label: Text('${fact['label']}: ${fact['value']}'),
          )).toList()),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return Scaffold(
      appBar: AppBar(title: const Text('JAKRoute'), actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang')]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : catalog == null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error ?? 'Katalog belum tersedia.'), const SizedBox(height: 16), FilledButton(onPressed: _load, child: const Text('Coba lagi')),
          ])))
          : SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(catalog['label'] as String, style: Theme.of(context).textTheme.titleMedium),
            if ((catalog['station_data'] as Map?)?['source'] == 'supabase_rest')
              Text('Data lokasi: Supabase · ${((catalog['station_data'] as Map)['locations'] as List).length} titik'),
            if (catalog['simulated'] == true) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('MODE DEMO · Denah dan kondisi adalah simulasi.', style: TextStyle(color: Color(0xff9a601b)))),
            _crowdCard(context),
            const SizedBox(height: 12),
            _placeSelector('Lokasi awal', _origin, (v) => setState(() => _origin = v)),
            const SizedBox(height: 12),
            _placeSelector('Tujuan', _destination, (v) => setState(() => _destination = v), automatic: true),
            const SizedBox(height: 12),
            TextField(controller: _message, enabled: !_busy, maxLines: 2, maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Kebutuhan perjalanan', hintText: 'Misalnya: ke peron, jangan lewat tangga', border: OutlineInputBorder())),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Hindari tangga'), value: _avoidStairs,
                onChanged: _busy ? null : (v) => setState(() => _avoidStairs = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Akses bebas anak tangga'),
                subtitle: const Text('Termasuk menghindari eskalator'), value: _stepFree,
                onChanged: _busy ? null : (v) => setState(() => _stepFree = v)),
            ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Prioritas dan fasilitas'), children: [
              DropdownButtonFormField<String>(value: _access, decoration: const InputDecoration(labelText: 'Akses pilihan'),
                items: const [DropdownMenuItem(value: 'any', child: Text('Otomatis')),
                  DropdownMenuItem(value: 'elevator', child: Text('Lift')),
                  DropdownMenuItem(value: 'escalator', child: Text('Eskalator')),
                  DropdownMenuItem(value: 'stairs', child: Text('Tangga'))],
                onChanged: _busy ? null : (v) => setState(() => _access = v ?? 'any')),
              _priority('Cepat sampai', _timeWeight, (v) => setState(() { _timeWeight = v; _prioritiesChanged = true; })),
              _priority('Sedikit berjalan', _walkWeight, (v) => setState(() { _walkWeight = v; _prioritiesChanged = true; })),
              _priority('Hindari kepadatan', _crowdWeight, (v) => setState(() { _crowdWeight = v; _prioritiesChanged = true; })),
              TextField(controller: _walkLimit, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Batas berjalan (meter)', hintText: 'Kosongkan jika tidak dibatasi')),
              Wrap(spacing: 8, children: (catalog['places'] as List).cast<Map>()
                .where((p) => ['toilet', 'mushola'].contains(p['kind']))
                .map((p) => FilterChip(label: Text('Singgah ${p['label']}'), selected: _via.contains(p['id']),
                    onSelected: _busy ? null : (yes) => setState(() { yes ? _via.add(p['id'] as String) : _via.remove(p['id']); }))).toList()),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _busy ? null : _recommend,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.route),
                label: Text(_busy ? 'Mencari rute…' : 'Bandingkan tiga rute')),
            if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            if (_recommendation?.status == 'clarification_required') Padding(padding: const EdgeInsets.all(12), child: Text(_recommendation!.question ?? 'Lengkapi tujuan perjalanan.')),
            if (_recommendation != null) ...[
              const SizedBox(height: 16),
              for (final route in _recommendation!.routes) Card(
                color: _selected?.id == route.id ? const Color(0xffe9f1ff) : null,
                child: ListTile(onTap: route.available ? () => setState(() => _selected = route) : null,
                  leading: Icon(route.available ? Icons.alt_route : Icons.block),
                  title: Text(route.label),
                  subtitle: Text(route.available ? '${route.walkingMeters.toStringAsFixed(0)} m berjalan · ${(route.durationSeconds / 60).toStringAsFixed(1)} menit · crowd ${route.crowdExposure.toStringAsFixed(2)}' : route.explanation),
                  trailing: _selected?.id == route.id ? const Icon(Icons.check_circle, color: Color(0xff176bdf)) : null)),
              if (_selected != null) ...[
                const SizedBox(height: 12), _insightCard(context, _selected!),
                for (final warning in _selected!.warnings) Padding(padding: const EdgeInsets.only(top: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, size: 18, color: Color(0xff9a601b)), const SizedBox(width: 8), Expanded(child: Text(warning)),
                ])),
              ],
              if (_recommendation!.forumSummary.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Kondisi fasilitas: ${_recommendation!.forumSummary}')),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: (catalog['floors'] as List).cast<Map>().map((f) => ChoiceChip(
                label: Text('Lantai ${f['id']}'), selected: _floor == f['id'], onSelected: (_) => setState(() => _floor = f['id'] as int))).toList()),
            const SizedBox(height: 8), RouteDiagram(catalog: catalog, route: _selected, crowd: _crowd, floor: _floor),
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Biru: jalur · Merah: titik crowd berbobot · Gelap: obstacle · Oranye: perpindahan lantai', style: TextStyle(fontSize: 12))),
            if (widget.mapStyleUrl.isNotEmpty) ...[
              const SizedBox(height: 16), MapidRouteMap(styleUrl: widget.mapStyleUrl, catalog: catalog, floor: _floor, route: _selected),
            ],
          ])),
    );
  }
}
