import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thekedaar/core/backup/clock_check.dart';
import 'package:thekedaar/core/i18n/i18n.dart';
import 'package:thekedaar/core/i18n/strings_hi.dart';

void main() {
  tearDown(() => appLanguage.value = AppLanguage.en);

  test('English returns the source text with placeholders filled', () {
    expect(tr('Workers'), 'Workers');
    expect(tr('{name} added', {'name': 'Ramesh'}), 'Ramesh added');
    expect(trPlural(1, '1 day', '{count} days'), '1 day');
    expect(trPlural(3, '1 day', '{count} days'), '3 days');
  });

  test('Hindi translates, fills placeholders and falls back to English', () {
    appLanguage.value = AppLanguage.hi;
    expect(tr('Workers'), 'मज़दूर');
    expect(tr('{name} added', {'name': 'Ramesh'}), 'Ramesh जोड़ा गया');
    expect(tr('Not a translated string'), 'Not a translated string');
    expect(describeClockSkew(const Duration(hours: 2)), '2 घंटे पीछे');
  });

  testWidgets('rebuildAllWidgets redraws const widgets in the new language',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Label()));
    expect(find.text('Workers'), findsOneWidget);

    appLanguage.value = AppLanguage.hi;
    rebuildAllWidgets(tester.element(find.byType(MaterialApp)));
    await tester.pump();
    expect(find.text('मज़दूर'), findsOneWidget);
  });

  test('every Hindi string keeps the same placeholders', () {
    final placeholder = RegExp(r'\{\w+\}');
    Set<String> names(String s) =>
        placeholder.allMatches(s).map((m) => m.group(0)!).toSet();
    for (final entry in hindiStrings.entries) {
      expect(names(entry.value), names(entry.key), reason: entry.key);
    }
  });
}

class _Label extends StatelessWidget {
  const _Label();

  @override
  Widget build(BuildContext context) => Text(tr('Workers'));
}
