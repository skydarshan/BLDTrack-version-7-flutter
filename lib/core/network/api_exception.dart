import 'package:dio/dio.dart';

import '../config/api_config.dart';

class ApiException implements Exception {
  ApiException({
    required this.message,
    this.statusCode,
    this.errors = const [],
  });

  final String message;
  final int? statusCode;
  final List<dynamic> errors;

  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    final data = response?.data;

    if (data is Map<String, dynamic>) {
      final message = data['message']?.toString();
      final errors = _readErrorList(data);
      return ApiException(
        message: (message != null && message.isNotEmpty)
            ? message
            : _fallbackMessage(error),
        statusCode: response?.statusCode,
        errors: errors,
      );
    }

    return ApiException(
      message: _fallbackMessage(error),
      statusCode: response?.statusCode,
    );
  }

  static List<dynamic> _readErrorList(Map<String, dynamic> data) {
    if (data['errors'] is List) return data['errors'] as List;
    if (data['details'] is List) return data['details'] as List;
    return const [];
  }

  /// Joi / API validation details (`errors` or `details` array).
  List<dynamic> get fieldErrors => errors;

  static String _fallbackMessage(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please try again.';
      case DioExceptionType.connectionError:
        if (ApiConfig.isLikelyWebCorsIssue) {
          return 'Cannot reach the live API from Chrome (CORS).\n'
              'Run: ./scripts/run_live_web.sh\n'
              '(proxy → https://api.bldtrack.ai)';
        }
        return 'Unable to connect to the server. Check your network and API URL.';
      case DioExceptionType.badResponse:
        return 'Something went wrong (${error.response?.statusCode ?? 'error'}).';
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      default:
        return error.message ?? 'Unexpected error occurred.';
    }
  }

  @override
  String toString() => message;
}
