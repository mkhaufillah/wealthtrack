class TokenModel {
  final String accessToken; final String tokenType; final int expiresIn;
  TokenModel({required this.accessToken, required this.tokenType, required this.expiresIn});
  factory TokenModel.fromJson(Map<String, dynamic> json) => TokenModel(
    accessToken: json['access_token'] as String,
    tokenType: json['token_type'] as String,
    expiresIn: json['expires_in'] as int,
  );
}