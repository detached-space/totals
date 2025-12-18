class Category {
  final int? id;
  final String name;
  final bool essential;
  final String? iconKey;
  final String? description;
  final String flow; // 'expense' | 'income'
  final bool recurring;
  final bool builtIn;
  final String? builtInKey;

  const Category({
    this.id,
    required this.name,
    required this.essential,
    this.iconKey,
    this.description,
    this.flow = 'expense',
    this.recurring = false,
    this.builtIn = false,
    this.builtInKey,
  });

  factory Category.fromDb(Map<String, dynamic> row) {
    final rawFlow = (row['flow'] as String?)?.trim().toLowerCase();
    return Category(
      id: row['id'] as int?,
      name: (row['name'] as String?) ?? '',
      essential: (row['essential'] as int? ?? 0) == 1,
      iconKey: row['iconKey'] as String?,
      description: row['description'] as String?,
      flow: rawFlow == 'income' ? 'income' : 'expense',
      recurring: (row['recurring'] as int? ?? 0) == 1,
      builtIn: (row['builtIn'] as int? ?? 0) == 1,
      builtInKey: row['builtInKey'] as String?,
    );
  }

  Map<String, dynamic> toDb() {
    return {
      'id': id,
      'name': name,
      'essential': essential ? 1 : 0,
      'iconKey': iconKey,
      'description': description,
      'flow': flow,
      'recurring': recurring ? 1 : 0,
      'builtIn': builtIn ? 1 : 0,
      'builtInKey': builtInKey,
    };
  }

  Category copyWith({
    int? id,
    String? name,
    bool? essential,
    String? iconKey,
    String? description,
    String? flow,
    bool? recurring,
    bool? builtIn,
    String? builtInKey,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      essential: essential ?? this.essential,
      iconKey: iconKey ?? this.iconKey,
      description: description ?? this.description,
      flow: flow ?? this.flow,
      recurring: recurring ?? this.recurring,
      builtIn: builtIn ?? this.builtIn,
      builtInKey: builtInKey ?? this.builtInKey,
    );
  }
}

class BuiltInCategories {
  static const List<Category> all = [
    Category(
      name: 'Salary',
      essential: true,
      iconKey: 'payments',
      description: 'Income from salary or wages',
      flow: 'income',
      recurring: true,
      builtIn: true,
      builtInKey: 'income_salary',
    ),
    Category(
      name: 'Business',
      essential: true,
      iconKey: 'payments',
      description: 'Income from a business or shop',
      flow: 'income',
      recurring: true,
      builtIn: true,
      builtInKey: 'income_business',
    ),
    Category(
      name: 'Side hustle',
      essential: false,
      iconKey: 'payments',
      description: 'Income from side jobs or freelance work',
      flow: 'income',
      recurring: true,
      builtIn: true,
      builtInKey: 'income_side_hustle',
    ),
    Category(
      name: 'Bonus',
      essential: false,
      iconKey: 'payments',
      description: 'Bonus, commission, or performance pay',
      flow: 'income',
      recurring: false,
      builtIn: true,
      builtInKey: 'income_bonus',
    ),
    Category(
      name: 'Refund',
      essential: false,
      iconKey: 'payments',
      description: 'Refunds and reimbursements',
      flow: 'income',
      recurring: false,
      builtIn: true,
      builtInKey: 'income_refund',
    ),
    Category(
      name: 'Gifts given',
      essential: false,
      iconKey: 'gift',
      description: 'Gifts you give to others',
      flow: 'expense',
      recurring: false,
      builtIn: true,
      builtInKey: 'expense_gifts_given',
    ),
    Category(
      name: 'Gifts received',
      essential: false,
      iconKey: 'gift',
      description: 'Gifts you receive from others',
      flow: 'income',
      recurring: false,
      builtIn: true,
      builtInKey: 'income_gifts_received',
    ),
    Category(
      name: 'Misc',
      essential: false,
      iconKey: 'more_horiz',
      description: 'Other income that doesn’t fit other categories',
      flow: 'income',
      recurring: false,
      builtIn: true,
      builtInKey: 'income_misc',
    ),
    Category(
      name: 'Rent',
      essential: true,
      iconKey: 'home',
      description: 'Housing rent and lease payments',
      flow: 'expense',
      recurring: true,
      builtIn: true,
      builtInKey: 'expense_rent',
    ),
    Category(
      name: 'Utilities',
      essential: true,
      iconKey: 'bolt',
      description: 'Electricity, water, internet, and bills',
      flow: 'expense',
      recurring: true,
      builtIn: true,
      builtInKey: 'expense_utilities',
    ),
    Category(
      name: 'Groceries',
      essential: true,
      iconKey: 'shopping_cart',
      description: 'Food and household essentials',
      flow: 'expense',
      recurring: false,
      builtIn: true,
      builtInKey: 'expense_groceries',
    ),
    Category(
      name: 'Transport',
      essential: true,
      iconKey: 'directions_car',
      description: 'Taxi, fuel, fares, and transport',
      flow: 'expense',
      recurring: false,
      builtIn: true,
      builtInKey: 'expense_transport',
    ),
    Category(
      name: 'Eating outside',
      essential: false,
      iconKey: 'restaurant',
      description: 'Restaurants, cafes, and takeaway',
      flow: 'expense',
      recurring: false,
      builtIn: true,
      builtInKey: 'expense_eating_outside',
    ),
    Category(
      name: 'Clothing',
      essential: false,
      iconKey: 'checkroom',
      description: 'Clothes, shoes, and accessories',
      flow: 'expense',
      recurring: false,
      builtIn: true,
      builtInKey: 'expense_clothing',
    ),
    Category(
      name: 'Health',
      essential: true,
      iconKey: 'health',
      description: 'Medical, pharmacy, and health spending',
      flow: 'expense',
      recurring: false,
      builtIn: true,
      builtInKey: 'expense_health',
    ),
    Category(
      name: 'Airtime',
      essential: true,
      iconKey: 'phone',
      description: 'Mobile airtime and data bundles',
      flow: 'expense',
      recurring: true,
      builtIn: true,
      builtInKey: 'expense_airtime',
    ),
    Category(
      name: 'Loan',
      essential: true,
      iconKey: 'request_quote',
      description: 'Loan payments and interest',
      flow: 'expense',
      recurring: true,
      builtIn: true,
      builtInKey: 'expense_loan',
    ),
    Category(
      name: 'Beauty',
      essential: false,
      iconKey: 'spa',
      description: 'Salon, grooming, and personal care',
      flow: 'expense',
      recurring: false,
      builtIn: true,
      builtInKey: 'expense_beauty',
    ),
    Category(
      name: 'Misc',
      essential: false,
      iconKey: 'more_horiz',
      description: 'Anything that doesn’t fit other categories',
      flow: 'expense',
      recurring: false,
      builtIn: true,
      builtInKey: 'expense_misc',
    ),
  ];
}
