import 'package:unique_ding_kitchen/models/models.dart';

class CartItem {
  const CartItem({
    required this.cartKey,
    required this.dish,
    required this.quantity,
    this.flavor = '',
    this.toppings = const <String>[],
  });

  final String cartKey;
  final Dish dish;
  final int quantity;
  final String flavor;
  final List<String> toppings;
}
