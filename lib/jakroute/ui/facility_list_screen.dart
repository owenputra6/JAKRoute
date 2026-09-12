import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import 'app_theme.dart';
import 'facility_detail_screen.dart';
import 'kinds.dart';
import 'widgets.dart';

/// Fasilitas tab (revised UI UX/direktori_fasilitas_stasiun): directory
/// header with the real mapped-point count, search, category pills with
/// counts, a survey-validation note, and grouped cards with LT badges.
/// Every row is a real `/catalog` place; grouping only reorganizes real
/// `kind` values. No fabricated tags (grab bars, hours, sanitation status).
class FacilityListScreen extends StatefulWidget {
  const FacilityListScreen({super.key, required this.api, required this.mapStyleUrl, this.onAvatarTap});

  final JakRouteApi api;
  final String mapStyleUrl;
  final VoidCallback? onAvatarTap;

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

  void _open(Map p) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FacilityDetailScreen(
          place: p,
          api: widget.api,
          mapStyleUrl: widget.mapStyleUrl,
          stationLabel: _catalog?['label']?.toString() ?? 'Stasiun Palmerah',
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final all = ((_catalog?['places'] as List?) ?? []).cast<Map>();
    final counts = <String, int>{'Semua': all.length};
    for (final p in all) {
      final g = groupForKind(p['kind']?.toString());
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final visible = all.where((p) {
      final label = (p['label']?.toString() ?? '').toLowerCase();
      final kind = p['kind']?.toString() ?? '';
      final q = _query.toLowerCase();
      final matchesQuery = q.isEmpty || label.contains(q) || kindLabel(kind).toLowerCase().contains(q);
      final matchesGroup = _group == 'Semua' || groupForKind(kind) == _group;
      return matchesQuery && matchesGroup;
    }).toList();
    final sections = <String, List<Map>>{};
    for (final p in visible) {
      sections.putIfAbsent(groupForKind(p['kind']?.toString()), () => []).add(p);
    }
    final blocks = (_catalog?['source_counts'] as Map?)?['blocks'];

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: BrandBar(context: 'Fasilitas Stasiun', onAvatarTap: widget.onAvatarTap),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xl),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Direktori Fasilitas', style: t.displayLarge?.copyWith(fontSize: 28)),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.storage_outlined, size: 16, color: AppColors.secondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _catalog == null
                            ? 'Memuat…'
                            : '${all.length} titik terpetakan${blocks != null ? ' • $blocks blok' : ''} • ${_catalog!['label']}',
                        style: t.labelSmall?.copyWith(color: AppColors.slate),
                      ),
                    ),
                  ]),
                ]),
              ),
              const Tag('Supabase PostGIS', icon: Icons.circle, color: AppColors.accentLight, fg: AppColors.secondary),
            ],
          ),
          const SizedBox(height: Space.sm),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              hintText: 'Cari toilet, lift, musala, ATM, kios…',
              prefixIcon: Icon(Icons.search, color: AppColors.slate),
              fillColor: AppColors.surfaceContainerLowest,
            ),
          ),
          const SizedBox(height: Space.sm),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final g in counts.keys) ...[
                  Pill(
                    label: g,
                    count: counts[g],
                    dotColor: g == 'Semua' ? null : groupColor(g),
                    selected: _group == g,
                    onTap: () => setState(() => _group = g),
                  ),
                  const SizedBox(width: Space.xs),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          const SourceNote('Validasi geospasial: survei lapangan, tersimpan di Supabase (station_blocks / station_nodes).'),
          if (_catalog == null)
            const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
          else if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Center(child: Text('Tidak ada fasilitas cocok.', style: t.bodyMedium)),
            ),
          for (final entry in sections.entries) ...[
            SectionHeader(title: entry.key, badge: '${entry.value.length} titik', accent: groupColor(entry.key)),
            for (final p in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: SurfaceCard(
                  padding: const EdgeInsets.all(Space.sm),
                  onTap: () => _open(p),
                  child: Row(children: [
                    FacilityThumb(place: p, color: groupColor(entry.key), size: 48),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p['label']?.toString() ?? '', style: t.labelMedium?.copyWith(fontSize: 15)),
                        Text('${kindLabel(p['kind']?.toString())} • ${floorLabel(_catalog!, p['floor'])}',
                            style: t.labelSmall?.copyWith(color: AppColors.slate)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Icon(Icons.chevron_right, color: AppColors.outline, size: 20),
                      const SizedBox(height: 4),
                      Text(floorShort(p['floor']), style: t.labelMedium?.copyWith(color: AppColors.secondary)),
                    ]),
                  ]),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
