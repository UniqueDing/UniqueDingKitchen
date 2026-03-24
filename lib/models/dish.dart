class Dish {
  const Dish({
    required this.id,
    required this.category,
    required this.name,
    required this.description,
    this.flavors = const <String>[],
    this.toppings = const <String>[],
  });

  final String id;
  final String category;
  final String name;
  final String description;
  final List<String> flavors;
  final List<String> toppings;
}
