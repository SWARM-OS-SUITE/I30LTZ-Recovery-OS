// I30LTZ IDE: entry point. Standalone app, no SWARM backend, works fully offline.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ide/i30ltz_ide.dart';
import 'theme/swarm_colors.dart';
import 'theme/swarm_text_styles.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: I30ltzIdeApp()));
}

class I30ltzIdeApp extends StatelessWidget {
  const I30ltzIdeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'I30LTZ IDE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: SwarmColors.bg,
        fontFamily: 'Lato',
        colorScheme: const ColorScheme.dark(
          primary: SwarmColors.accent,
          secondary: SwarmColors.agentCyan,
          surface: SwarmColors.bgSurface,
          error: SwarmColors.statusCritical,
        ),
        textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'Lato',
              bodyColor: SwarmColors.textPrimary,
              displayColor: SwarmColors.textPrimary,
            ),
        dividerColor: SwarmColors.border,
        tooltipTheme: TooltipThemeData(
          textStyle: SwarmTextStyles.codeSmall.copyWith(color: SwarmColors.textPrimary),
          decoration: BoxDecoration(color: SwarmColors.bgElevated, borderRadius: BorderRadius.circular(4)),
        ),
      ),
      home: const Scaffold(body: I30ltzIde()),
    );
  }
}
