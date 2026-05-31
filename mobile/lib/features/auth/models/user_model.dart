class UserModel {
  final int id;
  final String username;
  final String displayName;
  final String role;
  final int cycleStartDay;
  final String email;
  UserModel({required this.id, required this.username, required this.displayName, required this.role, this.cycleStartDay = 1, this.email = ''});
  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] as int, username: json['username'] as String,
    displayName: json['display_name'] as String, role: json['role'] as String,
    cycleStartDay: (json['cycle_start_day'] as int?) ?? 1,
    email: (json['email'] as String?) ?? '',
  );
  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'display_name': displayName, 'role': role, 'cycle_start_day': cycleStartDay, 'email': email};
}