import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../i18n/i18n.dart';

class AppUpdateChecker {
  const AppUpdateChecker();

  Future<void> check(BuildContext context) async {
    if (!AppConfig.subscriptionConfigured) return;
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.subscriptionApiUrl}/v1/app-config'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || !context.mounted) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = data['latestBuild'] as int? ?? 0;
      if (AppConfig.appBuildNumber >= latest) return;
      final minimum = data['minimumBuild'] as int? ?? 0;
      final url = Uri.tryParse(data['updateUrl'] as String? ?? '');
      if (url == null || !context.mounted) return;
      await _show(
        context,
        url: url,
        message: data['message'] as String? ?? tr('A new version is available.'),
        required: AppConfig.appBuildNumber < minimum,
      );
    } catch (_) {
      // Update checks must never prevent normal offline app startup.
    }
  }

  Future<void> _show(BuildContext context,
      {required Uri url,
      required String message,
      required bool required}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !required,
      builder: (dialogContext) => PopScope(
        canPop: !required,
        child: AlertDialog(
          icon: const Icon(Icons.system_update, size: 42),
          title: Text(required ? tr('Update required') : tr('Update available')),
          content: Text(message),
          actions: [
            if (!required)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('Later')),
              ),
            FilledButton.icon(
              onPressed: () async {
                await launchUrl(url, mode: LaunchMode.externalApplication);
                if (!required && dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              icon: const Icon(Icons.download),
              label: Text(tr('Update now')),
            ),
          ],
        ),
      ),
    );
  }
}
