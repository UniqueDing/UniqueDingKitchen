import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:unique_ding_kitchen/models/models.dart';
import 'package:unique_ding_kitchen/services/markdown_menu_parser.dart';
import 'package:unique_ding_kitchen/services/menu_repository.dart';

const String recommendationCategoryKey = '__recommendation__';

class OrderingPageData {
  const OrderingPageData({
    required this.dishes,
    required this.recommendationLoadNote,
  });

  final List<Dish> dishes;
  final String recommendationLoadNote;
}

class _RecommendationLoadResult {
  const _RecommendationLoadResult({
    required this.dishes,
    required this.loadNote,
  });

  final List<Dish> dishes;
  final String loadNote;
}

class OrderingDataLoader {
  OrderingDataLoader({
    required this.repository,
    MarkdownMenuParser? markdownMenuParser,
  }) : _markdownMenuParser = markdownMenuParser ?? MarkdownMenuParser();

  final MenuRepository repository;
  final MarkdownMenuParser _markdownMenuParser;

  Future<OrderingPageData> loadPageData() async {
    final menuFuture = repository.loadMenu().timeout(
      const Duration(seconds: 12),
    );
    final recommendationFuture = _loadRecommendationDishes();

    final menuDishes = await menuFuture;
    final recommendation = await recommendationFuture;

    return OrderingPageData(
      dishes: <Dish>[...recommendation.dishes, ...menuDishes],
      recommendationLoadNote: recommendation.loadNote,
    );
  }

  Future<_RecommendationLoadResult> _loadRecommendationDishes() async {
    try {
      final recommendationSource = await _loadRecommendationSource();
      final parsed = _parseRecommendationMarkdown(recommendationSource);
      final dishes = parsed
          .map(
            (dish) => Dish(
              id: 'rec-${dish.id}',
              category: recommendationCategoryKey,
              name: dish.name,
              description: dish.description,
              flavors: dish.flavors,
              toppings: dish.toppings,
            ),
          )
          .toList();
      return _RecommendationLoadResult(dishes: dishes, loadNote: '');
    } catch (error) {
      final details = error.toString();
      final loadNote = details.length > 220
          ? '${details.substring(0, 220)}...'
          : details;
      return _RecommendationLoadResult(
        dishes: const <Dish>[],
        loadNote: loadNote,
      );
    }
  }

  Future<String> _loadRecommendationSource() async {
    final errors = <String>[];
    if (kIsWeb) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final scopedPrefix = _scopedPrefix(Uri.base);
      final key = scopedPrefix.isNotEmpty
          ? '$scopedPrefix/public/recommend.md'
          : 'public/recommend.md';
      try {
        final resolved = Uri.base.resolve('$key?v=$stamp');
        final response = await http
            .get(resolved, headers: const {'cache-control': 'no-cache'})
            .timeout(const Duration(seconds: 6));

        if (response.statusCode != 200) {
          errors.add('$key -> status ${response.statusCode}');
        } else {
          final loaded = utf8.decode(response.bodyBytes, allowMalformed: true);
          if (_isUsableRecommendationMarkdown(loaded)) {
            return loaded;
          }
          errors.add('$key -> unusable content');
        }
      } catch (error) {
        errors.add('$key -> ${error.runtimeType}');
      }
    }

    throw FormatException(
      'Recommendation load failed; sample: ${errors.take(4).join(' | ')}',
    );
  }

  String _scopedPrefix(Uri base) {
    if (base.pathSegments.isEmpty) {
      return '';
    }
    final first = base.pathSegments.first.trim();
    if (first.isEmpty) {
      return '';
    }
    return '/$first';
  }

  bool _isUsableRecommendationMarkdown(String value) {
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

  List<Dish> _parseRecommendationMarkdown(String source) {
    try {
      return _markdownMenuParser.parse(source);
    } catch (_) {
      final dishes = <Dish>[];
      var index = 0;
      final lines = source.split(RegExp(r'\r?\n'));
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('## ')) {
          continue;
        }

        final listPrefix = RegExp(r'^([-*]|\d+[\.)])\s+');
        if (!listPrefix.hasMatch(line)) {
          continue;
        }

        final item = line.replaceFirst(listPrefix, '');
        final parts = item.split('|').map((part) => part.trim()).toList();
        if (parts.length < 2) {
          continue;
        }

        final name = parts[0];
        final description = parts[1];
        final flavors = parts.length > 2
            ? parts[2]
                  .split(RegExp(r'[、,/]'))
                  .map((part) => part.trim())
                  .where((part) => part.isNotEmpty)
                  .toList()
            : const <String>[];
        final toppings = parts.length > 3
            ? parts[3]
                  .split(RegExp(r'[、,/]'))
                  .map((part) => part.trim())
                  .where((part) => part.isNotEmpty)
                  .toList()
            : const <String>[];

        dishes.add(
          Dish(
            id: 'rec-${index++}',
            category: recommendationCategoryKey,
            name: name,
            description: description,
            flavors: flavors,
            toppings: toppings,
          ),
        );
      }
      return dishes;
    }
  }
}
