import 'package:flutter/material.dart';

import '../api_client.dart';
import '../route_diagram.dart';
import '../models.dart';
import 'app_theme.dart';
import 'chat_screen.dart';
import 'facility_detail_screen.dart';

/// Mirrors stitch_jakroute_ui_ux_design_system/home_search_route: full-screen
/// map, pill search bar, floor badge, draggable facility sheet. Basemap is
/// the existing MapidRouteMap (MAPID GL) — not a placeholder — bound to real
/// Supabase catalog data. Search/facility taps hand off to ChatScreen, which
/// is the actual AI routing surface.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.mapStyleUrl});

  final JakRouteApi api;
  final String mapStyleUrl;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Json? _catalog;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await widget.api.catalog();
      if (mounted) setState(() => _catalog = c);
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal memuat data stasiun.');
    }
  }

  void _openChat({String? initialMessage}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl, initialMessage: initialMessage),
    ));
  }

  void _openFacility(Map place) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FacilityDetailScreen(
        place: place,
        api: widget.api,
        mapStyleUrl: widget.mapStyleUrl,
        stationLabel: _catalog?['label']?.toString() ?? 'Stasiun Palmerah',
      ),
    ));
  }

  int get _floor {
    final floors = (_catalog?['floors'] as List?) ?? [];
    if (floors.isEmpty) return 0;
    return (floors.first as Map)['id'] as int? ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final places = ((_catalog?['places'] as List?) ?? []).cast<Map>();
    return Scaffold(
      body: Stack(
        children: [
          if (_catalog != null)
            Positioned.fill(child: RouteDiagram(catalog: _catalog!, floor: _floor))
          else
            Container(color: AppColors.surfaceContainer),
          _SearchBar(onTap: () => _openChat(), label: _catalog?['label']?.toString()),
          const _FloorBadge(),
          _BottomSheetPanel(
            label: _catalog?['label']?.toString() ?? 'Memuat stasiun…',
            places: places,
            error: _error,
            onFacilityTap: _openFacility,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'ai',
        backgroundColor: AppColors.primary,
        onPressed: () => _openChat(),
        child: const Icon(Icons.auto_awesome, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap, required this.label});
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + Space.xs,
      left: Space.gutter,
      right: Space.gutter,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(Radii.full),
            boxShadow: const [kSurfaceShadow],
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: AppColors.onSurfaceVariant),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  label == null ? 'Cari fasilitas atau tanya AI…' : 'Cari fasilitas di $label',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.outline),
                ),
              ),
              const Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloorBadge extends StatelessWidget {
  const _FloorBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: Space.gutter,
      top: MediaQuery.of(context).size.height * 0.22,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(Radii.md),
          boxShadow: const [kSurfaceShadow],
        ),
        child: Text('LT 2', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white)),
      ),
    );
  }
}

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

class _BottomSheetPanel extends StatelessWidget {
  const _BottomSheetPanel({required this.label, required this.places, required this.error, required this.onFacilityTap});
  final String label;
  final List<Map> places;
  final String? error;
  final ValueChanged<Map> onFacilityTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.32,
      minChildSize: 0.18,
      maxChildSize: 0.85,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
          boxShadow: [kSurfaceShadow],
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.lg),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: Space.sm),
                decoration: BoxDecoration(color: AppColors.outlineVariant, borderRadius: BorderRadius.circular(Radii.full)),
              ),
            ),
            Text(label, style: t.headlineSmall),
            const SizedBox(height: 2),
            Text('${places.length} fasilitas terverifikasi survei',
                style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: Space.sm),
            if (error != null) Text(error!, style: const TextStyle(color: AppColors.danger)),
            for (final p in places)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppColors.surfaceContainer,
                  child: Icon(_iconForKind(p['kind']?.toString()), color: AppColors.primary, size: 20),
                ),
                title: Text(p['label']?.toString() ?? '', style: t.labelMedium),
                subtitle: Text(p['kind']?.toString() ?? '', style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.outline),
                onTap: () => onFacilityTap(p),
              ),
          ],
        ),
      ),
    );
  }
}
