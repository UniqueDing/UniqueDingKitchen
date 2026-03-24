import 'package:flutter_test/flutter_test.dart';
import 'package:unique_ding_kitchen/services/markdown_menu_parser.dart';

void main() {
  test('parses category based markdown menu', () {
    const source = '''
## 热菜
- 宫保鸡丁 | 微辣可选 | 清淡，微辣，重辣 | 葱花，蒜蓉

## 主食
- 米饭 | 单份
''';

    final dishes = MarkdownMenuParser().parse(source);

    expect(dishes, hasLength(2));
    expect(dishes.first.category, '热菜');
    expect(dishes.first.name, '宫保鸡丁');
    expect(dishes.first.description, '微辣可选');
    expect(dishes.first.flavors, <String>['清淡', '微辣', '重辣']);
    expect(dishes.first.toppings, <String>['葱花', '蒜蓉']);
    expect(dishes.last.category, '主食');
    expect(dishes.last.flavors, isEmpty);
  });

  test('throws when a dish appears before category heading', () {
    const source = '- 宫保鸡丁 | 微辣可选';

    expect(
      () => MarkdownMenuParser().parse(source),
      throwsA(isA<FormatException>()),
    );
  });

  test('parses markdown table menu format', () {
    const source = '''
## 热菜
| 名称 | 描述 | 口味 | 小料 |
| --- | --- | --- | --- |
| 宫保鸡丁 | 酸甜微辣 | 清淡，微辣，重辣 | 葱花，蒜蓉 |
| 梅子排骨 | 开胃 |  |  |

## 主食
| 菜名 | 描述 |
| --- | --- |
| 米饭 | 单份 |
''';

    final dishes = MarkdownMenuParser().parse(source);

    expect(dishes, hasLength(3));
    expect(dishes[0].name, '宫保鸡丁');
    expect(dishes[0].description, '酸甜微辣');
    expect(dishes[0].flavors, <String>['清淡', '微辣', '重辣']);
    expect(dishes[0].toppings, <String>['葱花', '蒜蓉']);
    expect(dishes[1].name, '梅子排骨');
    expect(dishes[1].flavors, isEmpty);
    expect(dishes[2].category, '主食');
    expect(dishes[2].name, '米饭');
  });

  test('supports mixed list and table format in one category', () {
    const source = '''
## 火锅
- 清汤锅底 | 2-3人轻松开锅 | 浓汤，清淡 | 蒜蓉，麻酱
| 名称 | 描述 | 口味 | 小料 |
| --- | --- | --- | --- |
| 手切羊肉拼盘 | 鲜嫩 | 清淡，重辣 | 麻酱，香菜 |
''';

    final dishes = MarkdownMenuParser().parse(source);

    expect(dishes, hasLength(2));
    expect(dishes[0].name, '清汤锅底');
    expect(dishes[1].name, '手切羊肉拼盘');
  });

  test('parses table rows with missing optional columns', () {
    const source = '''
## 主食
| 名称 | 描述 |
| --- | --- |
| 米饭 | 单份 |
| 葱油拌面 | 香而不腻 |
''';

    final dishes = MarkdownMenuParser().parse(source);

    expect(dishes, hasLength(2));
    expect(dishes[0].name, '米饭');
    expect(dishes[0].description, '单份');
    expect(dishes[0].flavors, isEmpty);
    expect(dishes[0].toppings, isEmpty);
    expect(dishes[1].name, '葱油拌面');
  });

  test('splits both Chinese and ASCII commas in options', () {
    const source = '''
## 火锅
| 名称 | 描述 | 口味 | 小料 |
| --- | --- | --- | --- |
| 番茄锅底 | 酸甜柔和 | 清淡,微辣，重辣 | 蒜蓉, 麻酱，香菜 |
''';

    final dishes = MarkdownMenuParser().parse(source);

    expect(dishes, hasLength(1));
    expect(dishes.first.flavors, <String>['清淡', '微辣', '重辣']);
    expect(dishes.first.toppings, <String>['蒜蓉', '麻酱', '香菜']);
  });

  test('throws when a table row appears before category heading', () {
    const source = '| 名称 | 描述 |\n| --- | --- |\n| 米饭 | 单份 |';

    expect(
      () => MarkdownMenuParser().parse(source),
      throwsA(isA<FormatException>()),
    );
  });
}
