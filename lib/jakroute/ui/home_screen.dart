import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../station_map.dart';
import '../route_screen.dart';
import 'app_theme.dart';
import 'chat_screen.dart';
import 'facility_detail_screen.dart';
import 'kinds.dart';
import 'widgets.dart';

/// Peta tab (revised UI UX/peta_eksplorasi_stasiun_palmerah): map-first,
/// floating search pill with a directions button, category filter pills,
/// floor switcher stack, and a draggable sheet listing the real surveyed
/// facilities on the active floor. No distances-from-user, queue status or
/// operational badges — the backend does not return them.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.mapStyleUrl, this.onAvatarTap, this.onAskAi});

  final JakRouteApi api;
  final String mapStyleUrl;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onAskAi;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Json? _catalog;
  String? _error;
  int? _floor;
  String _group = 'Semua';

  @override
  void initState() {
    super.initState();
    _load();
  }

  static bool _askedFloor = false;

  Future<void> _load() async {
    try {
      final c = await widget.api.catalog();
      if (mounted) setState(() => _catalog = c);
      if (mounted && !_askedFloor && (c['floors'] as List?)?.length == 2) {
        _askedFloor = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _confirmFloor());
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal memuat data stasiun.');
    }
  }

  /// "Anda berada di lantai mana?" — visual confirmation with real station
  /// photos (survey 30 Aug 2026), since there is no indoor positioning.
  Future<void> _confirmFloor() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        Widget card(int floor, String title, String hint, String asset) => Expanded(
              child: Material(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Radii.lg),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  onTap: () => Navigator.of(ctx).pop(floor),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
                      child: AspectRatio(aspectRatio: 4 / 3, child: Image.asset(asset, fit: BoxFit.cover)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Space.sm),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: t.labelMedium?.copyWith(fontSize: 15)),
                        Text(hint, style: t.labelSmall?.copyWith(color: AppColors.slate)),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SheetHandle(),
            Text('Anda berada di lantai mana?', style: t.headlineSmall),
            Text('Tidak ada GPS indoor — cocokkan dengan foto stasiun.', style: t.labelSmall?.copyWith(color: AppColors.slate)),
            const SizedBox(height: Space.sm),
            Row(children: [
              card(1, 'Lantai 1 — Peron', 'Rel kereta, peron 1 & 2', 'assets/floor_peron.jpg'),
              const SizedBox(width: Space.xs),
              card(2, 'Lantai 2 — Hall', 'Gerbang tap, toilet, kios', 'assets/floor_hall.jpg'),
            ]),
          ]),
        );
      },
    );
    if (picked != null && mounted) setState(() => _floor = picked);
  }

  List<Map> get _floors => ((_catalog?['floors'] as List?) ?? []).cast<Map>();
  int get _activeFloor => _floor ?? (_floors.isEmpty ? 0 : (_floors.last['id'] as int? ?? 0));

  void _openChat() {
    if (widget.onAskAi != null) {
      widget.onAskAi!();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl),
    ));
  }

  void _openPlanner({String? destinationId}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JakRouteScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl, initialDestinationId: destinationId),
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

  @override
  Widget build(BuildContext context) {
    final all = ((_catalog?['places'] as List?) ?? []).cast<Map>();
    final onFloor = all.where((p) => p['floor'] == _activeFloor || isOutdoor(p)).toList();
    final groups = ['Semua', ...{for (final p in all) groupForKind(p['kind']?.toString())}];
    final visible = onFloor.where((p) => _group == 'Semua' || groupForKind(p['kind']?.toString()) == _group).toList();

    return Scaffold(
      appBar: BrandBar(onAvatarTap: widget.onAvatarTap),
      body: Stack(
        children: [
          if (_catalog != null)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, c) => StationMap(
                  styleUrl: widget.mapStyleUrl,
                  catalog: _catalog!,
                  floor: _activeFloor,
                  padding: EdgeInsets.fromLTRB(24, 120, 90, c.maxHeight * 0.34 + 16),
                ),
              ),
            )
          else
            Container(color: AppColors.surfaceContainerLow, child: _error == null ? const Center(child: CircularProgressIndicator()) : null),
          Positioned(
            top: Space.sm,
            left: Space.gutter,
            right: Space.gutter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SearchPill(
                  label: _catalog == null ? 'Memuat data stasiun…' : 'Cari fasilitas di ${_catalog!['label']}',
                  onTap: _openChat,
                  onDirections: _catalog == null ? null : () => _openPlanner(),
                ),
                const SizedBox(height: Space.xs),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final g in groups) ...[
                        Pill(
                          label: g,
                          icon: g == 'Semua' ? Icons.tune : null,
                          dotColor: g == 'Semua' ? null : groupColor(g),
                          selected: _group == g,
                          onTap: () => setState(() => _group = g),
                        ),
                        const SizedBox(width: Space.xs),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_floors.isNotEmpty)
            Positioned(
              right: Space.gutter,
              top: 120,
              child: FloorSwitcher(floors: _floors, active: _activeFloor, onChanged: (f) => setState(() => _floor = f)),
            ),
          _FacilitySheet(
            title: 'Fasilitas ${floorShort(_activeFloor)}',
            subtitle: _catalog == null ? 'Memuat…' : '${_catalog!['label']} • ${floorLabel(_catalog!, _activeFloor)}',
            places: visible,
            total: onFloor.where((p) => !isOutdoor(p)).length,
            outdoor: onFloor.where(isOutdoor).length,
            error: _error,
            onTap: _openFacility,
            onRoute: (p) => _openPlanner(destinationId: p['id'] as String),
            onAskAi: _openChat,
          ),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.label, required this.onTap, required this.onDirections});
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onDirections;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(Space.md, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [kRaisedShadow],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.secondary),
          const SizedBox(width: Space.sm),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Text(label, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.slate)),
            ),
          ),
          Tooltip(
            message: 'Rencanakan rute',
            child: Material(
              color: onDirections == null ? AppColors.surfaceContainer : AppColors.secondary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onDirections,
                child: const SizedBox(width: 44, height: 44, child: Icon(Icons.directions, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FacilitySheet extends StatelessWidget {
  const _FacilitySheet({
    required this.title,
    required this.subtitle,
    required this.places,
    required this.total,
    required this.outdoor,
    required this.error,
    required this.onTap,
    required this.onRoute,
    required this.onAskAi,
  });
  final String title;
  final String subtitle;
  final List<Map> places;
  final int total;
  final int outdoor;
  final String? error;
  final ValueChanged<Map> onTap;
  final ValueChanged<Map> onRoute;
  final VoidCallback onAskAi;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.34,
      minChildSize: 0.16,
      maxChildSize: 0.88,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
          boxShadow: [kRaisedShadow],
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          children: [
            const SheetHandle(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: t.headlineMedium),
                    Text(subtitle, style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Tag('$total titik survei', icon: Icons.verified_outlined, color: AppColors.accentLight, fg: AppColors.secondary),
                  if (outdoor > 0) ...[
                    const SizedBox(height: 4),
                    Tag('$outdoor tempat luar (OSM)', icon: Icons.public, color: const Color(0xFFFFF4E0), fg: const Color(0xFF9A5B00)),
                  ],
                ]),
              ],
            ),
            const SizedBox(height: Space.sm),
            if (error != null) Text(error!, style: const TextStyle(color: AppColors.danger)),
            if (places.isEmpty && error == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: Text('Tidak ada fasilitas kategori ini di lantai ini.',
                    style: t.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
              ),
            for (final p in places)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(Space.sm, Space.xs, Space.xs, Space.xs),
                  radius: Radii.md,
                  color: AppColors.surfaceContainerLow,
                  border: Colors.transparent,
                  onTap: () => onTap(p),
                  child: Row(children: [
                    FacilityThumb(place: p, color: AppColors.secondary, size: 44),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p['label']?.toString() ?? '',
                            style: t.labelMedium?.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${kindLabel(p['kind']?.toString())} • ${floorShort(p['floor'])}',
                            style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
                      ]),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.std)),
                      ),
                      onPressed: () => onRoute(p),
                      icon: const Icon(Icons.navigation_outlined, size: 16),
                      label: const Text('Rute', style: TextStyle(fontSize: 14)),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: Space.sm),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: onAskAi,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Tanya AI: rute sesuai kebutuhanmu'),
            ),
          ],
        ),
      ),
    );
  }
}
