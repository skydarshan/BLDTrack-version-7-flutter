import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../config/api_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

typedef UnauthorizedHandler = void Function();

/// Shared Dio client for `/api/v1` — same contract as the React app.
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    UnauthorizedHandler? onUnauthorized,
  })  : _tokenStorage = tokenStorage,
        _onUnauthorized = onUnauthorized {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.apiV1Base,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStorage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (options.data is FormData) {
            options.headers.remove('Content-Type');
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await _tokenStorage.clear();
            _onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  late final Dio _dio;
  final TokenStorage _tokenStorage;
  final UnauthorizedHandler? _onUnauthorized;

  Dio get dio => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _request(
      () => _dio.get<T>(path, queryParameters: queryParameters, options: options),
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _request(
      () => _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _request(
      () => _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
    );
  }

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _request(
      () => _dio.patch<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      ),
    );
  }

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) {
    return _request(
      () => _dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
      ),
    );
  }

  /// Multipart with JSON `data` plus named file fields (RR / DMR / RC / PO).
  Future<Response<T>> postNamedMultipart<T>(
    String path, {
    Map<String, dynamic>? payload,
    Map<String, MultipartFileEntry> namedFiles = const {},
    Map<String, dynamic>? fields,
    Map<String, dynamic>? queryParameters,
    bool put = false,
  }) {
    final form = FormData();
    if (payload != null) {
      form.fields.add(MapEntry('data', jsonEncode(payload)));
    }
    if (fields != null) {
      fields.forEach((k, v) {
        if (v != null) form.fields.add(MapEntry(k, v.toString()));
      });
    }
    namedFiles.forEach((name, file) {
      form.files.add(MapEntry(name, file.toMultipartFile()));
    });
    return _multipart<T>(
      () => put
          ? _dio.put<T>(path, data: form, queryParameters: queryParameters)
          : _dio.post<T>(path, data: form, queryParameters: queryParameters),
    );
  }

  /// PMS multipart: text field `data` (JSON) + repeated `files`.
  Future<Response<T>> postMultipart<T>(
    String path, {
    required Map<String, dynamic> payload,
    List<MultipartFileEntry> files = const [],
    Map<String, dynamic>? queryParameters,
  }) {
    return _multipart<T>(
      () => _dio.post<T>(
        path,
        data: _buildPmsFormData(payload, files),
        queryParameters: queryParameters,
      ),
    );
  }

  Future<Response<T>> putMultipart<T>(
    String path, {
    required Map<String, dynamic> payload,
    List<MultipartFileEntry> files = const [],
    Map<String, dynamic>? queryParameters,
  }) {
    return _multipart<T>(
      () => _dio.put<T>(
        path,
        data: _buildPmsFormData(payload, files),
        queryParameters: queryParameters,
      ),
    );
  }

  /// Excel import: field name `file` (singular).
  Future<Response<T>> postFileField<T>(
    String path, {
    required MultipartFileEntry file,
    String fieldName = 'file',
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? fields,
  }) {
    final form = FormData();
    if (fields != null) {
      fields.forEach((k, v) {
        if (v != null) form.fields.add(MapEntry(k, v.toString()));
      });
    }
    form.files.add(MapEntry(fieldName, file.toMultipartFile()));
    return _multipart<T>(
      () => _dio.post<T>(path, data: form, queryParameters: queryParameters),
    );
  }

  Future<List<int>> downloadBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        queryParameters: queryParameters,
        options: Options(responseType: ResponseType.bytes),
      );
      return res.data ?? <int>[];
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  FormData _buildPmsFormData(
    Map<String, dynamic> payload,
    List<MultipartFileEntry> files,
  ) {
    final form = FormData();
    form.fields.add(MapEntry('data', jsonEncode(payload)));
    for (final f in files) {
      form.files.add(MapEntry('files', f.toMultipartFile()));
    }
    return form;
  }

  Future<Response<T>> _multipart<T>(Future<Response<T>> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Response<T>> _request<T>(Future<Response<T>> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

class MultipartFileEntry {
  MultipartFileEntry({
    required this.bytes,
    required this.filename,
    this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String? contentType;

  MultipartFile toMultipartFile() {
    MediaType? mediaType;
    if (contentType != null && contentType!.contains('/')) {
      final parts = contentType!.split('/');
      mediaType = MediaType(parts[0], parts.sublist(1).join('/'));
    } else {
      final ext = p.extension(filename).toLowerCase();
      mediaType = switch (ext) {
        '.png' => MediaType('image', 'png'),
        '.jpg' || '.jpeg' => MediaType('image', 'jpeg'),
        '.gif' => MediaType('image', 'gif'),
        '.webp' => MediaType('image', 'webp'),
        '.mp4' => MediaType('video', 'mp4'),
        '.mov' => MediaType('video', 'quicktime'),
        '.pdf' => MediaType('application', 'pdf'),
        '.xlsx' => MediaType(
            'application',
            'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        '.xls' => MediaType('application', 'vnd.ms-excel'),
        _ => MediaType('application', 'octet-stream'),
      };
    }
    return MultipartFile.fromBytes(
      bytes,
      filename: filename,
      contentType: mediaType,
    );
  }
}
