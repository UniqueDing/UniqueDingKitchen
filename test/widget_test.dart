// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:unique_ding_kitchen/app.dart';
import 'package:unique_ding_kitchen/models/models.dart';
import 'package:unique_ding_kitchen/services/menu_repository.dart';

class _FakeRepository implements MenuRepository {
  @override
  Future<List<Dish>> loadMenu() async {
    return const [
      Dish(
        id: '热菜-宫保鸡丁-1',
        category: '热菜',
        name: '宫保鸡丁',
        description: '微辣可选',
        flavors: ['清淡', '微辣', '重辣'],
        toppings: ['葱花', '蒜蓉'],
      ),
      Dish(id: '主食-米饭-2', category: '主食', name: '米饭', description: ''),
    ];
  }
}

void main() {
  testWidgets('loads menu and generates copyable order text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(HomeDiningApp(repository: _FakeRepository()));
    await tester.pumpAndSettle();

    final withDescription = tester.widget<Column>(
      find.byKey(const Key('dish-content-热菜-宫保鸡丁-1')),
    );
    final withoutDescription = tester.widget<Column>(
      find.byKey(const Key('dish-content-主食-米饭-2')),
    );
    expect(withDescription.mainAxisAlignment, MainAxisAlignment.start);
    expect(withoutDescription.mainAxisAlignment, MainAxisAlignment.center);

    expect(find.text('宫保鸡丁'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('add-热菜-宫保鸡丁-1')));
    await tester.tap(find.byKey(const Key('add-热菜-宫保鸡丁-1')));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('add-热菜-宫保鸡丁-1')));
    await tester.tap(find.byKey(const Key('add-热菜-宫保鸡丁-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sheet-flavor-微辣')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sheet-topping-蒜蓉')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save-options')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('category-主食')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('add-主食-米饭-2')));
    await tester.tap(find.byKey(const Key('add-主食-米饭-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('generate-order-text')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('summary-note-input')), '少盐');
    await tester.tap(find.byKey(const Key('summary-copy')));
    await tester.pumpAndSettle();

    expect(find.text('点单确认'), findsOneWidget);
    expect(find.text('已点菜单'), findsOneWidget);
    expect(find.byKey(const Key('summary-add-more')), findsOneWidget);
    expect(find.byKey(const Key('summary-copy')), findsOneWidget);
    expect(find.byKey(const Key('summary-note-input')), findsOneWidget);
  });
}
