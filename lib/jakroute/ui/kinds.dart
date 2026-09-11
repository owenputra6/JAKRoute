import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Real `kind` values from GET /catalog (set by the Supabase loader from the
/// surveyed label). Only reorganizes what the backend returns — no invented
/// categories.
IconData iconForKind(String? kind) => switch (kind) {
      'toilet' => Icons.wc,
      'mushola' => Icons.mosque,
      'elevator' => Icons.elevator,
      'escalator' => Icons.escalator,
      'stairs' => Icons.stairs,
      'vending_machine' => Icons.local_cafe,
      'first_aid' => Icons.medical_services,
      'lactation_room' => Icons.child_friendly,
      'entrance' => Icons.door_sliding,
      'ticket_gate' => Icons.sensor_door,
      'shop' => Icons.storefront,
      'atm' => Icons.local_atm,
      'seating' => Icons.chair,
      'amenity' => Icons.category,
      'food' => Icons.restaurant,
      'bus_stop' => Icons.directions_bus,
      'minimarket' => Icons.local_grocery_store,
      'pharmacy' => Icons.local_pharmacy,
      _ => Icons.place,
    };

String kindLabel(String? kind) => switch (kind) {
      'toilet' => 'Toilet',
      'mushola' => 'Mushola',
      'elevator' => 'Lift',
      'escalator' => 'Eskalator',
      'stairs' => 'Tangga',
      'vending_machine' => 'Vending Machine',
      'first_aid' => 'P3K',
      'lactation_room' => 'Ruang Laktasi',
      'entrance' => 'Pintu Masuk',
      'ticket_gate' => 'Gerbang Tap',
      'shop' => 'Toko / Kios',
      'atm' => 'ATM',
      'seating' => 'Tempat Duduk',
      'amenity' => 'Perlengkapan',
      'food' => 'Kuliner',
      'bus_stop' => 'Halte Bus',
      'minimarket' => 'Minimarket',
      'pharmacy' => 'Apotek',
      _ => kind ?? 'Lainnya',
    };

String groupForKind(String? kind) => switch (kind) {
      'elevator' || 'escalator' || 'stairs' => 'Aksesibilitas',
      'toilet' || 'mushola' || 'vending_machine' || 'first_aid' || 'lactation_room' => 'Fasilitas Umum',
      'entrance' || 'ticket_gate' => 'Akses Masuk',
      'shop' || 'atm' => 'Komersial',
      'food' || 'bus_stop' || 'minimarket' || 'pharmacy' => 'Sekitar Stasiun',
      _ => 'Lainnya',
    };

/// Floor label from the catalog's `floors` list (backend-supplied), e.g.
/// "Lantai 2 — Hall". Falls back to the bare number.
String floorLabel(Map catalog, Object? floorId) {
  if (floorId == null) return 'Luar stasiun (OpenStreetMap)';
  final floors = (catalog['floors'] as List? ?? []).cast<Map>();
  final match = floors.where((f) => f['id'] == floorId);
  return match.isEmpty ? 'Lantai $floorId' : (match.first['label']?.toString() ?? 'Lantai $floorId');
}

/// Short badge form: "LT 2".
String floorShort(Object? floorId) => floorId == null ? 'Luar' : 'LT $floorId';

bool isOutdoor(Map place) => place['scope'] == 'outdoor';

Color groupColor(String group) => switch (group) {
      'Aksesibilitas' => AppColors.secondary,
      'Fasilitas Umum' => AppColors.success,
      'Akses Masuk' => AppColors.tertiaryFixedDim,
      'Komersial' => AppColors.warning,
      'Sekitar Stasiun' => const Color(0xFFC77716),
      _ => AppColors.outline,
    };
