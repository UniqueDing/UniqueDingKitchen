class TrilliumMenuParser {
  String? extractMarkdownFromHtml(String html, {required String articleTitle}) {
    var snippet = html;
    final title = articleTitle.trim();

    final headingMatches = <String>[
      '<h1 id="$title"',
      '<h1 id="${_slugify(title)}"',
      '>$title<',
    ];
    if (title.isNotEmpty) {
      for (final marker in headingMatches) {
        final start = snippet.indexOf(marker);
        if (start >= 0) {
          snippet = snippet.substring(start);
          break;
        }
      }
    }

    final h2Regex = RegExp(r'<h2[^>]*>(.*?)<a[^>]*>', dotAll: true);
    final h2Matches = h2Regex.allMatches(snippet).toList();
    if (h2Matches.isEmpty) {
      return null;
    }

    final buffer = StringBuffer();
    for (var i = 0; i < h2Matches.length; i++) {
      final match = h2Matches[i];
      final rawHeading = match.group(1) ?? '';
      final heading = _decodeHtml(_stripTags(rawHeading));
      if (heading.isEmpty) {
        continue;
      }

      final sectionStart = match.end;
      final sectionEnd = i + 1 < h2Matches.length
          ? h2Matches[i + 1].start
          : snippet.length;
      final chunk = snippet.substring(sectionStart, sectionEnd);

      final rows = <List<String>>[];
      final trRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
      for (final tr in trRegex.allMatches(chunk)) {
        final rowHtml = tr.group(1) ?? '';
        final cellRegex = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true);
        final cells = cellRegex
            .allMatches(rowHtml)
            .map((m) => _decodeHtml(_stripTags(m.group(1) ?? '')))
            .toList();
        if (cells.isEmpty) {
          continue;
        }
        if (_isHeaderRow(cells)) {
          continue;
        }
        if (cells.first.isEmpty) {
          continue;
        }
        while (cells.length < 4) {
          cells.add('');
        }
        rows.add(cells.take(4).toList());
      }

      if (rows.isEmpty) {
        continue;
      }

      buffer.writeln('## $heading');
      buffer.writeln('| 名称 | 描述 | 口味 | 小料 |');
      buffer.writeln('| --- | --- | --- | --- |');
      for (final row in rows) {
        buffer.writeln('| ${row[0]} | ${row[1]} | ${row[2]} | ${row[3]} |');
      }
      buffer.writeln();
    }

    final output = buffer.toString().trim();
    return output.isEmpty ? null : output;
  }

  bool _isHeaderRow(List<String> cells) {
    final normalized = cells
        .map((cell) => cell.replaceAll(' ', '').trim().toLowerCase())
        .toList();
    return normalized.contains('名称') ||
        normalized.contains('菜名') ||
        normalized.contains('description') ||
        normalized.contains('口味');
  }

  String _decodeHtml(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('\u00a0', ' ')
        .trim();
  }

  String _stripTags(String value) {
    return value.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  }

  String _slugify(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }
}
