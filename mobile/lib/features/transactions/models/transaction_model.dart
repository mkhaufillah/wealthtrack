class CategoryBrief {
  final int id; final String name; final String icon;
  CategoryBrief({required this.id, required this.name, required this.icon});
  factory CategoryBrief.fromJson(Map<String, dynamic> json) => CategoryBrief(
    id: json['id'] as int, name: json['name'] as String, icon: json['icon'] as String? ?? '',
  );
}

class TransactionModel {
  final int id; final int amount; final String type; final String description;
  final String note; final String date; final CategoryBrief category;
  TransactionModel({required this.id, required this.amount, required this.type,
    required this.description, required this.note, required this.date, required this.category});

  factory TransactionModel.fromJson(Map<String, dynamic> json) => TransactionModel(
    id: json['id'] as int, amount: json['amount'] as int,
    type: json['type'] as String, description: json['description'] as String? ?? '',
    note: json['note'] as String? ?? '', date: json['date'] as String? ?? '',
    category: CategoryBrief.fromJson(json['category']),
  );
}