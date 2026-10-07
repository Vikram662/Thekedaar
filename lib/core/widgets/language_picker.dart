import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

/// Always shown in both languages, so it can be found whichever is on.
const _languageTitle = 'Language / भाषा';

/// Settings row that shows the current language and opens the picker.
class LanguageTile extends StatelessWidget {
  const LanguageTile({super.key, this.closeDrawer = false});

  /// Pops the drawer before the picker opens.
  final bool closeDrawer;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.translate),
      title: const Text(_languageTitle),
      subtitle: Text(appLanguage.value.nativeName),
      trailing: closeDrawer ? null : const Icon(Icons.chevron_right),
      onTap: () {
        final navigator = Navigator.of(context);
        if (closeDrawer) navigator.pop();
        showLanguagePicker(navigator.context);
      },
    );
  }
}

/// Dialog listing every language; the app switches as soon as one is tapped.
Future<void> showLanguagePicker(BuildContext context) async {
  final chosen = await showDialog<AppLanguage>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text(_languageTitle),
      children: [
        for (final language in AppLanguage.values)
          ListTile(
            leading: Icon(
              language == appLanguage.value
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(language.nativeName),
            subtitle: language.nativeName == language.englishName
                ? null
                : Text(language.englishName),
            onTap: () => Navigator.of(context).pop(language),
          ),
      ],
    ),
  );
  if (chosen != null && chosen != appLanguage.value) {
    await setAppLanguage(chosen);
  }
}

/// Compact English | हिंदी switch for the first screens (onboarding).
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AppLanguage>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final language in AppLanguage.values)
          ButtonSegment(value: language, label: Text(language.nativeName)),
      ],
      selected: {appLanguage.value},
      onSelectionChanged: (s) => setAppLanguage(s.first),
    );
  }
}
