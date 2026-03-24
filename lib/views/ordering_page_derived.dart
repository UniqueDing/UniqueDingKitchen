import 'package:unique_ding_kitchen/models/models.dart';

class MenuListEntry {
  const MenuListEntry._({this.category, this.dish});

  const MenuListEntry.header(String category)
    : this._(category: category, dish: null);

  const MenuListEntry.dish(Dish dish) : this._(category: null, dish: dish);

  final String? category;
  final Dish? dish;
}

class OrderingDerivedState {
  const OrderingDerivedState({
    required this.categories,
    required this.groupedByCategory,
    required this.menuEntries,
  });

  final List<String> categories;
  final Map<String, List<Dish>> groupedByCategory;
  final List<MenuListEntry> menuEntries;
}

class OrderingPageDeriver {
  const OrderingPageDeriver._();

  static OrderingDerivedState derive(
    List<Dish> dishes, {
    required String recommendationCategory,
  }) {
    final seen = <String>{};
    final categories = <String>[];
    final grouped = <String, List<Dish>>{};

    for (final dish in dishes) {
      if (seen.add(dish.category)) {
        categories.add(dish.category);
      }
      grouped.putIfAbsent(dish.category, () => <Dish>[]).add(dish);
    }

    if (categories.remove(recommendationCategory)) {
      categories.insert(0, recommendationCategory);
    }

    final entries = <MenuListEntry>[];
    for (final category in categories) {
      entries.add(MenuListEntry.header(category));
      final categoryDishes = grouped[category] ?? const <Dish>[];
      for (final dish in categoryDishes) {
        entries.add(MenuListEntry.dish(dish));
      }
    }

    return OrderingDerivedState(
      categories: categories,
      groupedByCategory: grouped,
      menuEntries: entries,
    );
  }

  static List<MapEntry<String, List<CartItem>>> groupCartItemsByCategory(
    List<CartItem> items,
  ) {
    final grouped = <String, List<CartItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.dish.category, () => <CartItem>[]).add(item);
    }
    return grouped.entries.toList();
  }
}
