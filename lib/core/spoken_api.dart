import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'http/http_platform.dart';
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.status = 0, this.code = -1});

  final String message;
  final int status;
  final int code;

  @override
  String toString() => message;
}

class SpokenApi {
  SpokenApi._(this._dio);

  static const _apiPrefix = '/api/v1';

  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  final Dio _dio;

  static Future<SpokenApi> create({String baseUrl = defaultBaseUrl}) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl.replaceFirst(RegExp(r'/$'), ''),
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        headers: const <String, String>{'Accept': 'application/json'},
      ),
    );
    await configurePlatformHttp(dio);
    return SpokenApi._(dio);
  }

  Future<AccountBootstrap> bootstrap() async {
    final json = await _requestJson('POST', '$_apiPrefix/account/bootstrap',
        timeout: const Duration(seconds: 15));
    return AccountBootstrap.fromJson(json);
  }

  Future<SpokenLibrary> currentSeasonTests() async => SpokenLibrary.fromJson(
        await _requestJson(
            'GET', '$_apiPrefix/test_and_question/current_season_tests',
            retryQueries: true),
      );

  Future<SpokenLibrary> cambridgeTests() async => SpokenLibrary.fromJson(
        await _requestJson(
            'GET', '$_apiPrefix/test_and_question/cambridge_tests',
            retryQueries: true),
      );

  Future<SpokenQuestions> questions(int testId, {int? part}) async {
    final json = await _requestJson(
      'GET',
      '$_apiPrefix/test_and_question/tests/$testId/questions',
      queryParameters: part == null ? null : <String, Object>{'part': part},
      retryQueries: true,
    );
    return SpokenQuestions.fromJson(json);
  }

  Future<AssessmentResult> assess({
    required Uint8List wav,
    required int questionId,
    int? recordId,
  }) async {
    final form = FormData.fromMap(<String, dynamic>{
      'audio': MultipartFile.fromBytes(
        wav,
        filename: 'ielts-recording.wav',
        contentType: DioMediaType.parse('audio/wav'),
      ),
      'questionId': questionId,
      if (recordId != null) 'recordId': recordId,
    });
    final json = await _requestJson(
      'POST',
      '$_apiPrefix/pronunciation/ielts_assessment',
      data: form,
      timeout: const Duration(seconds: 180),
    );
    return AssessmentResult.fromJson(json);
  }

  Future<AiEvaluation> aiEvaluation(int detailId) async {
    final json = await _requestJson(
      'POST',
      '$_apiPrefix/pronunciation/ai_eval',
      data: <String, Object>{'detailId': detailId},
      contentType: Headers.formUrlEncodedContentType,
      timeout: const Duration(seconds: 150),
    );
    return AiEvaluation.fromJson(json);
  }

  Future<void> submitFeedback({
    required int detailId,
    required String content,
  }) async {
    await _requestJson(
      'POST',
      '$_apiPrefix/feedback',
      data: <String, Object>{
        'detailId': detailId,
        'content': content.trim(),
      },
      contentType: Headers.jsonContentType,
    );
  }

  Future<String> aiSpoken(int detailId) async {
    try {
      final response = await _dio.post<Object?>(
        '$_apiPrefix/pronunciation/ai_spoken',
        data: <String, Object>{'detailId': detailId},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          receiveTimeout: const Duration(seconds: 75),
        ),
      );
      final payload = asJsonMap(response.data);
      final code = asInt(payload['code'], -1);
      if (code != 0) {
        throw ApiException(
          asString(payload['message'], 'AI 标准发音生成失败'),
          status: response.statusCode ?? 200,
          code: code,
        );
      }
      final audioUrl = asString(payload['data']).trim();
      if (audioUrl.isEmpty) throw const ApiException('音频地址为空');
      return audioUrl;
    } on DioException catch (error) {
      throw _mapDioException(error, 'AI 标准发音生成失败');
    }
  }

  Future<RecordPage> records({int? cursorId, int pageSize = 20}) async {
    final json = await _requestJson(
      'GET',
      '$_apiPrefix/assessment_record/list',
      queryParameters: <String, Object>{
        'pageSize': pageSize,
        if (cursorId != null) 'cursorId': cursorId,
      },
      retryQueries: true,
    );
    return RecordPage.fromJson(json);
  }

  Future<RecordDetails> recordDetails(int recordId) async =>
      RecordDetails.fromJson(
        await _requestJson(
          'GET',
          '$_apiPrefix/assessment_record/$recordId/details',
          retryQueries: true,
        ),
      );

  Future<JsonMap> _requestJson(
    String method,
    String path, {
    Object? data,
    Map<String, Object>? queryParameters,
    Duration? timeout,
    String? contentType,
    bool retryQueries = false,
  }) async {
    final attempts = retryQueries ? 3 : 1;
    DioException? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response = await _dio.request<Object?>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: Options(
            method: method,
            contentType: contentType,
            receiveTimeout: timeout,
            sendTimeout: timeout,
          ),
        );
        return _unwrap(response.data, response.statusCode ?? 200);
      } on DioException catch (error) {
        lastError = error;
        if (attempt + 1 >= attempts || !_isRetryable(error)) break;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw _mapDioException(lastError!, '网络连接不可用');
  }

  JsonMap _unwrap(Object? body, int status) {
    final payload = asJsonMap(body);
    final code = asInt(payload['code'], -1);
    if (code != 0) {
      throw ApiException(
        asString(payload['message'], '服务返回了无效结果'),
        status: status,
        code: code,
      );
    }
    return asJsonMap(payload['data']);
  }

  bool _isRetryable(DioException error) {
    final status = error.response?.statusCode ?? 0;
    return status >= 500 ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }

  ApiException _mapDioException(DioException error, String fallback) {
    final status = error.response?.statusCode ?? 0;
    final payload = asJsonMap(error.response?.data);
    final message = asString(payload['message']);
    if (message.isNotEmpty) {
      return ApiException(message,
          status: status, code: asInt(payload['code'], -1));
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return ApiException('请求超时，请稍后重试', status: status);
    }
    return ApiException(error.message ?? fallback, status: status);
  }
}
