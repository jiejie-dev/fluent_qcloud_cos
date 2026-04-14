import 'dart:io';

import 'package:fluent_qcloud_cos/models/complete_multipart_upload.dart';
import 'package:fluent_qcloud_cos/models/initiate_multipart_upload_result.dart';
import 'package:fluent_qcloud_cos/models/list_multipart_uploads.dart';
import 'package:fluent_qcloud_cos/models/list_part.dart';
import 'package:test/test.dart';

void main() {
  test('parse_InitiateMultipartUploadResult', () {
    final result = InitiateMultipartUploadResult.parse(
      '''<InitiateMultipartUploadResult>
            <Bucket>examplebucket-1250000000</Bucket>
            <Key>exampleobject</Key>
            <UploadId>1585130821cbb7df1d11846c073ad648e8f33b087cec2381df437acdc833cf654b9ecc6361</UploadId>
</InitiateMultipartUploadResult>''',
    );
    expect(
      result.uploadId,
      '1585130821cbb7df1d11846c073ad648e8f33b087cec2381df437acdc833cf654b9ecc6361',
    );
  });

  test('parse_CompleteMultipartUploadResult', () {
    final result = CompleteMultipartUploadResult.parse(
      '''<CompleteMultipartUploadResult xmlns="http://www.qcloud.com/document/product/436/7751">
    <Location>http://examplebucket-1250000000.cos.ap-beijing.myqcloud.com/exampleobject</Location>
    <Bucket>examplebucket-1250000000</Bucket>
    <Key>exampleobject</Key>
    <ETag>&quot;aa259a62513358f69e98e72e59856d88-3&quot;</ETag>
</CompleteMultipartUploadResult>''',
    );
    expect(
      result.location,
      'http://examplebucket-1250000000.cos.ap-beijing.myqcloud.com/exampleobject',
    );
  });

  test('parse_ListMultipartUploadsResult', () {
    final result = ListMultipartUploadsResult.parse(
      '''<ListMultipartUploadsResult>
    <Bucket>examplebucket-1250000000</Bucket>
    <Encoding-Type/>
    <KeyMarker/>
    <UploadIdMarker/>
    <MaxUploads>1000</MaxUploads>
    <Prefix/>
    <Delimiter>/</Delimiter>
    <IsTruncated>false</IsTruncated>
    <Upload>
        <Key>Object</Key>
        <UploadId>1484726657932bcb5b17f7a98a8cad9fc36a340ff204c79bd2f51e7dddf0b6d1da6220520c</UploadId>
        <Initiator>
           <ID>qcs::cam::uin/100000000001:uin/100000000001</ID>
        <DisplayName>100000000001</DisplayName>
        </Initiator>
        <Owner>
           <ID>qcs::cam::uin/100000000001:uin/100000000001</ID>
        <DisplayName>100000000001</DisplayName>
        </Owner>
        <StorageClass>Standard</StorageClass>
        <Initiated>Wed Jan 18 16:04:17 2017</Initiated>
    </Upload>
    <Upload>
        <Key>Object</Key>
        <UploadId>1484727158f2b8034e5407d18cbf28e84f754b791ecab607d25a2e52de9fee641e5f60707c</UploadId>
        <Initiator>
           <ID>qcs::cam::uin/100000000001:uin/100000000001</ID>
        <DisplayName>100000000001</DisplayName>
        </Initiator>
        <Owner>
           <ID>qcs::cam::uin/100000000001:uin/100000000001</ID>
        <DisplayName>100000000001</DisplayName>
        </Owner>
        <StorageClass>Standard</StorageClass>
        <Initiated>Wed Jan 18 16:12:38 2017</Initiated>
    </Upload>
    <Upload>
        <Key>exampleobject</Key>
        <UploadId>1484727270323ddb949d528c629235314a9ead80f0ba5d993a3d76b460e6a9cceb9633b08e</UploadId>
        <Initiator>
           <ID>qcs::cam::uin/100000000001:uin/100000000001</ID>
        <DisplayName>100000000001</DisplayName>
        </Initiator>
        <Owner>
           <ID>qcs::cam::uin/100000000001:uin/100000000001</ID>
        <DisplayName>100000000001</DisplayName>
        </Owner>
        <StorageClass>Standard</StorageClass>
        <Initiated>Wed Jan 18 16:14:30 2017</Initiated>
    </Upload>
</ListMultipartUploadsResult>''',
    );
    expect(result.uploads.length, 3);
  });

  test('parse_ListPartsResult', () {
    final result = ListPartsResult.parse(
      '''<?xml version="1.0" encoding="UTF-8" ?>
<ListPartsResult>
    <Bucket>examplebucket-1250000000</Bucket>
    <Encoding-type/>
    <Key>exampleobject</Key>
    <UploadId>14846420620b1f381e5d7b057692e131dd8d72dfa28f2633cfbbe4d0a9e8bd0719933545b0</UploadId>
    <Initiator>
        <ID>1250000000</ID>
        <DisplayName>1250000000</DisplayName>
    </Initiator>
    <Owner>
        <ID>qcs::cam::uin/100000000001:uin/100000000001</ID>
        <DisplayName>100000000001</DisplayName>
    </Owner>
    <PartNumberMarker>0</PartNumberMarker>
    <Part>
        <PartNumber>1</PartNumber>
        <LastModified>Tue Jan 17 16:43:37 2017</LastModified>
        <ETag>"a1f8e5e4d63ac6970a0062a6277e191fe09a1382"</ETag>
        <Size>5242880</Size>
    </Part>
    <NextPartNumberMarker>1</NextPartNumberMarker>
    <StorageClass>STANDARD</StorageClass>
    <MaxParts>1</MaxParts>
    <IsTruncated>true</IsTruncated>
</ListPartsResult>''',
    );
    expect(result.parts.length, 1);
  });

  // Integration tests below require .env and test/assets/ files.
  // Skip when running in CI or when .env is not available.
  final hasEnv = File('.env').existsSync() ||
      File('${Directory.current.path}/.env').existsSync();

  group('integration tests', skip: hasEnv ? null : 'requires .env file', () {
    // Integration tests can be re-enabled when .env and test assets are available.
  });
}
