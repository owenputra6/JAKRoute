import 'package:flutter/material.dart';

import '../api_client.dart';
import 'app_theme.dart';
import 'chat_screen.dart';
import 'kinds.dart';

/// Mirrors stitch_jakroute_ui_ux_design_system/facility_detail_view, bound to
/// a real place row from GET /catalog (Supabase station_blocks/station_nodes).
/// No fabricated status/notes — only fields the backend actually returns.
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

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.surface, title: Text(kindLabel(kind))),
      body: ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(iconForKind(kind), color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: t.headlineSmall),
                    Text(stationLabel, style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          _InfoRow(label: 'Kategori', value: kindLabel(kind)),
          if (place['floor'] != null) _InfoRow(label: 'Lantai', value: floorShort(place['floor'])),
          _InfoRow(label: 'Sumber data', value: 'Supabase — station_blocks / station_nodes (survei lapangan)'),
          if (place['id'] != null) _InfoRow(label: 'ID titik', value: place['id'].toString()),
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChatScreen(api: api, mapStyleUrl: mapStyleUrl, initialMessage: 'Saya mau ke $label.'),
            )),
            child: const Text('Rute ke Sini'),
          ),
          const SizedBox(height: Space.xs),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Lihat Fasilitas Lain'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: t.bodyMedium),
          const SizedBox(height: Space.xs),
          const Divider(height: 1, color: AppColors.hairline),
        ],
      ),
    );
  }
}
