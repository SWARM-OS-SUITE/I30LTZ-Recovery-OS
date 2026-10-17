import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i30ltz_ide/ide/mad_ai_panel.dart';
import 'package:i30ltz_ide/theme/swarm_colors.dart';

void main() {
  testWidgets('MAD AI panel renders its empty state and works offline-safe', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(backgroundColor: SwarmColors.bg, body: MadAiPanel())),
    ));
    await tester.pump();
    expect(find.textContaining('MAD AI'), findsWidgets);
    expect(find.textContaining('nothing runs or changes without your click'), findsOneWidget);
  });
}
