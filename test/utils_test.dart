import 'package:dio/dio.dart';
import 'package:fluent_qcloud_cos/utils.dart';
import 'package:platform_file/platform_file.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'test_helpers.dart';

void main() {
  group('cosLog', () {
    test('does not throw when disabled', () {
      cosDebugLogEnabled = false;
      expect(() => cosLog('test message'), returnsNormally);
    });

    test('does not throw when enabled', () {
      cosDebugLogEnabled = true;
      expect(() => cosLog('test message'), returnsNormally);
      cosDebugLogEnabled = false;
    });
  });

  group('subElem', () {
    test('finds child element by name', () {
      final doc = XmlDocument.parse('<root><child>value</child></root>');
      final result = subElem(doc.rootElement, 'child');
      expect(result.innerText, 'value');
    });

    test('throws when child element not found', () {
      final doc = XmlDocument.parse('<root><child>value</child></root>');
      expect(() => subElem(doc.rootElement, 'missing'), throwsStateError);
    });

    test('throws when multiple elements with same name', () {
      final doc = XmlDocument.parse(
          '<root><child>a</child><child>b</child></root>');
      expect(() => subElem(doc.rootElement, 'child'), throwsStateError);
    });
  });

  group('hmacSha1', () {
    test('produces correct HMAC-SHA1 digest', () {
      final result = hmacSha1('hello', 'secret');
      expect(result, isNotEmpty);
      expect(result.length, 40);
    });

    test('same inputs produce same output', () {
      final a = hmacSha1('message', 'key');
      final b = hmacSha1('message', 'key');
      expect(a, equals(b));
    });

    test('different messages produce different output', () {
      final a = hmacSha1('message1', 'key');
      final b = hmacSha1('message2', 'key');
      expect(a, isNot(equals(b)));
    });

    test('different keys produce different output', () {
      final a = hmacSha1('message', 'key1');
      final b = hmacSha1('message', 'key2');
      expect(a, isNot(equals(b)));
    });

    test('handles empty message', () {
      final result = hmacSha1('', 'key');
      expect(result, isNotEmpty);
    });

    test('handles empty key', () {
      final result = hmacSha1('message', '');
      expect(result, isNotEmpty);
    });
  });

  group('getListAndParameters', () {
    test('handles empty map', () {
      final result = getListAndParameters({});
      expect(result[0], '');
      expect(result[1], '');
    });

    test('handles single entry', () {
      final result = getListAndParameters({'key': 'value'});
      expect(result[0], 'key');
      expect(result[1], 'key=value');
    });

    test('sorts keys alphabetically', () {
      final result = getListAndParameters({'b': '2', 'a': '1', 'c': '3'});
      expect(result[0], 'a;b;c');
      expect(result[1], 'a=1&b=2&c=3');
    });

    test('encodes special characters', () {
      final result = getListAndParameters({'key with space': 'val&ue'});
      expect(result[0], contains('key'));
      expect(result[1], contains('='));
    });

    test('handles null values', () {
      final result = getListAndParameters({'key': null});
      expect(result[0], 'key');
      expect(result[1], 'key=');
    });

    test('lowercases keys after encoding', () {
      final result = getListAndParameters({'Key': 'Value'});
      expect(result[0], contains('key'));
    });
  });

  group('filterHeaders', () {
    test('returns empty map for empty input', () {
      final result = filterHeaders({});
      expect(result, isEmpty);
    });

    test('keeps valid standard headers', () {
      final result = filterHeaders({
        'content-type': 'application/json',
        'content-length': '100',
        'host': 'example.com',
        'cache-control': 'no-cache',
        'content-disposition': 'attachment',
        'content-encoding': 'gzip',
        'content-md5': 'abc',
        'expires': 'Thu, 01 Dec 1994',
      });
      expect(result.length, 8);
    });

    test('keeps x-cos- prefixed headers', () {
      final result = filterHeaders({
        'x-cos-acl': 'public-read',
        'x-cos-grant-read': 'id="100000000001"',
      });
      expect(result.length, 2);
      expect(result['x-cos-acl'], 'public-read');
    });

    test('rejects non-cos x- headers', () {
      final result = filterHeaders({
        'x-forwarded-for': '127.0.0.1',
        'x-request-id': '12345',
        'x-amz-date': '2021-01-01',
      });
      expect(result, isEmpty);
    });

    test('filters out invalid headers', () {
      final result = filterHeaders({
        'accept': 'text/html',
        'user-agent': 'test',
        'custom-header': 'value',
      });
      expect(result, isEmpty);
    });

    test('skips content-length when value is "0"', () {
      final result = filterHeaders({'content-length': '0'});
      expect(result, isEmpty);
    });

    test('keeps content-length when value is non-zero', () {
      final result = filterHeaders({'content-length': '100'});
      expect(result.length, 1);
      expect(result['content-length'], '100');
    });

    test('handles case-insensitive header names', () {
      final result = filterHeaders({
        'Content-Type': 'text/plain',
        'CONTENT-LENGTH': '50',
        'Host': 'example.com',
      });
      expect(result.length, 3);
      expect(result['Content-Type'], 'text/plain');
    });

    test('handles mixed valid and invalid headers', () {
      final result = filterHeaders({
        'content-type': 'text/plain',
        'accept': 'text/html',
        'x-cos-meta-data': 'custom',
        'x-random-header': 'ignored',
      });
      expect(result.length, 2);
      expect(result.containsKey('content-type'), isTrue);
      expect(result.containsKey('x-cos-meta-data'), isTrue);
    });
  });

  group('getSign', () {
    final fixedTime = DateTime(2024, 1, 15, 12, 0, 0);

    test('returns empty string for anonymous mode', () {
      final result = getSign('GET', '/test',
          secretId: 'id', secretKey: 'key', anonymous: true);
      expect(result, '');
    });

    test('produces valid signature format', () {
      final result = getSign(
        'GET',
        '/test-object',
        secretId: 'AKIDxxxxxxxx',
        secretKey: 'secretxxxxxxxx',
        signTime: fixedTime,
      );
      expect(result, contains('q-sign-algorithm=sha1'));
      expect(result, contains('q-ak=AKIDxxxxxxxx'));
      expect(result, contains('q-sign-time='));
      expect(result, contains('q-key-time='));
      expect(result, contains('q-header-list='));
      expect(result, contains('q-url-param-list='));
      expect(result, contains('q-signature='));
    });

    test('includes params in signature', () {
      final result = getSign(
        'GET',
        '/test',
        secretId: 'id',
        secretKey: 'key',
        params: {'prefix': 'test/', 'max-keys': '100'},
        signTime: fixedTime,
      );
      expect(result, contains('q-url-param-list='));
      expect(result, contains('q-signature='));
    });

    test('includes headers in signature', () {
      final result = getSign(
        'PUT',
        '/test',
        secretId: 'id',
        secretKey: 'key',
        headers: {'content-type': 'text/plain', 'host': 'example.com'},
        signTime: fixedTime,
      );
      expect(result, contains('q-header-list='));
    });

    test('uses custom sign duration', () {
      final shortResult = getSign(
        'GET',
        '/test',
        secretId: 'id',
        secretKey: 'key',
        signTime: fixedTime,
        signDuration: const Duration(minutes: 5),
      );
      final longResult = getSign(
        'GET',
        '/test',
        secretId: 'id',
        secretKey: 'key',
        signTime: fixedTime,
        signDuration: const Duration(hours: 2),
      );
      expect(shortResult, isNot(equals(longResult)));
    });

    test('same inputs produce same signature', () {
      final a = getSign('GET', '/test',
          secretId: 'id', secretKey: 'key', signTime: fixedTime);
      final b = getSign('GET', '/test',
          secretId: 'id', secretKey: 'key', signTime: fixedTime);
      expect(a, equals(b));
    });

    test('different methods produce different signatures', () {
      final a = getSign('GET', '/test',
          secretId: 'id', secretKey: 'key', signTime: fixedTime);
      final b = getSign('PUT', '/test',
          secretId: 'id', secretKey: 'key', signTime: fixedTime);
      expect(a, isNot(equals(b)));
    });
  });

  group('cosRequest', () {
    late QueuedMockInterceptor mock;

    setUp(() {
      mock = setUpMockDio();
    });

    tearDown(() {
      tearDownMockDio();
    });

    test('makes successful GET request', () async {
      mock.enqueueResponse(statusCode: 200, data: '<xml>ok</xml>');

      final request = createTestRequest();
      final resp = await cosRequest<String>(
        'GET',
        'test-object',
        putObjectRequest: request,
      );

      expect(resp.statusCode, 200);
      expect(resp.data, '<xml>ok</xml>');
    });

    test('prepends / to action if missing', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest();
      await cosRequest<String>(
        'GET',
        'no-slash',
        putObjectRequest: request,
      );

      final capturedUri = mock.capturedRequests.first.uri.toString();
      expect(capturedUri, contains('/no-slash'));
    });

    test('does not double-prepend / to action', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest();
      await cosRequest<String>(
        'GET',
        '/with-slash',
        putObjectRequest: request,
      );

      final capturedUri = mock.capturedRequests.first.uri.toString();
      expect(capturedUri, contains('/with-slash'));
      expect(capturedUri, isNot(contains('//with-slash')));
    });

    test('includes Authorization header', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest();
      await cosRequest<String>(
        'GET',
        '/test',
        putObjectRequest: request,
      );

      final headers = mock.capturedRequests.first.headers;
      expect(headers.containsKey('Authorization'), isTrue);
      expect(headers['Authorization'], contains('q-sign-algorithm=sha1'));
    });

    test('includes security token when non-empty', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest(securityToken: 'my-token');
      await cosRequest<String>(
        'GET',
        '/test',
        putObjectRequest: request,
        token: 'my-token',
      );

      final headers = mock.capturedRequests.first.headers;
      expect(headers['x-cos-security-token'], 'my-token');
    });

    test('omits security token when empty', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest(securityToken: '');
      await cosRequest<String>(
        'GET',
        '/test',
        putObjectRequest: request,
        token: '',
      );

      final headers = mock.capturedRequests.first.headers;
      expect(headers.containsKey('x-cos-security-token'), isFalse);
    });

    test('omits security token when null', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest();
      await cosRequest<String>(
        'GET',
        '/test',
        putObjectRequest: request,
        token: null,
      );

      final headers = mock.capturedRequests.first.headers;
      expect(headers.containsKey('x-cos-security-token'), isFalse);
    });

    test('passes query parameters', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest();
      await cosRequest<String>(
        'GET',
        '/test',
        putObjectRequest: request,
        params: {'prefix': 'files/', 'uploads': ''},
      );

      final queryParams = mock.capturedRequests.first.queryParameters;
      expect(queryParams['prefix'], 'files/');
      expect(queryParams['uploads'], '');
    });

    test('constructs correct URL with region', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest(
        bucketName: 'my-bucket',
        region: 'ap-shanghai',
      );
      await cosRequest<String>(
        'GET',
        '/obj',
        putObjectRequest: request,
      );

      final uri = mock.capturedRequests.first.uri.toString();
      expect(uri, contains('my-bucket.cos.ap-shanghai.myqcloud.com'));
    });

    test('uses data over stream when both provided', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest();
      await cosRequest<String>(
        'PUT',
        '/test',
        putObjectRequest: request,
        data: 'my-data',
        stream: Stream.value([1, 2, 3]),
      );

      expect(mock.capturedRequests.first.data, 'my-data');
    });

    test('uses stream when data is null', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest();
      await cosRequest<String>(
        'PUT',
        '/test',
        putObjectRequest: request,
        stream: Stream.value([1, 2, 3]),
      );

      expect(mock.capturedRequests.first.data, isNotNull);
    });

    test('rethrows DioException on network error', () async {
      final dioResult = createMockDio();
      cosCreateDio = () => dioResult.dio;
      dioResult.mock.enqueue((opts) =>
          throw DioException(requestOptions: opts, message: 'Network error'));

      final request = createTestRequest();
      expect(
        () => cosRequest<String>('GET', '/test', putObjectRequest: request),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('splitFileIntoChunks', () {
    test('splits file exactly divisible by part size', () async {
      final file = PlatformFile(name: 'test.bin', size: 3000, bytes: null);
      final result = await splitFileIntoChunks(file, 1000);

      expect(result.chunks.length, 3);
      expect(result.divider.partSize, 1000);
      expect(result.divider.partNumber, 3);
      for (int i = 0; i < 3; i++) {
        expect(result.chunks[i].number, i + 1);
        expect(result.chunks[i].offset, i * 1000);
        expect(result.chunks[i].size, 1000);
        expect(result.chunks[i].done, isFalse);
      }
    });

    test('splits file with remainder', () async {
      final file = PlatformFile(name: 'test.bin', size: 2500, bytes: null);
      final result = await splitFileIntoChunks(file, 1000);

      expect(result.chunks.length, 3);
      expect(result.chunks[0].size, 1000);
      expect(result.chunks[1].size, 1000);
      expect(result.chunks[2].size, 500);
      expect(result.divider.partNumber, 3);
    });

    test('handles file smaller than part size', () async {
      final file = PlatformFile(name: 'test.bin', size: 500, bytes: null);
      final result = await splitFileIntoChunks(file, 1000);

      expect(result.chunks.length, 1);
      expect(result.chunks[0].size, 500);
      expect(result.chunks[0].offset, 0);
      expect(result.chunks[0].number, 1);
    });

    test('handles zero-size file', () async {
      final file = PlatformFile(name: 'test.bin', size: 0, bytes: null);
      final result = await splitFileIntoChunks(file, 1000);

      expect(result.chunks, isEmpty);
      expect(result.divider.partNumber, 0);
    });

    test('auto-doubles part size when too many parts', () async {
      final file =
          PlatformFile(name: 'test.bin', size: 2000 * 1000, bytes: null);
      final result = await splitFileIntoChunks(file, 1);

      expect(result.divider.partNumber, lessThanOrEqualTo(1000));
      expect(result.divider.partSize, greaterThan(1));
    });

    test('chunk offsets are consecutive', () async {
      final file = PlatformFile(name: 'test.bin', size: 5500, bytes: null);
      final result = await splitFileIntoChunks(file, 1000);

      int expectedOffset = 0;
      for (var chunk in result.chunks) {
        expect(chunk.offset, expectedOffset);
        expectedOffset += chunk.size;
      }
      expect(expectedOffset, 5500);
    });

    test('all chunk numbers are sequential starting from 1', () async {
      final file = PlatformFile(name: 'test.bin', size: 3500, bytes: null);
      final result = await splitFileIntoChunks(file, 1000);

      for (int i = 0; i < result.chunks.length; i++) {
        expect(result.chunks[i].number, i + 1);
      }
    });
  });

  group('defaultCreateDio', () {
    test('creates Dio with timeout configuration', () {
      final dio = defaultCreateDio();
      expect(dio.options.connectTimeout, const Duration(seconds: 30));
      expect(dio.options.receiveTimeout, const Duration(seconds: 120));
      expect(dio.options.sendTimeout, const Duration(seconds: 120));
    });
  });
}
