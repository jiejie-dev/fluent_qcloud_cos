import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fluent_object_storage/fluent_object_storage.dart';
import 'package:fluent_qcloud_cos/utils.dart';
import 'package:platform_file/platform_file.dart';

/// Interceptor that returns mock responses from a queue in order.
class QueuedMockInterceptor extends Interceptor {
  final List<Response Function(RequestOptions)> _queue = [];
  final List<RequestOptions> capturedRequests = [];

  void enqueue(Response Function(RequestOptions) handler) {
    _queue.add(handler);
  }

  void enqueueResponse({
    int statusCode = 200,
    String? data,
    Map<String, List<String>>? headers,
  }) {
    _queue.add((opts) => Response(
          requestOptions: opts,
          statusCode: statusCode,
          data: data,
          headers: Headers.fromMap(headers ?? {}),
        ));
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    capturedRequests.add(options);
    if (_queue.isEmpty) {
      handler.reject(DioException(
        requestOptions: options,
        message: 'No more mock responses in queue',
      ));
      return;
    }
    final responseBuilder = _queue.removeAt(0);
    handler.resolve(responseBuilder(options));
  }
}

/// Creates a Dio instance with a queued mock interceptor.
/// Returns both the Dio instance and the interceptor for enqueuing responses.
({Dio dio, QueuedMockInterceptor mock}) createMockDio() {
  final interceptor = QueuedMockInterceptor();
  final dio = Dio();
  dio.interceptors.add(interceptor);
  return (dio: dio, mock: interceptor);
}

/// Installs a mock Dio and returns the interceptor for enqueuing responses.
/// Call [tearDownMockDio] in test tearDown to restore.
QueuedMockInterceptor setUpMockDio() {
  final result = createMockDio();
  cosCreateDio = () => result.dio;
  return result.mock;
}

/// Restores the default Dio factory.
void tearDownMockDio() {
  cosCreateDio = defaultCreateDio;
}

/// Creates a test PlatformFile with in-memory data.
PlatformFile createTestFile({
  String name = 'test.png',
  required int size,
  List<int>? bytes,
  Stream<List<int>>? readStream,
}) {
  final data = bytes ?? List.filled(size, 65);
  return PlatformFile(
    name: name,
    size: size,
    bytes: Uint8List.fromList(data),
    readStream: readStream ?? Stream.value(data),
  );
}

/// Creates a test PlatformFile that only has readStream (no bytes).
PlatformFile createStreamOnlyTestFile({
  String name = 'test.png',
  required int size,
}) {
  final data = List.filled(size, 65);
  return PlatformFile(
    name: name,
    size: size,
    readStream: Stream.value(data),
  );
}

/// Creates a test PlatformFile with neither bytes nor readStream.
PlatformFile createEmptySourceTestFile({
  String name = 'test.png',
  required int size,
}) {
  return PlatformFile(
    name: name,
    size: size,
  );
}

/// Helper to create a standard test request.
ObjectStoragePutObjectRequest createTestRequest({
  String taskId = 'test-task',
  PlatformFile? file,
  String bucketName = 'test-bucket',
  String objectName = 'test-object.png',
  String accessKeyId = 'test-ak',
  String accessKeySecret = 'test-sk',
  String securityToken = 'test-token',
  String region = 'ap-beijing',
  int? divisionForUpload,
  int? sliceSizeForUpload,
}) {
  file ??= createTestFile(name: objectName, size: 1024);
  return ObjectStoragePutObjectRequest(
    taskId: taskId,
    file: file,
    bucketName: bucketName,
    objectName: objectName,
    accessKeyId: accessKeyId,
    accessKeySecret: accessKeySecret,
    securityToken: securityToken,
    expiredTime:
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
    region: region,
    divisionForUpload: divisionForUpload ?? 2 * 1024 * 1024,
    sliceSizeForUpload: sliceSizeForUpload ?? 1024 * 1024,
  );
}
