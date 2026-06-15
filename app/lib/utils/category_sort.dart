import 'package:totals/models/category.dart';

int compareCategoriesAlphabetically(Category a, Category b) {
  final nameCompare =
      a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase());
  if (nameCompare != 0) return nameCompare;

  final flowCompare = a.flow.toLowerCase().compareTo(b.flow.toLowerCase());
  if (flowCompare != 0) return flowCompare;

  return (a.id ?? 0).compareTo(b.id ?? 0);
}

List<Category> sortCategoriesAlphabetically(Iterable<Category> categories) {
  return List<Category>.from(categories)..sort(compareCategoriesAlphabetically);
}
