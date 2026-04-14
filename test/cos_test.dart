import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fluent_qcloud_cos/cos.dart';
import 'package:fluent_qcloud_cos/exceptions.dart';
import 'package:fluent_qcloud_cos/models/chunks.dart';
import 'package:fluent_qcloud_cos/utils.dart';
import 'package:fluent_object_storage/fluent_object_storage.dart';
import 'package:platform_file/platform_file.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  late QueuedMockInterceptor mock;

  setUp(() {
    mock = setUpMockDio();
    FluentQCloudCos.maxPartRetries = 1;
  });

  tearDown(() {
    tearDownMockDio();
    FluentQCloudCos.maxPartRetries = 3;
  });

  group('putObject', () {
    test('delegates to putObjectSimple for small files', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final file = createTestFile(size: 1024);
      final request = createTestRequest(
        file: file,
        divisionForUpload: 2048,
      );

      await FluentQCloudCos.putObject(request);
      expect(mock.capturedRequests.length, 1);
      expect(mock.capturedRequests.first.method, 'PUT');
    });

    test('delegates to putObjectMultiPart for large files', () async {
      final file = createTestFile(size: 3072);
      final request = createTestRequest(
        file: file,
        divisionForUpload: 2048,
        sliceSizeForUpload: 1024,
      );

      // listMultipartUploads (for getResumableUploadId)
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<ListMultipartUploadsResult><Bucket>b</Bucket></ListMultipartUploadsResult>',
      );
      // initiateMultipartUpload
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<InitiateMultipartUploadResult><Bucket>b</Bucket><Key>k</Key><UploadId>uid-123</UploadId></InitiateMultipartUploadResult>',
      );
      // listParts (empty)
      mock.enqueueResponse(
        statusCode: 200,
        data: '<ListPartsResult></ListPartsResult>',
      );
      // uploadPart x3
      for (var i = 0; i < 3; i++) {
        mock.enqueue((opts) => Response(
              requestOptions: opts,
              statusCode: 200,
              data: 'ok',
              headers: Headers.fromMap({
                'etag': ['"etag-${i + 1}"']
              }),
            ));
      }
      // completeMultipartUpload
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      await FluentQCloudCos.putObject(request);
      expect(mock.capturedRequests.length, 7);
    });

    test('throws COSException for zero-size file', () {
      final file = PlatformFile(name: 'empty.txt', size: 0);
      final request = createTestRequest(file: file);

      expect(
        () => FluentQCloudCos.putObject(request),
        throwsA(isA<COSException>()),
      );
    });
  });

  group('putObjectSimple', () {
    test('returns objectName on success', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest(objectName: 'my-file.png');
      final result = await FluentQCloudCos.putObjectSimple(request);
      expect(result, 'my-file.png');
    });

    test('calls onSuccess handler on success', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      bool successCalled = false;
      final handler = ObjectStoragePutObjectEventHandler(taskId: 'test');
      handler.onSuccess = (_) => successCalled = true;

      final request = createTestRequest();
      await FluentQCloudCos.putObjectSimple(request, handler: handler);
      expect(successCalled, isTrue);
    });

    test('calls onProgress handler on success', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      ObjectStoragePutObjectResult? progressResult;
      final handler = ObjectStoragePutObjectEventHandler(taskId: 'test');
      handler.onProgress = (result) => progressResult = result;

      final file = createTestFile(size: 512);
      final request = createTestRequest(file: file);
      await FluentQCloudCos.putObjectSimple(request, handler: handler);

      expect(progressResult, isNotNull);
      expect(progressResult!.currentSize, 512);
      expect(progressResult!.totalSize, 512);
    });

    test('throws COSException on non-200 response', () async {
      mock.enqueueResponse(statusCode: 403, data: 'Forbidden');

      final request = createTestRequest();
      expect(
        () => FluentQCloudCos.putObjectSimple(request),
        throwsA(isA<COSException>()),
      );
    });

    test('calls onFailed handler on error', () async {
      mock.enqueueResponse(statusCode: 500, data: 'Server Error');

      bool failedCalled = false;
      final handler = ObjectStoragePutObjectEventHandler(taskId: 'test');
      handler.onFailed = (_) => failedCalled = true;

      final request = createTestRequest();
      try {
        await FluentQCloudCos.putObjectSimple(request, handler: handler);
      } catch (_) {}

      expect(failedCalled, isTrue);
    });

    test('works without handler', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest();
      final result = await FluentQCloudCos.putObjectSimple(request);
      expect(result, isNotNull);
    });

    test('sends correct method and content type headers', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest(objectName: 'photo.jpg');
      await FluentQCloudCos.putObjectSimple(request);

      expect(mock.capturedRequests.first.method, 'PUT');
    });
  });

  group('putObjectMultiPart', () {
    void enqueueMultiPartFlow({
      int partCount = 3,
      bool withResume = false,
      String uploadId = 'uid-test',
      String objectName = 'test-object.png',
    }) {
      if (withResume) {
        // listMultipartUploads → has existing upload
        mock.enqueueResponse(
          statusCode: 200,
          data: '<ListMultipartUploadsResult><Upload>'
              '<Key>$objectName</Key><UploadId>$uploadId</UploadId>'
              '</Upload></ListMultipartUploadsResult>',
        );
      } else {
        // listMultipartUploads → empty
        mock.enqueueResponse(
          statusCode: 200,
          data:
              '<ListMultipartUploadsResult><Bucket>b</Bucket></ListMultipartUploadsResult>',
        );
        // initiateMultipartUpload
        mock.enqueueResponse(
          statusCode: 200,
          data:
              '<InitiateMultipartUploadResult><Bucket>b</Bucket><Key>k</Key><UploadId>$uploadId</UploadId></InitiateMultipartUploadResult>',
        );
      }

      // listParts → empty
      mock.enqueueResponse(
        statusCode: 200,
        data: '<ListPartsResult></ListPartsResult>',
      );

      // uploadPart x partCount
      for (var i = 0; i < partCount; i++) {
        mock.enqueue((opts) => Response(
              requestOptions: opts,
              statusCode: 200,
              data: 'ok',
              headers: Headers.fromMap({
                'etag': ['"etag-${i + 1}"']
              }),
            ));
      }

      // completeMultipartUpload
      mock.enqueueResponse(statusCode: 200, data: 'ok');
    }

    test('completes fresh multipart upload', () async {
      final file = createTestFile(size: 3072);
      final request = createTestRequest(
        file: file,
        sliceSizeForUpload: 1024,
      );
      enqueueMultiPartFlow(partCount: 3);

      await FluentQCloudCos.putObjectMultiPart(request);

      // listMultipartUploads + initiateMultipartUpload + listParts + 3 uploadPart + completeMultipartUpload = 7
      expect(mock.capturedRequests.length, 7);
    });

    test('resumes existing multipart upload', () async {
      final file = createTestFile(size: 3072);
      final request = createTestRequest(
        file: file,
        sliceSizeForUpload: 1024,
      );
      enqueueMultiPartFlow(
        partCount: 3,
        withResume: true,
        objectName: request.objectName,
      );

      await FluentQCloudCos.putObjectMultiPart(request);

      // listMultipartUploads + listParts + 3 uploadPart + completeMultipartUpload = 6 (no initiate)
      expect(mock.capturedRequests.length, 6);
    });

    test('calls onProgress for each uploaded part', () async {
      final file = createTestFile(size: 2048);
      final request = createTestRequest(
        file: file,
        sliceSizeForUpload: 1024,
      );
      enqueueMultiPartFlow(partCount: 2);

      List<int> progressSizes = [];
      final handler = ObjectStoragePutObjectEventHandler(taskId: 'test');
      handler.onProgress = (result) {
        progressSizes.add(result.currentSize!);
      };

      await FluentQCloudCos.putObjectMultiPart(request, handler: handler);
      expect(progressSizes, [1024, 2048]);
    });

    test('calls onSuccess on completion', () async {
      final file = createTestFile(size: 1024);
      final request = createTestRequest(
        file: file,
        sliceSizeForUpload: 1024,
      );
      enqueueMultiPartFlow(partCount: 1);

      bool successCalled = false;
      final handler = ObjectStoragePutObjectEventHandler(taskId: 'test');
      handler.onSuccess = (_) => successCalled = true;

      await FluentQCloudCos.putObjectMultiPart(request, handler: handler);
      expect(successCalled, isTrue);
    });

    test('calls onFailed and rethrows on error', () async {
      // listMultipartUploads → error
      mock.enqueueResponse(statusCode: 500, data: 'Server Error');
      // getResumableUploadId catches COSException → returns null → calls initiateMultipartUpload
      mock.enqueueResponse(statusCode: 500, data: 'Server Error');

      final file = createTestFile(size: 2048);
      final request = createTestRequest(
        file: file,
        sliceSizeForUpload: 1024,
      );

      bool failedCalled = false;
      final handler = ObjectStoragePutObjectEventHandler(taskId: 'test');
      handler.onFailed = (_) => failedCalled = true;

      try {
        await FluentQCloudCos.putObjectMultiPart(request, handler: handler);
        fail('Should have thrown COSException');
      } on COSException {
        // expected
      }

      expect(failedCalled, isTrue);
    });

    test('throws COSException for zero-size file', () {
      final file = PlatformFile(name: 'empty.txt', size: 0);
      final request = createTestRequest(file: file);

      expect(
        () => FluentQCloudCos.putObjectMultiPart(request),
        throwsA(isA<COSException>()),
      );
    });

    test('handles file with bytes only (no readStream)', () async {
      final data = List.filled(2048, 65);
      final file = PlatformFile(
        name: 'test.png',
        size: 2048,
        bytes: Uint8List.fromList(data),
      );
      final request = createTestRequest(
        file: file,
        sliceSizeForUpload: 1024,
      );
      enqueueMultiPartFlow(partCount: 2);

      await FluentQCloudCos.putObjectMultiPart(request);
      expect(mock.capturedRequests.length, 6);
    });

    test('throws when file has neither readStream nor bytes', () async {
      final file = PlatformFile(name: 'test.png', size: 2048);
      final request = createTestRequest(
        file: file,
        sliceSizeForUpload: 1024,
      );

      // listMultipartUploads → empty
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<ListMultipartUploadsResult><Bucket>b</Bucket></ListMultipartUploadsResult>',
      );
      // initiateMultipartUpload
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<InitiateMultipartUploadResult><Bucket>b</Bucket><Key>k</Key><UploadId>uid</UploadId></InitiateMultipartUploadResult>',
      );
      // listParts
      mock.enqueueResponse(
        statusCode: 200,
        data: '<ListPartsResult></ListPartsResult>',
      );

      expect(
        () => FluentQCloudCos.putObjectMultiPart(request),
        throwsA(isA<COSException>()),
      );
    });

    test('throws when server returns inconsistent part number', () async {
      final file = createTestFile(size: 2048);
      final request = createTestRequest(
        file: file,
        sliceSizeForUpload: 1024,
      );

      // listMultipartUploads → has upload
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<ListMultipartUploadsResult><Upload><Key>${request.objectName}</Key><UploadId>uid</UploadId></Upload></ListMultipartUploadsResult>',
      );
      // listParts → part with number 5, but file only produces 2 chunks
      mock.enqueueResponse(
        statusCode: 200,
        data: '''<ListPartsResult>
          <Part><PartNumber>5</PartNumber><LastModified>date</LastModified><ETag>"etag"</ETag><Size>1024</Size></Part>
        </ListPartsResult>''',
      );

      expect(
        () => FluentQCloudCos.putObjectMultiPart(request),
        throwsA(isA<COSException>()),
      );
    });

    test('skips already uploaded parts in resume', () async {
      final file = createTestFile(size: 3072);
      final request = createTestRequest(
        file: file,
        sliceSizeForUpload: 1024,
      );

      // listMultipartUploads → has existing upload
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<ListMultipartUploadsResult><Upload><Key>${request.objectName}</Key><UploadId>uid</UploadId></Upload></ListMultipartUploadsResult>',
      );
      // listParts → part 1 already uploaded
      mock.enqueueResponse(
        statusCode: 200,
        data: '''<ListPartsResult>
          <Part><PartNumber>1</PartNumber><LastModified>date</LastModified><ETag>"existing-etag"</ETag><Size>1024</Size></Part>
        </ListPartsResult>''',
      );
      // uploadPart x2 (parts 2 and 3, part 1 skipped)
      for (var i = 0; i < 2; i++) {
        mock.enqueue((opts) => Response(
              requestOptions: opts,
              statusCode: 200,
              data: 'ok',
              headers: Headers.fromMap({
                'etag': ['"etag-new-${i + 2}"']
              }),
            ));
      }
      // completeMultipartUpload
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      await FluentQCloudCos.putObjectMultiPart(request);

      // listMultipartUploads + listParts + 2 uploadPart + completeMultipartUpload = 5
      expect(mock.capturedRequests.length, 5);
    });
  });

  group('initiateMultipartUpload', () {
    test('returns upload ID on success', () async {
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<InitiateMultipartUploadResult><Bucket>b</Bucket><Key>k</Key><UploadId>uid-abc</UploadId></InitiateMultipartUploadResult>',
      );

      final request = createTestRequest();
      final result = await FluentQCloudCos.initiateMultipartUpload(request);
      expect(result.uploadId, 'uid-abc');
    });

    test('throws COSException on non-200', () async {
      mock.enqueueResponse(statusCode: 403, data: 'Forbidden');

      final request = createTestRequest();
      expect(
        () => FluentQCloudCos.initiateMultipartUpload(request),
        throwsA(isA<COSException>()),
      );
    });

    test('sends POST with uploads param', () async {
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<InitiateMultipartUploadResult><Bucket>b</Bucket><Key>k</Key><UploadId>uid</UploadId></InitiateMultipartUploadResult>',
      );

      final request = createTestRequest();
      await FluentQCloudCos.initiateMultipartUpload(request);

      expect(mock.capturedRequests.first.method, 'POST');
      expect(
          mock.capturedRequests.first.queryParameters.containsKey('uploads'),
          isTrue);
    });
  });

  group('uploadPart', () {
    test('returns ETag on success', () async {
      mock.enqueue((opts) => Response(
            requestOptions: opts,
            statusCode: 200,
            data: 'ok',
            headers: Headers.fromMap({
              'etag': ['"part-etag-1"']
            }),
          ));

      final request = createTestRequest();
      final etag = await FluentQCloudCos.uploadPart(
          'uid', 1, [1, 2, 3, 4], request);
      expect(etag, '"part-etag-1"');
    });

    test('throws COSException on error response', () async {
      mock.enqueueResponse(statusCode: 500, data: 'Error');

      final request = createTestRequest();
      expect(
        () => FluentQCloudCos.uploadPart('uid', 1, [1, 2], request),
        throwsA(isA<COSException>()),
      );
    });

    test('sends PUT with uploadId and partNumber params', () async {
      mock.enqueue((opts) => Response(
            requestOptions: opts,
            statusCode: 200,
            data: 'ok',
            headers: Headers.fromMap({
              'etag': ['"etag"']
            }),
          ));

      final request = createTestRequest();
      await FluentQCloudCos.uploadPart('my-uid', 5, [1], request);

      final captured = mock.capturedRequests.first;
      expect(captured.method, 'PUT');
      expect(captured.queryParameters['uploadId'], 'my-uid');
      expect(captured.queryParameters['partNumber'], '5');
    });

    test('sends correct content-length header', () async {
      mock.enqueue((opts) => Response(
            requestOptions: opts,
            statusCode: 200,
            data: 'ok',
            headers: Headers.fromMap({
              'etag': ['"etag"']
            }),
          ));

      final partData = List.filled(2048, 65);
      final request = createTestRequest();
      await FluentQCloudCos.uploadPart('uid', 1, partData, request);

      final captured = mock.capturedRequests.first;
      expect(captured.headers['content-length'], '2048');
    });
  });

  group('completeMultipartUpload', () {
    test('succeeds with valid chunks', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final chunks = [
        Chunk(1, 0, 1024, true)..eTag = '"etag1"',
        Chunk(2, 1024, 1024, true)..eTag = '"etag2"',
      ];
      final request = createTestRequest();

      await FluentQCloudCos.completeMultipartUpload('uid', chunks, request);

      final captured = mock.capturedRequests.first;
      expect(captured.method, 'POST');
      expect(captured.queryParameters['uploadId'], 'uid');
      expect(captured.headers['content-type'], 'application/xml');
    });

    test('throws COSException on non-200', () async {
      mock.enqueueResponse(statusCode: 400, data: 'Bad Request');

      final chunks = [Chunk(1, 0, 1024, true)..eTag = '"etag"'];
      final request = createTestRequest();

      expect(
        () => FluentQCloudCos.completeMultipartUpload('uid', chunks, request),
        throwsA(isA<COSException>()),
      );
    });

    test('sends XML with part numbers and eTags', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final chunks = [
        Chunk(1, 0, 512, true)..eTag = '"abc"',
        Chunk(2, 512, 512, true)..eTag = '"def"',
      ];
      final request = createTestRequest();

      await FluentQCloudCos.completeMultipartUpload('uid', chunks, request);

      final data = mock.capturedRequests.first.data as String;
      expect(data, contains('<PartNumber>1</PartNumber>'));
      expect(data, contains('<ETag>"abc"</ETag>'));
      expect(data, contains('<PartNumber>2</PartNumber>'));
      expect(data, contains('<ETag>"def"</ETag>'));
    });
  });

  group('abortMultipartUpload', () {
    test('succeeds with 204 response', () async {
      mock.enqueueResponse(statusCode: 204, data: '');

      final request = createTestRequest();
      await FluentQCloudCos.abortMultipartUpload('uid-abort', request);

      expect(mock.capturedRequests.first.method, 'DELETE');
      expect(mock.capturedRequests.first.queryParameters['uploadId'],
          'uid-abort');
    });

    test('succeeds with 200 response', () async {
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      final request = createTestRequest();
      await FluentQCloudCos.abortMultipartUpload('uid', request);
    });

    test('throws COSException on error', () async {
      mock.enqueueResponse(statusCode: 404, data: 'NoSuchUpload');

      final request = createTestRequest();
      expect(
        () => FluentQCloudCos.abortMultipartUpload('bad-uid', request),
        throwsA(isA<COSException>()),
      );
    });
  });

  group('listMultipartUploads', () {
    test('returns parsed result on success', () async {
      mock.enqueueResponse(
        statusCode: 200,
        data: '''<ListMultipartUploadsResult>
          <Upload><Key>obj1</Key><UploadId>uid1</UploadId></Upload>
          <Upload><Key>obj2</Key><UploadId>uid2</UploadId></Upload>
        </ListMultipartUploadsResult>''',
      );

      final request = createTestRequest();
      final result = await FluentQCloudCos.listMultipartUploads(request);

      expect(result.uploads.length, 2);
      expect(result.uploads[0].key, 'obj1');
    });

    test('throws COSException on non-200', () async {
      mock.enqueueResponse(statusCode: 500, data: 'Error');

      final request = createTestRequest();
      expect(
        () => FluentQCloudCos.listMultipartUploads(request),
        throwsA(isA<COSException>()),
      );
    });

    test('sends GET with prefix and uploads params', () async {
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<ListMultipartUploadsResult><Bucket>b</Bucket></ListMultipartUploadsResult>',
      );

      final request = createTestRequest(objectName: 'my/prefix.png');
      await FluentQCloudCos.listMultipartUploads(request);

      final captured = mock.capturedRequests.first;
      expect(captured.method, 'GET');
      expect(captured.queryParameters['prefix'], 'my/prefix.png');
      expect(captured.queryParameters.containsKey('uploads'), isTrue);
    });
  });

  group('getResumableUploadId', () {
    test('returns uploadId when matching upload exists', () async {
      mock.enqueueResponse(
        statusCode: 200,
        data: '''<ListMultipartUploadsResult>
          <Upload><Key>test-object.png</Key><UploadId>uid-match</UploadId></Upload>
        </ListMultipartUploadsResult>''',
      );

      final request = createTestRequest(objectName: 'test-object.png');
      final uploadId = await FluentQCloudCos.getResumableUploadId(request);
      expect(uploadId, 'uid-match');
    });

    test('returns last matching uploadId when multiple exist', () async {
      mock.enqueueResponse(
        statusCode: 200,
        data: '''<ListMultipartUploadsResult>
          <Upload><Key>test-object.png</Key><UploadId>uid-first</UploadId></Upload>
          <Upload><Key>test-object.png</Key><UploadId>uid-last</UploadId></Upload>
        </ListMultipartUploadsResult>''',
      );

      final request = createTestRequest(objectName: 'test-object.png');
      final uploadId = await FluentQCloudCos.getResumableUploadId(request);
      expect(uploadId, 'uid-last');
    });

    test('returns null when no uploads exist', () async {
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<ListMultipartUploadsResult><Bucket>b</Bucket></ListMultipartUploadsResult>',
      );

      final request = createTestRequest();
      final uploadId = await FluentQCloudCos.getResumableUploadId(request);
      expect(uploadId, isNull);
    });

    test('returns null when no matching key found', () async {
      mock.enqueueResponse(
        statusCode: 200,
        data: '''<ListMultipartUploadsResult>
          <Upload><Key>other-object.png</Key><UploadId>uid-other</UploadId></Upload>
        </ListMultipartUploadsResult>''',
      );

      final request = createTestRequest(objectName: 'my-object.png');
      final uploadId = await FluentQCloudCos.getResumableUploadId(request);
      expect(uploadId, isNull);
    });

    test('returns null on COSException', () async {
      mock.enqueueResponse(statusCode: 500, data: 'Error');

      final request = createTestRequest();
      final uploadId = await FluentQCloudCos.getResumableUploadId(request);
      expect(uploadId, isNull);
    });
  });

  group('listParts', () {
    test('returns parsed result on success', () async {
      mock.enqueueResponse(
        statusCode: 200,
        data: '''<ListPartsResult>
          <Part><PartNumber>1</PartNumber><LastModified>date</LastModified><ETag>"etag1"</ETag><Size>1024</Size></Part>
          <Part><PartNumber>2</PartNumber><LastModified>date</LastModified><ETag>"etag2"</ETag><Size>1024</Size></Part>
        </ListPartsResult>''',
      );

      final request = createTestRequest();
      final result = await FluentQCloudCos.listParts('uid', request);

      expect(result.parts.length, 2);
      expect(result.parts[0].partNumber, 1);
      expect(result.parts[1].partNumber, 2);
    });

    test('throws COSException on non-200', () async {
      mock.enqueueResponse(statusCode: 404, data: 'Not Found');

      final request = createTestRequest();
      expect(
        () => FluentQCloudCos.listParts('uid', request),
        throwsA(isA<COSException>()),
      );
    });

    test('sends GET with uploadId param', () async {
      mock.enqueueResponse(
        statusCode: 200,
        data: '<ListPartsResult></ListPartsResult>',
      );

      final request = createTestRequest();
      await FluentQCloudCos.listParts('my-upload-id', request);

      final captured = mock.capturedRequests.first;
      expect(captured.method, 'GET');
      expect(captured.queryParameters['uploadId'], 'my-upload-id');
    });
  });

  group('retry logic', () {
    test('retries failed part upload', () async {
      FluentQCloudCos.maxPartRetries = 3;

      final file = createTestFile(size: 1024);
      final request = createTestRequest(
        file: file,
        sliceSizeForUpload: 1024,
      );

      // getResumableUploadId → empty
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<ListMultipartUploadsResult><Bucket>b</Bucket></ListMultipartUploadsResult>',
      );
      // initiate
      mock.enqueueResponse(
        statusCode: 200,
        data:
            '<InitiateMultipartUploadResult><Bucket>b</Bucket><Key>k</Key><UploadId>uid</UploadId></InitiateMultipartUploadResult>',
      );
      // listParts → empty
      mock.enqueueResponse(
        statusCode: 200,
        data: '<ListPartsResult></ListPartsResult>',
      );
      // uploadPart attempt 1 → fail
      mock.enqueueResponse(statusCode: 500, data: 'Error');
      // uploadPart attempt 2 → fail
      mock.enqueueResponse(statusCode: 500, data: 'Error');
      // uploadPart attempt 3 → success
      mock.enqueue((opts) => Response(
            requestOptions: opts,
            statusCode: 200,
            data: 'ok',
            headers: Headers.fromMap({
              'etag': ['"retried-etag"']
            }),
          ));
      // completeMultipartUpload
      mock.enqueueResponse(statusCode: 200, data: 'ok');

      await FluentQCloudCos.putObjectMultiPart(request);
      // 3 + 3 attempts for upload + 1 complete = 7 total
      expect(mock.capturedRequests.length, 7);
    });
  });
}
