import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RuntimeConfig {
  const RuntimeConfig({
    required this.siteName,
    required this.menuSource,
    required this.trilliumUrl,
    required this.trilliumTitle,
  });

  static const RuntimeConfig fallback = RuntimeConfig(
    siteName: "UniqueDing's Kitchen",
    menuSource: 'local',
    trilliumUrl: '',
    trilliumTitle: '',
  );

  static const RuntimeConfig webStrictFallback = RuntimeConfig(
    siteName: "UniqueDing's Kitchen",
    menuSource: 'local',
    trilliumUrl: '',
    trilliumTitle: '',
  );

  final String siteName;
  final String menuSource;
  final String trilliumUrl;
  final String trilliumTitle;

  static Future<RuntimeConfig> load() async {
    if (!kIsWeb) {
      return fallback;
    }

    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final scopedPrefix = _scopedPrefix(Uri.base);
      final key = scopedPrefix.isNotEmpty
          ? '$scopedPrefix/public/runtime_config.json?v=$stamp'
          : 'public/runtime_config.json?v=$stamp';
      final resolved = Uri.base.resolve(key);
      final response = await http
          .get(resolved, headers: const {'cache-control': 'no-cache'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return webStrictFallback;
      }

      final source = utf8.decode(response.bodyBytes, allowMalformed: true);
      final json = jsonDecode(source);
      if (json is Map<String, dynamic>) {
        final siteName =
            (json['site_name'] as String?)?.trim().isNotEmpty == true
            ? (json['site_name'] as String).trim()
            : fallback.siteName;

        final url = (json['TRILLIUM_URL'] as String?)?.trim() ?? '';
        final sourceValue = (json['MENU_SOURCE'] as String?)?.trim();
        final sourceName = (sourceValue?.isNotEmpty ?? false)
            ? (sourceValue == 'markdown' ? 'local' : sourceValue!)
            : (url.isNotEmpty ? 'trillium' : webStrictFallback.menuSource);
        final title = (json['TRILLIUM_TITLE'] as String?)?.trim() ?? '';

        return RuntimeConfig(
          siteName: siteName,
          menuSource: sourceName,
          trilliumUrl: url,
          trilliumTitle: title,
        );
      }
    } catch (_) {
      return webStrictFallback;
    }

    return webStrictFallback;
  }

  static String _scopedPrefix(Uri base) {
    if (base.pathSegments.isEmpty) {
      return '';
    }
    final first = base.pathSegments.first.trim();
    if (first.isEmpty) {
      return '';
    }
    return '/$first';
  }
}
