import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';

import 'strings_hi.dart';

/// Languages the app UI can show. English is the source text; other
/// languages look it up in their string table and fall back to English.
enum AppLanguage {
  en('English', 'English'),
  hi('हिंदी', 'Hindi');

  const AppLanguage(this.nativeName, this.englishName);

  /// Name shown in the language picker, in the language itself.
  final String nativeName;
  final String englishName;

  Locale get locale => Locale(name);

  /// intl locale used for dates and other UI formatting.
  String get intlLocale => name;
}

/// The current UI language. A per-phone preference (not part of the
/// business data or backups), so it is chosen even before onboarding.
final appLanguage = ValueNotifier<AppLanguage>(AppLanguage.en);

const _fileName = 'language';

Future<File> _file() async =>
    File('${(await getApplicationSupportDirectory()).path}/$_fileName');

/// Loads the saved language. Call once in `main` before `runApp`.
Future<void> loadAppLanguage() async {
  try {
    await initializeDateFormatting('hi');
  } catch (_) {
    // Dates fall back to English names.
  }
  try {
    final file = await _file();
    if (!await file.exists()) return;
    final saved = (await file.readAsString()).trim();
    appLanguage.value = AppLanguage.values.firstWhere(
      (l) => l.name == saved,
      orElse: () => AppLanguage.en,
    );
  } catch (_) {
    // Unreadable preference: keep English.
  }
}

Future<void> setAppLanguage(AppLanguage language) async {
  appLanguage.value = language;
  try {
    await (await _file()).writeAsString(language.name);
  } catch (_) {
    // Applies for this session only.
  }
}

/// Translates [text] (the English source string) into the current language.
///
/// Placeholders like `{name}` are replaced from [args] after translation, so
/// word order can differ between languages:
/// `tr('Paid {amount} to {name}', {'amount': '₹500', 'name': 'Ramesh'})`.
String tr(String text, [Map<String, Object?> args = const {}]) {
  var result = switch (appLanguage.value) {
    AppLanguage.en => text,
    AppLanguage.hi => hindiStrings[text] ?? text,
  };
  for (final entry in args.entries) {
    result = result.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return result;
}

/// Picks the singular or plural English form, then translates it.
/// [count] is available to both forms as `{count}`.
String trPlural(
  int count,
  String one,
  String many, [
  Map<String, Object?> args = const {},
]) =>
    tr(count == 1 ? one : many, {'count': count, ...args});

/// One-letter weekday headers, Monday first, for calendar grids.
List<String> get weekdayLetters => switch (appLanguage.value) {
      AppLanguage.en => const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
      AppLanguage.hi => const ['सो', 'मं', 'बु', 'गु', 'शु', 'श', 'र'],
    };

/// The intl locale for dates shown in the UI. PDFs always use English.
String get uiDateLocale => appLanguage.value.intlLocale;

/// Rebuilds every widget below [context], including `const` ones, so text
/// read through [tr] updates right after the language changes.
void rebuildAllWidgets(BuildContext context) {
  void rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}
