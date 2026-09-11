import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rider mobility preferences. Stored locally (browser storage) and sent to
/// the backend as the `preferences` object on every route request — this is
/// the only thing the Profil screen edits, so what it shows is what routing
/// uses. Nothing here is a placeholder.
class UserPrefs extends ChangeNotifier {
  UserPrefs._();
  static final instance = UserPrefs._();

  /// 'wheelchair' | 'luggage' | 'general'
  String mobility = 'general';
  bool avoidStairs = false;
  bool stepFree = false;
  double? maxWalkM;

  static const _kMobility = 'prefs.mobility', _kAvoid = 'prefs.avoid_stairs', _kStep = 'prefs.step_free', _kWalk = 'prefs.max_walk_m';

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      mobility = sp.getString(_kMobility) ?? mobility;
      avoidStairs = sp.getBool(_kAvoid) ?? avoidStairs;
      stepFree = sp.getBool(_kStep) ?? stepFree;
      maxWalkM = sp.getDouble(_kWalk);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> update({String? mobility, bool? avoidStairs, bool? stepFree, double? maxWalkM, bool clearWalk = false}) async {
    if (mobility != null) {
      this.mobility = mobility;
      // Mobility profile sets the hard constraints; user can still toggle them.
      if (mobility == 'wheelchair') { this.stepFree = true; this.avoidStairs = true; }
      if (mobility == 'luggage') { this.avoidStairs = true; }
      if (mobility == 'general') { this.stepFree = false; this.avoidStairs = false; }
    }
    if (avoidStairs != null) this.avoidStairs = avoidStairs;
    if (stepFree != null) this.stepFree = stepFree;
    if (maxWalkM != null) this.maxWalkM = maxWalkM;
    if (clearWalk) this.maxWalkM = null;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kMobility, this.mobility);
      await sp.setBool(_kAvoid, this.avoidStairs);
      await sp.setBool(_kStep, this.stepFree);
      if (this.maxWalkM == null) { await sp.remove(_kWalk); } else { await sp.setDouble(_kWalk, this.maxWalkM!); }
    } catch (_) {}
  }

  /// Backend `Preferences` fields (schemas.py). Only hard constraints and the
  /// walk budget; priorities stay at the balanced default unless a screen
  /// overrides them.
  Map<String, dynamic> toRequest() => {
        'avoid_stairs': avoidStairs,
        'step_free': stepFree,
        if (stepFree) 'preferred_access': 'elevator',
        if (maxWalkM != null) 'max_walk_m': maxWalkM,
      };

  String get mobilityLabel => switch (mobility) {
        'wheelchair' => 'Kursi Roda',
        'luggage' => 'Bawa Koper',
        _ => 'Umum / Cepat',
      };
}
