import 'package:flutter/material.dart';

import '../api_client.dart';
import '../facility_photos.dart';
import '../route_screen.dart';
import 'app_theme.dart';
import 'chat_screen.dart';
import 'kinds.dart';
import 'widgets.dart';

/// One real place row from GET /catalog (Supabase station_nodes). Only fields
/// the backend returns: label, kind, floor, node type, source id. Two actions:
/// plan a route here (advanced planner, destination prefilled) or ask the AI.
class FacilityDetailScreen extends StatelessWidget {
  const FacilityDetailScreen({
    super.key,
    required this.place,
    required this.api,
    required this.mapStyleUrl,
    required this.stationLabel,
  });

  final Map place;
  final JakRouteApi api;
  final String mapStyleUrl;
  final String stationLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final label = place['label']?.toString() ?? 'Fasilitas';
    final kind = place['kind']?.toString() ?? '';
    final group = groupForKind(kind);
    final nodeType = switch (place['node_type']) {
      'connector_access' => 'Akses antarlantai (konektor)',
      'entrance_access' => 'Pintu masuk / keluar stasiun',
      'facility_entrance' => 'Pintu masuk fasilitas',
      'destination' => 'Titik tujuan',
      'outdoor_poi' => 'Tempat di luar stasiun',
      _ => null,
    };

    final photos = facilityPhotos[place['id']?.toString()] ?? const <String>[];
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: BrandBar(context: kindLabel(kind), leading: const BackButton()),
      body: ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          if (photos.isNotEmpty) ...[
            _PhotoStrip(photos: photos),
            const SizedBox(height: Space.md),
          ],
          SurfaceCard(
            child: Row(children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: groupColor(group).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(Radii.md)),
                child: Icon(iconForKind(kind), color: groupColor(group), size: 32),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: t.headlineMedium),
                  Text(stationLabel, style: t.labelSmall?.copyWith(color: AppColors.slate)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    Tag(kindLabel(kind), color: groupColor(group).withValues(alpha: 0.12), fg: groupColor(group)),
                    if (place['floor'] != null) Tag(floorShort(place['floor']), icon: Icons.layers_outlined, color: AppColors.accentLight, fg: AppColors.secondary),
                  ]),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: Space.md),
          SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Data titik', style: t.headlineSmall),
              const SizedBox(height: Space.xs),
              _InfoRow(label: 'Kategori', value: '$group • ${kindLabel(kind)}'),
              if (nodeType != null) _InfoRow(label: 'Jenis titik', value: nodeType),
              _InfoRow(label: 'Lantai', value: floorLabel(const {}, place['floor'])),
              if (place['routing_adjustment_m'] != null)
                _InfoRow(label: 'Penyesuaian ke area jalan', value: '${place['routing_adjustment_m']} m'),
              if (place['osm_tag'] != null) _InfoRow(label: 'Tag OSM', value: place['osm_tag'].toString(), mono: true),
              if (place['id'] != null) _InfoRow(label: 'ID titik', value: place['id'].toString(), mono: true),
              _InfoRow(
                label: 'Sumber data',
                value: isOutdoor(place) ? 'OpenStreetMap (Overpass) — data komunitas, bukan survei' : 'Supabase PostGIS — survei lapangan (station_nodes)',
                last: true,
              ),
            ]),
          ),
          const SizedBox(height: Space.lg),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => JakRouteScreen(api: api, mapStyleUrl: mapStyleUrl, initialDestinationId: place['id']?.toString()),
            )),
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Rute ke Sini'),
          ),
          const SizedBox(height: Space.xs),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChatScreen(api: api, mapStyleUrl: mapStyleUrl, initialMessage: isOutdoor(place) ? 'Saya mau keluar stasiun ke $label.' : 'Saya mau ke $label (Lantai ${place['floor']}).'),
            )),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Tanya AI rute ke sini'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.mono = false, this.last = false});

  final String label;
  final String value;
  final bool mono, last;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: t.bodyMedium?.copyWith(fontSize: 14, color: AppColors.slate))),
          Expanded(
            flex: 2,
            child: Text(value, textAlign: TextAlign.right,
                style: t.labelMedium?.copyWith(fontSize: 13, fontFamily: mono ? 'monospace' : null)),
          ),
        ]),
      ),
      if (!last) const Divider(),
    ]);
  }
}

/// Survey photos, swipeable; tap opens full-screen.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos});
  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 220,
        child: PageView.builder(
          controller: PageController(viewportFraction: photos.length > 1 ? 0.9 : 1),
          itemCount: photos.length,
          itemBuilder: (_, i) => Padding(
            padding: EdgeInsets.only(right: photos.length > 1 ? Space.xs : 0),
            child: GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => Dialog.fullscreen(
                  backgroundColor: Colors.black,
                  child: Stack(children: [
                    Center(child: InteractiveViewer(child: Image.asset(photos[i]))),
                    Positioned(top: 8, right: 8, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop())),
                  ]),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.lg),
                child: Image.asset(photos[i], fit: BoxFit.cover, width: double.infinity),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text('Foto survei lapangan 30 Agu 2026${photos.length > 1 ? ' • geser untuk foto lain' : ''}',
          style: t.labelSmall?.copyWith(color: AppColors.slate)),
    ]);
  }
}
