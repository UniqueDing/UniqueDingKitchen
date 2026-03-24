import 'package:unique_ding_kitchen/models/models.dart';

class MarkdownMenuParser {
  static final RegExp _listSeparator = RegExp(r'[，,]');
  static final RegExp _tableSeparatorCell = RegExp(r'^:?-{3,}:?$');

  List<Dish> parse(String source) {
    final dishes = <Dish>[];
    String? currentCategory;
    var dishIndex = 0;

    final lines = source.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final lineNumber = i + 1;
      final rawLine = lines[i].trim();

      if (rawLine.isEmpty) {
        continue;
      }

      if (rawLine.startsWith('## ')) {
        currentCategory = rawLine.substring(3).trim();
        continue;
      }

      if (rawLine.startsWith('|')) {
        if (currentCategory == null) {
          throw FormatException(
            'Line $lineNumber must belong to a category declared with ##.',
          );
        }

        final cells = _splitTableCells(rawLine);
        if (cells.isEmpty || _isTableSeparatorRow(cells)) {
          continue;
        }
        if (_isTableHeaderRow(cells)) {
          continue;
        }

        _appendDish(
          dishes: dishes,
          category: currentCategory,
          lineNumber: lineNumber,
          parts: cells,
          dishIndex: ++dishIndex,
        );
        continue;
      }

      if (!rawLine.startsWith('- ')) {
        continue;
      }

      if (currentCategory == null) {
        throw FormatException(
          'Line $lineNumber must belong to a category declared with ##.',
        );
      }

      final content = rawLine.substring(2).trim();
      final parts = content.split('|').map((part) => part.trim()).toList();

      if (parts.isEmpty || parts[0].isEmpty) {
        throw FormatException(
          'Line $lineNumber must follow "- 名称 | 描述 | 口味(，分隔) | 小料(，分隔)" format.',
        );
      }

      _appendDish(
        dishes: dishes,
        category: currentCategory,
        lineNumber: lineNumber,
        parts: parts,
        dishIndex: ++dishIndex,
      );
    }

    if (dishes.isEmpty) {
      throw const FormatException('No dishes were found in assets/menu.md.');
    }

    return dishes;
  }

  List<String> _splitOptions(String source) {
    return source
        .split(_listSeparator)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<String> _splitTableCells(String line) {
    var content = line.trim();
    if (content.startsWith('|')) {
      content = content.substring(1);
    }
    if (content.endsWith('|')) {
      content = content.substring(0, content.length - 1);
    }
    return content.split('|').map((item) => item.trim()).toList();
  }

  bool _isTableSeparatorRow(List<String> cells) {
    if (cells.isEmpty) {
      return false;
    }
    return cells.every(
      (cell) => cell.isNotEmpty && _tableSeparatorCell.hasMatch(cell),
    );
  }

  bool _isTableHeaderRow(List<String> cells) {
    if (cells.isEmpty) {
      return false;
    }
    final normalized = cells.map((cell) => cell.replaceAll(' ', '')).toList();
    if (!normalized.any((cell) => cell == '名称' || cell == '菜名')) {
      return false;
    }
    return normalized.any((cell) => cell == '描述') ||
        normalized.any((cell) => cell == '口味') ||
        normalized.any((cell) => cell == '小料');
  }

  void _appendDish({
    required List<Dish> dishes,
    required String category,
    required int lineNumber,
    required List<String> parts,
    required int dishIndex,
  }) {
    if (parts.isEmpty || parts[0].isEmpty) {
      throw FormatException('Line $lineNumber must include dish name.');
    }

    final description = parts.length > 1 ? parts[1] : '';
    final flavors = parts.length > 2
        ? _splitOptions(parts[2])
        : const <String>[];
    final toppings = parts.length > 3
        ? _splitOptions(parts[3])
        : const <String>[];

    dishes.add(
      Dish(
        id: '$category-${parts[0]}-$dishIndex',
        category: category,
        name: parts[0],
        description: description,
        flavors: flavors,
        toppings: toppings,
      ),
    );
  }
}
