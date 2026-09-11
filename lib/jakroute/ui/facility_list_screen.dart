import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import 'app_theme.dart';
import 'facility_detail_screen.dart';

IconData _iconForKind(String? kind) => switch (kind) {
      'toilet' => Icons.wc,
      'mushola' => Icons.mosque,
      'elevator' => Icons.elevator,
      'escalator' => Icons.escalator,
      'stairs' => Icons.stairs,
      'vending_machine' => Icons.local_cafe,
      'first_aid' => Icons.medical_services,
      'lactation_room' => Icons.child_friendly,
      'entrance' => Icons.door_sliding,
      _ => Icons.place,
    };

/// Mirrors stitch_jakroute_ui_ux_design_system/facility_search_results,
/// bound to real GET /catalog data.
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
  String _kind = 'Semua';

  @override
  void initState() {
    super.initState();
    widget.api.catalog().then((c) => setState(() => _catalog = c)).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final all = ((_catalog?['places'] as List?) ?? []).cast<Map>();
    final kinds = ['Semua', ...{for (final p in all) p['kind']?.toString() ?? ''}.where((k) => k.isNotEmpty)];
    final visible = all.where((p) {
      final label = (p['label']?.toString() ?? '').toLowerCase();
      final kind = p['kind']?.toString() ?? '';
      final matchesQuery = _query.isEmpty || label.contains(_query.toLowerCase()) || kind.contains(_query.toLowerCase());
      final matchesKind = _kind == 'Semua' || kind == _kind;
      return matchesQuery && matchesKind;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(backgroundColor: AppColors.surface, title: const Text('Fasilitas'), elevation: 0),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.sm),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Cari nama atau kategori fasilitas',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surfaceContainer,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.full), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              children: [
                for (final k in kinds)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.xs),
                    child: ChoiceChip(
                      label: Text(k),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
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
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final p = visible[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: Space.xs),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.surfaceContainer,
                                child: Icon(_iconForKind(p['kind']?.toString()), color: AppColors.primary, size: 20),
                              ),
                              title: Text(p['label']?.toString() ?? '', style: t.labelMedium),
                              subtitle: Text(p['kind']?.toString() ?? '', style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
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
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
