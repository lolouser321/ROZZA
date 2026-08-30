import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/rozza_theme.dart';
import '../../playback/playback_controller.dart';
import '../../widgets/mini_player.dart';
import '../home/home_screen.dart';
import '../library/library_screen.dart';
import '../search/search_screen.dart';

class RozzaShell extends StatefulWidget {
  const RozzaShell({super.key, required this.playback});

  final PlaybackController playback;

  @override
  State<RozzaShell> createState() => _RozzaShellState();
}

class _RozzaShellState extends State<RozzaShell> {
  int index = 0;
  late final PageController pageController = PageController();

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  void select(int value) {
    HapticFeedback.selectionClick();
    setState(() => index = value);
    pageController.animateToPage(
      value,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: PageView(
            controller: pageController,
            onPageChanged: (value) => setState(() => index = value),
            children: [
              HomeScreen(playback: widget.playback),
              SearchScreen(playback: widget.playback),
              LibraryScreen(playback: widget.playback),
            ],
          ),
        ),
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: ColoredBox(
            color: RozzaColors.ink.withValues(alpha: .82),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MiniPlayer(playback: widget.playback),
                  NavigationBar(
                    height: 66,
                    selectedIndex: index,
                    onDestinationSelected: select,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.search_rounded),
                        selectedIcon: Icon(Icons.manage_search_rounded),
                        label: 'Search',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.library_music_outlined),
                        selectedIcon: Icon(Icons.library_music_rounded),
                        label: 'Library',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
