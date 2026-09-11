import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import 'app_theme.dart';
import 'facility_detail_screen.dart';
import 'kinds.dart';

Color _groupColor(String group) => switch (group) {
      'Aksesibilitas' => AppColors.secondary,
      'Fasilitas Umum' => AppColors.success,
      'Akses Masuk' => AppColors.tertiaryFixedDim,
      'Komersial' => AppColors.warning,
      _ => AppColors.outline,
    };

/// Mirrors stitch_jakroute_ui_ux_design_system/facility_search_results,
/// bound to real GET /catalog data. Grouping reflects real `kind` values
/// only — no fabricated status badges, floors, hours, or distances.
class FacilityListScreen extends StatefulWidget {
  const FacilityListScreen({super.key, required this.api, required this.mapStyleUrl});

  final JakRouteApi api;
  final String mapStyleUrl;

  @override
  State<FacilityListScreen> createState() => _FacilityListScreenState();
}

class _FacilityListScreenState extends State<FacilityListScreen> {
  Json? _catalog;
  String _query = '';
  String _group = 'Semua';

  @override
  void initState() {
    super.initState();
    widget.api.catalog().then((c) => setState(() => _catalog = c)).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final all = ((_catalog?['places'] as List?) ?? []).cast<Map>();
    final groups = ['Semua', ...{for (final p in all) groupForKind(p['kind']?.toString())}];
    final visible = all.where((p) {
      final label = (p['label']?.toString() ?? '').toLowerCase();
      final kind = p['kind']?.toString() ?? '';
      final matchesQuery = _query.isEmpty || label.contains(_query.toLowerCase()) || kindLabel(kind).toLowerCase().contains(_query.toLowerCase());
      final matchesGroup = _group == 'Semua' || groupForKind(kind) == _group;
      return matchesQuery && matchesGroup;
    }).toList();
    final sections = <String, List<Map>>{};
    for (final p in visible) {
      sections.putIfAbsent(groupForKind(p['kind']?.toString()), () => []).add(p);
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(backgroundColor: AppColors.surface, elevation: 0,
        title: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Fasilitas Stasiun'),
          if (_catalog != null) Text(_catalog!['label'] as String,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: AppColors.onSurfaceVariant)),
        ]),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.sm),
            child: Row(children: [
              Expanded(child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Cari lift, eskalator, toilet, mushola...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.full), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              )),
              if (_query.isNotEmpty || _group != 'Semua') ...[
                const SizedBox(width: Space.xs),
                IconButton(tooltip: 'Reset filter', icon: const Icon(Icons.filter_alt_off),
                    onPressed: () => setState(() { _query = ''; _group = 'Semua'; })),
              ],
            ]),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              children: [
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.xs),
                    child: ChoiceChip(
                      avatar: g == 'Semua' ? null : Icon(Icons.circle, size: 10, color: _groupColor(g)),
                      label: Text(g),
                      selected: _group == g,
                      onSelected: (_) => setState(() => _group = g),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          Expanded(
            child: _catalog == null
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? Center(child: Text('Tidak ada fasilitas cocok.', style: t.bodyMedium))
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                        children: [
                          for (final entry in sections.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(Space.xs, Space.sm, Space.xs, Space.xs),
                              child: Row(children: [
                                Icon(Icons.circle, size: 8, color: _groupColor(entry.key)),
                                const SizedBox(width: Space.xs),
                                Expanded(child: Text(entry.key.toUpperCase(),
                                    style: t.labelSmall?.copyWith(letterSpacing: 0.5, color: AppColors.onSurfaceVariant))),
                                Text('${entry.value.length} fasilitas', style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
                              ]),
                            ),
                            for (final p in entry.value)
                              Card(
                                margin: const EdgeInsets.only(bottom: Space.xs),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: _groupColor(entry.key).withValues(alpha: 0.12),
                                    child: Icon(iconForKind(p['kind']?.toString()), color: _groupColor(entry.key), size: 20),
                                  ),
                                  title: Text(p['label']?.toString() ?? '', style: t.labelMedium),
                                  subtitle: Text('${kindLabel(p['kind']?.toString())} · ${floorShort(p['floor'])}', style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
                                  trailing: const Icon(Icons.chevron_right, color: AppColors.outline),
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => FacilityDetailScreen(
                                      place: p,
                                      api: widget.api,
                                      mapStyleUrl: widget.mapStyleUrl,
                                      stationLabel: _catalog?['label']?.toString() ?? 'Stasiun Palmerah',
                                    ),
                                  )),
                                ),
                              ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
