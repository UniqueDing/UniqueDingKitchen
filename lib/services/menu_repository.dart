import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:unique_ding_kitchen/models/models.dart';
import 'package:unique_ding_kitchen/services/markdown_menu_parser.dart';
import 'package:unique_ding_kitchen/services/trillium_menu_parser.dart';

abstract class MenuRepository {
  Future<List<Dish>> loadMenu();
}

class AssetMenuRepository implements MenuRepository {
  AssetMenuRepository({
    MarkdownMenuParser? parser,
    this.publicPath = 'public/menu.md',
    this.webPath = 'menu.md',
    this.menuSource = 'local',
    this.trilliumUrl = '',
    this.trilliumTitle = '',
  }) : _parser = parser ?? MarkdownMenuParser();

  final MarkdownMenuParser _parser;
  final TrilliumMenuParser _trilliumParser = TrilliumMenuParser();
  final String publicPath;
  final String webPath;
  final String menuSource;
  final String trilliumUrl;
  final String trilliumTitle;

  @override
  Future<List<Dish>> loadMenu() async {
    if (kIsWeb && menuSource.trim().toLowerCase() == 'trillium') {
      final dishes = await _loadFromTrilliumHtml();
      if (dishes.isEmpty) {
        throw StateError('Trillium source returned empty menu.');
      }
      return dishes;
    }

    if (kIsWeb) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final candidates = <String>[
        '$publicPath?v=$stamp',
        '/$publicPath?v=$stamp',
        '$webPath?v=$stamp',
        '/$webPath?v=$stamp',
      ];

      for (final key in candidates) {
        try {
          final resolved = Uri.base.resolve(key);
          final response = await http
              .get(resolved, headers: const {'cache-control': 'no-cache'})
              .timeout(const Duration(seconds: 4));
          if (response.statusCode != 200) {
            continue;
          }
          final loaded = utf8.decode(response.bodyBytes, allowMalformed: true);
          if (_isUsableMarkdown(loaded)) {
            return _parser.parse(loaded);
          }
        } catch (_) {
          continue;
        }
      }
    }
    return _parser.parse(_fallbackMenuMarkdown);
  }

  Future<List<Dish>> _loadFromTrilliumHtml() async {
    final url = trilliumUrl.trim();
    if (url.isEmpty) {
      throw StateError(
        'Trillium URL is empty. Set TRILLIUM_URL when MENU_SOURCE=trillium.',
      );
    }

    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      throw StateError('Invalid TRILLIUM_URL: $url');
    }

    final uri = parsed.hasScheme
        ? parsed
        : (kIsWeb ? Uri.base.resolve(url) : parsed);

    if (!(uri.hasScheme && uri.hasAuthority)) {
      throw StateError(
        'Invalid TRILLIUM_URL after resolve: $url -> ${uri.toString()}',
      );
    }

    try {
      final response = await http
          .get(uri, headers: const {'cache-control': 'no-cache'})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        throw StateError(
          'Trillium request failed with HTTP ${response.statusCode}: $url',
        );
      }

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final markdown = _trilliumParser.extractMarkdownFromHtml(
        html,
        articleTitle: trilliumTitle,
      );
      if (markdown == null || markdown.trim().isEmpty) {
        throw StateError(
          'Failed to extract menu from Trillium HTML. Check TRILLIUM_TITLE and page structure.',
        );
      }

      return _parser.parse(markdown);
    } on StateError {
      rethrow;
    } catch (error) {
      throw StateError('Failed to load menu from Trillium: $error');
    }
  }

  bool _isUsableMarkdown(String value) {
    final text = value.trimLeft();
    if (text.isEmpty) {
      return false;
    }
    final lower = text.toLowerCase();
    if (lower.startsWith('<!doctype html') || lower.startsWith('<html')) {
      return false;
    }
    return true;
  }

  static const String _fallbackMenuMarkdown = '''
## 菜单加载提示
| 名称 | 描述 | 口味 | 小料 |
| --- | --- | --- | --- |
| 菜单加载失败 | 请检查 public/menu.md 的路径与格式（必须先有 ## 分类，再有 markdown 表格行） |  |  |
''';
}
