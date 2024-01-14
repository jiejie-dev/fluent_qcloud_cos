library fluent_qcloud_cos;

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:fluent_object_storage/fluent_object_storage.dart';
import 'package:fluent_qcloud_cos/constants.dart';
import 'package:fluent_qcloud_cos/exceptions.dart';
import 'package:fluent_qcloud_cos/models/chunks.dart';
import 'package:fluent_qcloud_cos/models/complete_multipart_upload.dart';
import 'package:fluent_qcloud_cos/models/initiate_multipart_upload_result.dart';
import 'package:fluent_qcloud_cos/models/list_multipart_uploads.dart';
import 'package:fluent_qcloud_cos/models/list_part.dart';
import 'package:fluent_qcloud_cos/utils.dart';
import 'package:mime/mime.dart';

/// TODO: 添加校验功能和一些边界值检测处理 参考官方 golang sdk:
/// https://github.com/tencentyun/cos-go-sdk-v5/blob/master/object.go
class FluentQCloudCos {
  /// 文件上传
  /// 当文件大于 20M 时自动启用分快上传, 否则使用简单文件上传
  static Future<void> putObject(ObjectStoragePutObjectRequest putObjectRequest,
      {ObjectStoragePutObjectEventHandler? handler}) async {
    final fileSize = await putObjectRequest.file.length();
    if (fileSize > defaultSimpleFileMaxSize) {
      await putObjectMultiPart(putObjectRequest, handler: handler);
    } else {
      await putObjectSimple(putObjectRequest, handler: handler);
    }
  }

  static Future<void> putObjectMultiPart(
      ObjectStoragePutObjectRequest putObjectRequest,
      {ObjectStoragePutObjectEventHandler? handler}) async {
    String? uploadId = await getResumableUploadId(putObjectRequest);
    if (uploadId == null) {
      final initResult = await initiateMultipartUpload(putObjectRequest);
      uploadId = initResult.uploadId;
    }
    final splitResult = await splitFileIntoChunks(putObjectRequest.file);
    final chunks = splitResult.chunks;
    final partsResult = await listParts(uploadId, putObjectRequest);
    for (var part in partsResult.parts) {
      int partNumber = part.partNumber;
      if (partNumber > splitResult.divider.partNumber) {
        throw COSException(400, "Part Number is not consistent");
      }

      partNumber = partNumber - 1;

      /// TODO: ETAG MD5 校验

      chunks[partNumber].done = true;
      chunks[partNumber].eTag = part.eTag;
    }
    final fileSize = await putObjectRequest.file.length();
    for (var chunk in chunks) {
      if (chunk.done) {
        continue;
      }
      final stream = putObjectRequest.file
          .openRead(chunk.offset, chunk.offset + chunk.size);
      final reader = ChunkedStreamReader(stream);
      final partData = await reader.readChunk(chunk.size);
      chunk.eTag =
          await uploadPart(uploadId, chunk.number, partData, putObjectRequest);
      await reader.cancel();

      if (handler?.onProgress != null) {
        cosLog('onProgress: ${chunk.offset + chunk.size}/$fileSize');
        handler!.onProgress!(ObjectStoragePutObjectResult(
          taskId: putObjectRequest.taskId,
          event: 'onProgress',
          currentSize: chunk.offset + chunk.size,
          totalSize: fileSize,
        ));
      }
    }
    await completeMultipartUpload(uploadId, chunks, putObjectRequest);
    if (handler?.onSuccess != null) {
      handler!.onSuccess!(ObjectStoragePutObjectResult(
          taskId: putObjectRequest.taskId, event: 'onSuccess'));
    }
  }

  static Future<String?> putObjectSimple(
      ObjectStoragePutObjectRequest putObjectRequest,
      {ObjectStoragePutObjectEventHandler? handler}) async {
    cosLog("putObjectSimple");
    int flength = await putObjectRequest.file.length();
    String? contentType = putObjectRequest.file.mimeType;
    contentType ??= lookupMimeType(putObjectRequest.file.name);

    var fs = putObjectRequest.file.openRead();
    var response = await request<String>(
      "PUT",
      putObjectRequest.objectName,
      putObjectRequest: putObjectRequest,
      headers: {
        "content-type": contentType,
        "content-length": flength.toString()
      },
      token: putObjectRequest.securityToken,
      stream: fs,
    );
    cosLog("request-id:${response.headers["x-cos-request-id"]?.first ?? ""}");
    if (response.statusCode != 200) {
      // String content = await response.transform(utf8.decoder).join("");
      cosLog("putObject error content: ${response.data}");
      throw COSException(response.statusCode!, response.data ?? "");
    }
    if (handler?.onSuccess != null) {
      handler!.onSuccess!(ObjectStoragePutObjectResult(
          taskId: putObjectRequest.taskId, event: 'onSuccess'));
    }
    return putObjectRequest.objectName;
  }

