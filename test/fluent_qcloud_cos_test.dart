import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fluent_qcloud_cos/models/complete_multipart_upload.dart';
import 'package:fluent_qcloud_cos/models/initiate_multipart_upload_result.dart';
import 'package:fluent_qcloud_cos/models/list_multipart_uploads.dart';
import 'package:fluent_qcloud_cos/models/list_part.dart';
import 'package:fluent_qcloud_cos/utils.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluent_qcloud_cos/fluent_qcloud_cos.dart';
import 'package:sync/sync.dart';

final String pathPrefix =
    Directory.current.path.endsWith('test') ? './assets/' : './test/assets/';

void main() async {
  final smallFilePath = "${pathPrefix}1000x1000-1MB.png";
  final largeFilePath = "${pathPrefix}1000x1000-21MB.png";

  final smallFile = XFile(smallFilePath);
  final largeFile = XFile(largeFilePath);

  await dotenv.load(fileName: ".env");

  final secretId = dotenv.env['SECRET_ID'];
  final secretKey = dotenv.env['SECRET_KEY'];
  final bucketName = dotenv.env['BUCKET_NAME'];
  final region = dotenv.env['REGION'];

  test('parse_InitiateMultipartUploadResult', () {
    final result =
        InitiateMultipartUploadResult.parse('''<InitiateMultipartUploadResult>
            <Bucket>examplebucket-1250000000</Bucket>
            <Key>exampleobject</Key>
            <UploadId>1585130821cbb7df1d11846c073ad648e8f33b087cec2381df437acdc833cf654b9ecc6361</UploadId>
</InitiateMultipartUploadResult>''');
    expect(result.uploadId,
        '1585130821cbb7df1d11846c073ad648e8f33b087cec2381df437acdc833cf654b9ecc6361');
  });

  test('parse_CompleteMultipartUploadResult', () {
    final result = CompleteMultipartUploadResult.parse(
        '''<CompleteMultipartUploadResult xmlns="http://www.qcloud.com/document/product/436/7751">
    <Location>http://examplebucket-1250000000.cos.ap-beijing.myqcloud.com/exampleobject</Location>
    <Bucket>examplebucket-1250000000</Bucket>
    <Key>exampleobject</Key>
    <ETag>&quot;aa259a62513358f69e98e72e59856d88-3&quot;</ETag>
</CompleteMultipartUploadResult>''');
    expect(result.location,
        'http://examplebucket-1250000000.cos.ap-beijing.myqcloud.com/exampleobject');
  });

  test('parse_ListMultipartUploadsResult', () {
    final result =
        ListMultipartUploadsResult.parse('''<ListMultipartUploadsResult>
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
</ListMultipartUploadsResult>''');
    expect(result.uploads.length, 3);
  });

  test('parse_ListPartsResult', () {
    final result =
        ListPartsResult.parse('''<?xml version="1.0" encoding="UTF-8" ?>
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
</ListPartsResult>''');
    expect(result.parts.length, 1);
  });

  test('putObjectSimple', () async {
    final wg = WaitGroup();
    wg.add();
    final handler =
        ObjectStoragePutObjectEventHandler(taskId: "putObjectSimple");
    handler.onFailed = (msg) {
      cosLog(msg.errorMessage ?? "未知错误");
      wg.done();
    };
    handler.onSuccess = (msg) {
      cosLog("上传成功");
      wg.done();
    };
    handler.onProgress = (msg) {
      cosLog("${msg.currentSize}/${msg.totalSize}");
    };
    await FluentQCloudCos.putObjectSimple(
      ObjectStoragePutObjectRequest(
        taskId: "putObjectSimple",
        file: smallFile,
        bucketName: bucketName!,
        objectName: "file-small.jpg",
        accessKeyId: secretId!,
        accessKeySecret: secretKey!,
        securityToken: "",
        expiredTime:
            DateTime.now().add(const Duration(days: 50)).millisecondsSinceEpoch,
        region: region!,
      ),
      handler: handler,
    );
    wg.wait();
  });

  test('putObjectMultiPart', () async {
    final wg = WaitGroup();
    wg.add();
    final handler =
        ObjectStoragePutObjectEventHandler(taskId: "putObjectSimple");
    handler.onFailed = (msg) {
      cosLog(msg.errorMessage ?? "未知错误");
      wg.done();
    };
    handler.onSuccess = (msg) {
      cosLog("上传成功");
      wg.done();
    };
    handler.onProgress = (msg) {
      cosLog("${msg.currentSize}/${msg.totalSize}");
    };
    await FluentQCloudCos.putObjectMultiPart(
      ObjectStoragePutObjectRequest(
        taskId: "putObjectMultiPart",
        file: largeFile,
        bucketName: bucketName!,
        objectName: "file-large.mp4",
        accessKeyId: secretId!,
        accessKeySecret: secretKey!,
        expiredTime:
            DateTime.now().add(const Duration(days: 50)).millisecondsSinceEpoch,
        region: region!,
        securityToken: '',
      ),
      handler: handler,
    );
    wg.wait();
  });

  test('initiateMultipartUpload', () async {
    final wg = WaitGroup();
    wg.add();
    final result = await FluentQCloudCos.initiateMultipartUpload(
      ObjectStoragePutObjectRequest(
        taskId: "initiateMultipartUpload",
        file: largeFile,
        bucketName: bucketName!,
        objectName: "file-large.mp4",
        accessKeyId: secretId!,
        accessKeySecret: secretKey!,
        expiredTime:
            DateTime.now().add(const Duration(days: 50)).millisecondsSinceEpoch,
        region: region!,
        securityToken: '',
      ),
    );
    cosLog(result.uploadId);
    wg.wait();
  });

  test('putObjectFileSizeLessThan20M', () async {
    final wg = WaitGroup();
    wg.add();
    final handler =
        ObjectStoragePutObjectEventHandler(taskId: "putObjectSimple");
    handler.onFailed = (msg) {
      cosLog(msg.errorMessage ?? "未知错误");
      wg.done();
    };
    handler.onSuccess = (msg) {
      cosLog("上传成功");
      wg.done();
    };
    handler.onProgress = (msg) {
      cosLog("${msg.currentSize}/${msg.totalSize}");
    };
    await FluentQCloudCos.putObject(
      ObjectStoragePutObjectRequest(
        taskId: "putObjectFileSizeLessThan20M",
        file: smallFile,
        bucketName: bucketName!,
        objectName: "file-small.jpg",
        accessKeyId: secretId!,
        accessKeySecret: secretKey!,
        securityToken: "",
        expiredTime:
            DateTime.now().add(const Duration(days: 50)).millisecondsSinceEpoch,
        region: region!,
      ),
      handler: handler,
    );
    wg.wait();
  });

  test('putObjectFileSizeMoreThan20M', () async {
    final wg = WaitGroup();
    wg.add();
    final handler =
        ObjectStoragePutObjectEventHandler(taskId: "putObjectSimple");
    handler.onFailed = (msg) {
      cosLog(msg.errorMessage ?? "未知错误");
      wg.done();
    };
    handler.onSuccess = (msg) {
      cosLog("上传成功");
      wg.done();
    };
    handler.onProgress = (msg) {
      cosLog("${msg.currentSize}/${msg.totalSize}");
    };
    await FluentQCloudCos.putObject(
      ObjectStoragePutObjectRequest(
        taskId: "putObjectFileSizeMoreThan20M",
        file: largeFile,
        bucketName: bucketName!,
        objectName: "file-small.jpg",
        accessKeyId: secretId!,
        accessKeySecret: secretKey!,
        securityToken: "",
        expiredTime:
            DateTime.now().add(const Duration(days: 50)).millisecondsSinceEpoch,
        region: region!,
      ),
      handler: handler,
    );
    wg.wait();
  });
}
