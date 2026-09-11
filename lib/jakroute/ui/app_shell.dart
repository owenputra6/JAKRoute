import 'package:flutter/material.dart';

import '../api_client.dart';
import '../route_screen.dart';
import 'app_theme.dart';
import 'chat_screen.dart';

/// Bottom-nav shell: AI chat (primary, chatbot rubric) + advanced form
/// (existing route_screen.dart — sliders/switches for power users, kept as-is
/// since it is already wired and tested against the real backend).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api, required this.mapStyleUrl});

  final JakRouteApi api;
  final String mapStyleUrl;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ChatScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl),
      JakRouteScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.surfaceContainerLowest,
        indicatorColor: AppColors.secondaryContainer.withValues(alpha: 0.18),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Asisten AI'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Rute Lanjutan'),
        ],
      ),
    );
  }
}
