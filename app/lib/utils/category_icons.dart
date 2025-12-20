import 'package:flutter/material.dart';

class CategoryIconOption {
  final String key;
  final IconData icon;
  final String label;

  const CategoryIconOption({
    required this.key,
    required this.icon,
    required this.label,
  });
}

const List<CategoryIconOption> categoryIconOptions = [
  CategoryIconOption(key: 'payments', icon: Icons.payments_rounded, label: 'Salary'),
  CategoryIconOption(key: 'gift', icon: Icons.card_giftcard_rounded, label: 'Gifts'),
  CategoryIconOption(key: 'home', icon: Icons.home_rounded, label: 'Rent'),
  CategoryIconOption(key: 'bolt', icon: Icons.bolt_rounded, label: 'Utilities'),
  CategoryIconOption(key: 'shopping_cart', icon: Icons.shopping_cart_rounded, label: 'Groceries'),
  CategoryIconOption(key: 'directions_car', icon: Icons.directions_car_rounded, label: 'Transport'),
  CategoryIconOption(key: 'restaurant', icon: Icons.restaurant_rounded, label: 'Eating out'),
  CategoryIconOption(key: 'checkroom', icon: Icons.checkroom_rounded, label: 'Clothing'),
  CategoryIconOption(key: 'health', icon: Icons.health_and_safety_rounded, label: 'Health'),
  CategoryIconOption(key: 'phone', icon: Icons.phone_android_rounded, label: 'Airtime'),
  CategoryIconOption(key: 'request_quote', icon: Icons.request_quote_rounded, label: 'Loan'),
  CategoryIconOption(key: 'spa', icon: Icons.spa_rounded, label: 'Beauty'),
  CategoryIconOption(key: 'more_horiz', icon: Icons.more_horiz_rounded, label: 'Misc'),
];

IconData iconForCategoryKey(String? iconKey) {
  switch (iconKey) {
    case 'payments':
      return Icons.payments_rounded;
    case 'gift':
      return Icons.card_giftcard_rounded;
    case 'home':
      return Icons.home_rounded;
    case 'bolt':
      return Icons.bolt_rounded;
    case 'shopping_cart':
      return Icons.shopping_cart_rounded;
    case 'directions_car':
      return Icons.directions_car_rounded;
    case 'restaurant':
      return Icons.restaurant_rounded;
    case 'checkroom':
      return Icons.checkroom_rounded;
    case 'health':
      return Icons.health_and_safety_rounded;
    case 'phone':
      return Icons.phone_android_rounded;
    case 'request_quote':
      return Icons.request_quote_rounded;
    case 'spa':
      return Icons.spa_rounded;
    case 'more_horiz':
      return Icons.more_horiz_rounded;
    default:
      return Icons.category_rounded;
  }
}
