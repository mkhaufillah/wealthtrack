class CategoryBrief {
  final int id; final String name; final String nameEn; final String icon;
  CategoryBrief({required this.id, required this.name, required this.nameEn, required this.icon});
  factory CategoryBrief.fromJson(Map<String, dynamic> json) => CategoryBrief(
    id: json['id'] as int, name: json['name'] as String, nameEn: json['name_en'] as String? ?? '', icon: json['icon'] as String? ?? '',
  );
}

class UserBrief {
  final int id; final String displayName;
  UserBrief({required this.id, required this.displayName});
  factory UserBrief.fromJson(Map<String, dynamic> json) => UserBrief(
    id: json['id'] as int, displayName: json['display_name'] as String? ?? '',
  );
}

class TransactionModel {
  final int id; final int amount; final String type; final String description;
  final String note; final String date; final CategoryBrief category;
  final UserBrief? user;
  TransactionModel({required this.id, required this.amount, required this.type,
    required this.description, required this.note, required this.date, required this.category,
    this.user});

  factory TransactionModel.fromJson(Map<String, dynamic> json) => TransactionModel(
    id: json['id'] as int, amount: json['amount'] as int,
    type: json['type'] as String, description: json['description'] as String? ?? '',
    note: json['note'] as String? ?? '', date: json['date'] as String? ?? '',
    category: CategoryBrief.fromJson(json['category']),
    user: json['user'] != null ? UserBrief.fromJson(json['user']) : null,
  );
}