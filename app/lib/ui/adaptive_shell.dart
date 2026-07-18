import 'package:flutter/material.dart';

typedef KiranaPageBuilder = Widget Function(BuildContext context);

class KiranaDestination {
  const KiranaDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final KiranaPageBuilder builder;
}

/// Adaptive navigation shell shared by mobile and browser layouts.
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({required this.destinations, super.key})
    : assert(destinations.length > 0);

  final List<KiranaDestination> destinations;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant AdaptiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.destinations.length) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.destinations[_selectedIndex];
    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail = constraints.maxWidth >= 840;
        final showBottomNavigation =
            !showRail && widget.destinations.length > 1;
        final page = destination.builder(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(destination.label),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    'KiranaGPT',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          body: showRail
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _selectDestination,
                      labelType: NavigationRailLabelType.all,
                      leading: const Padding(
                        padding: EdgeInsets.only(bottom: 18),
                        child: CircleAvatar(child: Icon(Icons.storefront)),
                      ),
                      destinations: widget.destinations
                          .map(
                            (item) => NavigationRailDestination(
                              icon: Icon(item.icon),
                              selectedIcon: Icon(item.selectedIcon),
                              label: Text(item.label),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: page),
                  ],
                )
              : page,
          bottomNavigationBar: !showBottomNavigation
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectDestination,
                  destinations: widget.destinations
                      .map(
                        (item) => NavigationDestination(
                          icon: Icon(item.icon),
                          selectedIcon: Icon(item.selectedIcon),
                          label: item.label,
                        ),
                      )
                      .toList(growable: false),
                ),
        );
      },
    );
  }

  void _selectDestination(int index) {
    setState(() => _selectedIndex = index);
  }
}
