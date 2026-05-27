class UserModel {
  final int id;
  final String username;
  final String displayName;
  final String role;
  UserModel({required this.id, required this.username, required this.displayName, required this.role});
  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] as int, username: json['username'] as String,
    displayName: json['display_name'] as String, role: json['role'] as String,
  );
  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'display_name': displayName, 'role': role};
}