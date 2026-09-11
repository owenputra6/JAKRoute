import 'package:flutter/material.dart';

import '../api_client.dart';
import 'chat_screen.dart';
import 'facility_list_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

/// Bottom-nav shell (revised UI UX mockups): Peta / Tanya AI / Fasilitas /
/// Profil. The AI chat is a first-class tab — it is the app's core
/// differentiator. The advanced route planner (route_screen.dart) is reached
/// from the Peta search pill's directions button.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api, required this.mapStyleUrl});

  final JakRouteApi api;
  final String mapStyleUrl;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _goProfile() => setState(() => _index = 3);
  void _goChat() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl, onAvatarTap: _goProfile, onAskAi: _goChat),
      ChatScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl, embedded: true, onAvatarTap: _goProfile),
      FacilityListScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl, onAvatarTap: _goProfile),
      ProfileScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Peta'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Tanya AI'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Fasilitas'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
