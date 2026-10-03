import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/app/theme.dart';
import 'package:thekedaar/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  testWidgets('onboarding: Continue needs a name and a trade', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const OnboardingScreen(),
        ),
      ),
    );

    FilledButton continueButton() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Continue'),
        );

    expect(find.text('Electrical'), findsOneWidget);
    expect(continueButton().onPressed, isNull);

    await tester.enterText(find.byType(TextFormField).first, 'Sharma Works');
    await tester.pump();
    expect(continueButton().onPressed, isNull);

    await tester.tap(find.text('Plumbing'));
    await tester.pump();
    expect(continueButton().onPressed, isNotNull);

    await tester.tap(find.text('Plumbing'));
    await tester.pump();
    expect(continueButton().onPressed, isNull);
  });
}