  /// 初始化分快上传
  static Future<InitiateMultipartUploadResult> initiateMultipartUpload(
      ObjectStoragePutObjectRequest putObjectRequest) async {
    final resp = await request<String>(
      'POST',
      putObjectRequest.objectName,
      putObjectRequest: putObjectRequest,
      params: {"uploads": ""},
      token: putObjectRequest.securityToken,
    );
    // final xmlContent = await resp.transform(utf8.decoder).join("");
    if (resp.statusCode != 200) {
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
    return InitiateMultipartUploadResult.parse(resp.data!);
  }

  /// 上传分块
  static Future<String?> uploadPart(
    String uploadId,
    int partNumber,
    List<int> partData,
    ObjectStoragePutObjectRequest putObjectRequest,
  ) async {
    String? contentType = putObjectRequest.file.mimeType;
    contentType ??= lookupMimeType(putObjectRequest.file.name);

    final fs = Stream.fromIterable(partData.map((e) => [e]));
    final resp = await request<String>(
      'PUT',
      putObjectRequest.objectName,
      putObjectRequest: putObjectRequest,
      params: {'uploadId': uploadId, 'partNumber': partNumber.toString()},
      headers: {
        "content-type": contentType,
        "content-length": partData.length.toString(),
      },
      token: putObjectRequest.securityToken,
      stream: fs,
    );
    // final xmlContent = await resp.transform(utf8.decoder).join("");
    if (resp.statusCode != 200) {
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
    return resp.headers.value('ETag');
  }

  /// 完成分块上传
  static Future<void> completeMultipartUpload(
    String uploadId,
    List<Chunk> chunks,
    ObjectStoragePutObjectRequest putObjectRequest,
  ) async {
    final payload = CompleteMultipartUpload(chunks);
    final resp = await request(
      'POST',
      putObjectRequest.objectName,
      putObjectRequest: putObjectRequest,
      params: {'uploadId': uploadId},
      token: putObjectRequest.securityToken,
      data: utf8.encode(payload.xmlContent()),
    );

    // final resultXmlContent = await resp.transform(utf8.decoder).join("");
    if (resp.statusCode != 200) {
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
  }

  /// 取消分块上传
  /// Abort Multipart Upload 用来实现舍弃一个分块上传并删除已上传的块。
  /// 当您调用 Abort Multipart Upload 时，如果有正在使用这个 Upload Parts 上传块的请求，
  /// 则 Upload Parts 会返回失败。当该 UploadId 不存在时，会返回404 NoSuchUpload。
  static Future<void> abortMultipartUpload() async {}

  static Future<ListMultipartUploadsResult> listMultipartUploads(
      ObjectStoragePutObjectRequest putObjectRequest) async {
    final resp = await request<String>(
      'GET',
      '',
      putObjectRequest: putObjectRequest,
      params: {'prefix': putObjectRequest.objectName, 'uploads': ''},
      token: putObjectRequest.securityToken,
    );
    // final xmlContent = await resp.transform(utf8.decoder).join("");
    if (resp.statusCode != 200) {
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
    return ListMultipartUploadsResult.parse(resp.data!);
  }

  /// 获取未完成的分块上传ID UploadId
  static Future<String?> getResumableUploadId(
      ObjectStoragePutObjectRequest putObjectRequest) async {
    try {
      final uploadsResult = await listMultipartUploads(putObjectRequest);
      if (uploadsResult.uploads.isEmpty) {
        return null;
      }
      return uploadsResult.uploads
          .lastWhere((element) => element.key == putObjectRequest.objectName)
          .uploadId;
    } catch (e) {
      return null;
    }
  }

  /// List Parts 用来查询特定分块上传中的已上传的块，
  /// 即罗列出指定 UploadId 所属的所有已上传成功的分块。
  static Future<ListPartsResult> listParts(
    String uploadId,
    ObjectStoragePutObjectRequest putObjectRequest,
  ) async {
    final resp = await request<String>(
      'GET',
      putObjectRequest.objectName,
      putObjectRequest: putObjectRequest,
      params: {'uploadId': uploadId},
      token: putObjectRequest.securityToken,
    );
    // final xmlContent = await resp.transform(utf8.decoder).join("");
    if (resp.statusCode != 200) {
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
    return ListPartsResult.parse(resp.data!);
  }
}
