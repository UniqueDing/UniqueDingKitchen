import 'package:unique_ding_kitchen/models/models.dart';

class OrderConfirmation {
  const OrderConfirmation({
    required this.items,
    required this.note,
    required this.orderText,
  });

  final List<CartItem> items;
  final String note;
  final String orderText;
}
