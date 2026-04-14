import 'package:fluent_qcloud_cos/exceptions.dart';
import 'package:fluent_qcloud_cos/models/chunks.dart';
import 'package:fluent_qcloud_cos/models/complete_multipart_upload.dart';
import 'package:fluent_qcloud_cos/models/divide_part_result.dart';
import 'package:fluent_qcloud_cos/models/initiate_multipart_upload_result.dart';
import 'package:fluent_qcloud_cos/models/list_multipart_uploads.dart';
import 'package:fluent_qcloud_cos/models/list_part.dart';
import 'package:test/test.dart';

void main() {
  group('COSException', () {
    test('stores statusCode and msg', () {
      final e = COSException(404, 'Not Found');
      expect(e.statusCode, 404);
      expect(e.msg, 'Not Found');
    });

    test('toString includes statusCode and msg', () {
      final e = COSException(500, 'Server Error');
      final str = e.toString();
      expect(str, contains('500'));
      expect(str, contains('Server Error'));
      expect(str, contains('COSException'));
    });

    test('implements Exception', () {
      expect(COSException(400, 'Bad'), isA<Exception>());
    });
  });

  group('DividePartResult', () {
    test('constructor sets fields', () {
      final result = DividePartResult(1024, 10);
      expect(result.partSize, 1024);
      expect(result.partNumber, 10);
    });

    group('parse', () {
      test('calculates correct part number for exact division', () {
        final result = DividePartResult.parse(3000, 1000);
        expect(result.partSize, 1000);
        expect(result.partNumber, 3);
      });

      test('truncates part number for non-exact division', () {
        final result = DividePartResult.parse(3500, 1000);
        expect(result.partSize, 1000);
        expect(result.partNumber, 3);
      });

      test('doubles part size when partNumber exceeds 1000', () {
        final result = DividePartResult.parse(2000000, 1);
        expect(result.partNumber, lessThanOrEqualTo(1000));
        expect(result.partSize, greaterThan(1));
      });

      test('returns 0 parts for zero filesize', () {
        final result = DividePartResult.parse(0, 1000);
        expect(result.partNumber, 0);
        expect(result.partSize, 1000);
      });

      test('returns 0 parts for negative filesize', () {
        final result = DividePartResult.parse(-100, 1000);
        expect(result.partNumber, 0);
      });

      test('throws on zero partSize', () {
        expect(
          () => DividePartResult.parse(1000, 0),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws on negative partSize', () {
        expect(
          () => DividePartResult.parse(1000, -1),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('handles file size equal to part size', () {
        final result = DividePartResult.parse(1000, 1000);
        expect(result.partNumber, 1);
        expect(result.partSize, 1000);
      });

      test('handles file size smaller than part size', () {
        final result = DividePartResult.parse(500, 1000);
        expect(result.partNumber, 0);
        expect(result.partSize, 1000);
      });

      test('handles very large file with small part size', () {
        final fileSize = 10 * 1024 * 1024 * 1024; // 10GB
        final result = DividePartResult.parse(fileSize, 1024 * 1024);
        expect(result.partNumber, lessThanOrEqualTo(1000));
        expect(result.partSize * result.partNumber, lessThanOrEqualTo(fileSize));
      });
    });
  });

  group('Chunk', () {
    test('constructor sets all fields', () {
      final chunk = Chunk(1, 0, 1024, false);
      expect(chunk.number, 1);
      expect(chunk.offset, 0);
      expect(chunk.size, 1024);
      expect(chunk.done, isFalse);
      expect(chunk.eTag, isNull);
    });

    test('done flag can be updated', () {
      final chunk = Chunk(1, 0, 1024, false);
      chunk.done = true;
      expect(chunk.done, isTrue);
    });

    test('eTag can be set', () {
      final chunk = Chunk(1, 0, 1024, false);
      chunk.eTag = '"abc123"';
      expect(chunk.eTag, '"abc123"');
    });

    test('initial done=true from constructor', () {
      final chunk = Chunk(2, 1024, 512, true);
      expect(chunk.done, isTrue);
    });
  });

  group('SplitFileChunksResult', () {
    test('constructor stores divider and chunks', () {
      final divider = DividePartResult(1024, 3);
      final chunks = [Chunk(1, 0, 1024, false), Chunk(2, 1024, 1024, false)];
      final result = SplitFileChunksResult(divider, chunks);
      expect(result.divider.partSize, 1024);
      expect(result.chunks.length, 2);
    });
  });

  group('InitiateMultipartUploadResult', () {
    test('constructor stores uploadId', () {
      final result = InitiateMultipartUploadResult('upload-123');
      expect(result.uploadId, 'upload-123');
    });

    test('parse extracts uploadId from XML', () {
      final result = InitiateMultipartUploadResult.parse('''
<InitiateMultipartUploadResult>
    <Bucket>examplebucket-1250000000</Bucket>
    <Key>exampleobject</Key>
    <UploadId>1585130821cbb7df1d11846c073ad648e8f33b087cec2381df437acdc833cf654b9ecc6361</UploadId>
</InitiateMultipartUploadResult>''');
      expect(result.uploadId,
          '1585130821cbb7df1d11846c073ad648e8f33b087cec2381df437acdc833cf654b9ecc6361');
    });

    test('parse throws on missing UploadId element', () {
      expect(
        () => InitiateMultipartUploadResult.parse('''
<InitiateMultipartUploadResult>
    <Bucket>examplebucket</Bucket>
</InitiateMultipartUploadResult>'''),
        throwsStateError,
      );
    });

    test('parse throws on invalid XML', () {
      expect(
        () => InitiateMultipartUploadResult.parse('not xml'),
        throwsA(anything),
      );
    });
  });

  group('MultipartUploadPart', () {
    test('constructor stores fields', () {
      final part = MultipartUploadPart(3, '"etag123"');
      expect(part.partNumber, 3);
      expect(part.eTag, '"etag123"');
    });
  });

  group('CompleteMultipartUpload', () {
    test('xmlContent generates valid XML with chunks', () {
      final chunks = [
        Chunk(1, 0, 1024, true)..eTag = '"etag1"',
        Chunk(2, 1024, 1024, true)..eTag = '"etag2"',
        Chunk(3, 2048, 512, true)..eTag = '"etag3"',
      ];
      final upload = CompleteMultipartUpload(chunks);
      final xml = upload.xmlContent();

      expect(xml, contains('<CompleteMultipartUpload>'));
      expect(xml, contains('<Part>'));
      expect(xml, contains('<PartNumber>1</PartNumber>'));
      expect(xml, contains('<ETag>"etag1"</ETag>'));
      expect(xml, contains('<PartNumber>2</PartNumber>'));
      expect(xml, contains('<ETag>"etag2"</ETag>'));
      expect(xml, contains('<PartNumber>3</PartNumber>'));
      expect(xml, contains('<ETag>"etag3"</ETag>'));
    });

    test('xmlContent throws StateError when chunk has null eTag', () {
      final chunks = [
        Chunk(1, 0, 1024, true)..eTag = '"etag1"',
        Chunk(2, 1024, 1024, false),
      ];
      final upload = CompleteMultipartUpload(chunks);
      expect(() => upload.xmlContent(), throwsStateError);
    });

    test('xmlContent throws StateError when chunk has empty eTag', () {
      final chunks = [
        Chunk(1, 0, 1024, true)..eTag = '',
      ];
      final upload = CompleteMultipartUpload(chunks);
      expect(() => upload.xmlContent(), throwsStateError);
    });

    test('xmlContent handles single chunk', () {
      final chunks = [Chunk(1, 0, 1024, true)..eTag = '"single"'];
      final upload = CompleteMultipartUpload(chunks);
      final xml = upload.xmlContent();
      expect(xml, contains('<PartNumber>1</PartNumber>'));
      expect(xml, contains('<ETag>"single"</ETag>'));
    });

    test('xmlContent with empty chunks list produces valid XML', () {
      final upload = CompleteMultipartUpload([]);
      final xml = upload.xmlContent();
      expect(xml, contains('<CompleteMultipartUpload/>'));
    });
  });

  group('CompleteMultipartUploadResult', () {
    test('constructor stores all fields', () {
      final result = CompleteMultipartUploadResult(
          'http://example.com', 'bucket', 'key', '"etag"');
      expect(result.location, 'http://example.com');
      expect(result.bucket, 'bucket');
      expect(result.key, 'key');
      expect(result.eTag, '"etag"');
    });

    test('parse extracts fields from XML', () {
      final result = CompleteMultipartUploadResult.parse('''
<CompleteMultipartUploadResult xmlns="http://www.qcloud.com/document/product/436/7751">
    <Location>http://examplebucket-1250000000.cos.ap-beijing.myqcloud.com/exampleobject</Location>
    <Bucket>examplebucket-1250000000</Bucket>
    <Key>exampleobject</Key>
    <ETag>&quot;aa259a62513358f69e98e72e59856d88-3&quot;</ETag>
</CompleteMultipartUploadResult>''');

      expect(result.location,
          'http://examplebucket-1250000000.cos.ap-beijing.myqcloud.com/exampleobject');
      expect(result.bucket, 'examplebucket-1250000000');
      expect(result.key, 'exampleobject');
      expect(result.eTag, contains('aa259a62513358f69e98e72e59856d88'));
    });

    test('parse throws on missing element', () {
      expect(
        () => CompleteMultipartUploadResult.parse('''
<CompleteMultipartUploadResult>
    <Location>http://example.com</Location>
</CompleteMultipartUploadResult>'''),
        throwsStateError,
      );
    });
  });

  group('ListPart', () {
    test('constructor stores fields', () {
      final part = ListPart(1, '2024-01-15T12:00:00Z', '"etag"', 5242880);
      expect(part.partNumber, 1);
      expect(part.lastModified, '2024-01-15T12:00:00Z');
      expect(part.eTag, '"etag"');
      expect(part.size, 5242880);
    });
  });

  group('ListPartsResult', () {
    test('constructor with provided parts', () {
      final parts = [ListPart(1, 'date', '"etag"', 1024)];
      final result = ListPartsResult(parts);
      expect(result.parts.length, 1);
    });

    test('parse extracts parts from XML', () {
      final result = ListPartsResult.parse('''<?xml version="1.0" encoding="UTF-8" ?>
<ListPartsResult>
    <Bucket>examplebucket-1250000000</Bucket>
    <Key>exampleobject</Key>
    <UploadId>upload-123</UploadId>
    <Part>
        <PartNumber>1</PartNumber>
        <LastModified>Tue Jan 17 16:43:37 2017</LastModified>
        <ETag>"a1f8e5e4d63ac6970a0062a6277e191fe09a1382"</ETag>
        <Size>5242880</Size>
    </Part>
    <Part>
        <PartNumber>2</PartNumber>
        <LastModified>Tue Jan 17 16:44:00 2017</LastModified>
        <ETag>"b2f9e6e5d74bd7080b1173b7388f202gf19b2493"</ETag>
        <Size>5242880</Size>
    </Part>
</ListPartsResult>''');
      expect(result.parts.length, 2);
      expect(result.parts[0].partNumber, 1);
      expect(result.parts[0].eTag,
          '"a1f8e5e4d63ac6970a0062a6277e191fe09a1382"');
      expect(result.parts[0].size, 5242880);
      expect(result.parts[1].partNumber, 2);
    });

    test('parse handles empty parts list', () {
      final result = ListPartsResult.parse('''<?xml version="1.0" encoding="UTF-8" ?>
<ListPartsResult>
    <Bucket>examplebucket</Bucket>
    <Key>exampleobject</Key>
    <UploadId>upload-123</UploadId>
</ListPartsResult>''');
      expect(result.parts, isEmpty);
    });

    test('parse handles single part', () {
      final result = ListPartsResult.parse('''
<ListPartsResult>
    <Part>
        <PartNumber>3</PartNumber>
        <LastModified>2024-01-15</LastModified>
        <ETag>"etag3"</ETag>
        <Size>1024</Size>
    </Part>
</ListPartsResult>''');
      expect(result.parts.length, 1);
      expect(result.parts[0].partNumber, 3);
    });
  });

  group('ListMultipartUpload', () {
    test('constructor stores fields', () {
      final upload = ListMultipartUpload('my-key', 'upload-123');
      expect(upload.key, 'my-key');
      expect(upload.uploadId, 'upload-123');
    });
  });

  group('ListMultipartUploadsResult', () {
    test('constructor with provided uploads', () {
      final uploads = [ListMultipartUpload('key', 'id')];
      final result = ListMultipartUploadsResult(uploads);
      expect(result.uploads.length, 1);
    });

    test('parse extracts uploads from XML', () {
      final result = ListMultipartUploadsResult.parse('''
<ListMultipartUploadsResult>
    <Bucket>examplebucket</Bucket>
    <Upload>
        <Key>object1</Key>
        <UploadId>upload-001</UploadId>
        <Initiator><ID>user</ID></Initiator>
    </Upload>
    <Upload>
        <Key>object2</Key>
        <UploadId>upload-002</UploadId>
        <Initiator><ID>user</ID></Initiator>
    </Upload>
</ListMultipartUploadsResult>''');
      expect(result.uploads.length, 2);
      expect(result.uploads[0].key, 'object1');
      expect(result.uploads[0].uploadId, 'upload-001');
      expect(result.uploads[1].key, 'object2');
      expect(result.uploads[1].uploadId, 'upload-002');
    });

    test('parse handles empty uploads', () {
      final result = ListMultipartUploadsResult.parse('''
<ListMultipartUploadsResult>
    <Bucket>examplebucket</Bucket>
</ListMultipartUploadsResult>''');
      expect(result.uploads, isEmpty);
    });

    test('parse handles three uploads', () {
      final result = ListMultipartUploadsResult.parse('''
<ListMultipartUploadsResult>
    <Upload>
        <Key>Object</Key>
        <UploadId>id1</UploadId>
    </Upload>
    <Upload>
        <Key>Object</Key>
        <UploadId>id2</UploadId>
    </Upload>
    <Upload>
        <Key>exampleobject</Key>
        <UploadId>id3</UploadId>
    </Upload>
</ListMultipartUploadsResult>''');
      expect(result.uploads.length, 3);
    });
  });
}
