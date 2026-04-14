library fluent_qcloud_cos;

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:fluent_object_storage/fluent_object_storage.dart';
import 'package:fluent_qcloud_cos/exceptions.dart';
import 'package:fluent_qcloud_cos/models/chunks.dart';
import 'package:fluent_qcloud_cos/models/complete_multipart_upload.dart';
import 'package:fluent_qcloud_cos/models/initiate_multipart_upload_result.dart';
import 'package:fluent_qcloud_cos/models/list_multipart_uploads.dart';
import 'package:fluent_qcloud_cos/models/list_part.dart';
import 'package:fluent_qcloud_cos/utils.dart';
import 'package:mime/mime.dart';

class FluentQCloudCos {
  /// Maximum retry count for individual part upload failures.
  static int maxPartRetries = 3;

  /// 文件上传
  /// 根据文件大小自动选择简单上传或分块上传
  static Future<void> putObject(
    ObjectStoragePutObjectRequest request, {
    ObjectStoragePutObjectEventHandler? handler,
  }) async {
    final fileSize = request.file.size;
    if (fileSize <= 0) {
      throw COSException(400, "File size must be greater than 0");
    }
    if (fileSize > request.divisionForUpload) {
      await putObjectMultiPart(request, handler: handler);
    } else {
      await putObjectSimple(request, handler: handler);
    }
  }

  static Future<void> putObjectMultiPart(
    ObjectStoragePutObjectRequest request, {
    ObjectStoragePutObjectEventHandler? handler,
  }) async {
    final fileSize = request.file.size;
    if (fileSize <= 0) {
      throw COSException(400, "File size must be greater than 0");
    }

    try {
      String? uploadId = await getResumableUploadId(request);
      if (uploadId == null) {
        final initResult = await initiateMultipartUpload(request);
        uploadId = initResult.uploadId;
      }
      final splitResult = await splitFileIntoChunks(
        request.file,
        request.sliceSizeForUpload,
      );
      final chunks = splitResult.chunks;
      if (chunks.isEmpty) {
        throw COSException(400, "File produced no chunks for upload");
      }
      final partsResult = await listParts(uploadId, request);
      for (var part in partsResult.parts) {
        int partNumber = part.partNumber;
        if (partNumber > splitResult.divider.partNumber) {
          throw COSException(400, "Part Number is not consistent");
        }

        final partIndex = partNumber - 1;
        chunks[partIndex].done = true;
        chunks[partIndex].eTag = part.eTag;
      }

      Stream<List<int>>? stream = request.file.readStream;
      if (stream == null && request.file.bytes != null) {
        stream = Stream.value(request.file.bytes!);
      }
      if (stream == null && request.file.path != null) {
        stream = File(request.file.path!).openRead();
      }
      if (stream == null) {
        throw COSException(400, "File has neither readStream, bytes, nor path");
      }

      final reader = ChunkedStreamReader(stream);
      try {
        for (var chunk in chunks) {
          final partData = await reader.readChunk(chunk.size);
          if (chunk.done) {
            continue;
          }

          chunk.eTag = await _uploadPartWithRetry(
            uploadId,
            chunk.number,
            partData,
            request,
          );

          handler?.onProgress?.call(
            ObjectStoragePutObjectResult(
              taskId: request.taskId,
              event: 'onProgress',
              currentSize: chunk.offset + chunk.size,
              totalSize: fileSize,
            ),
          );
        }
      } finally {
        await reader.cancel();
      }

      await completeMultipartUpload(uploadId, chunks, request);
      handler?.onSuccess?.call(
        ObjectStoragePutObjectResult(
          taskId: request.taskId,
          event: 'onSuccess',
        ),
      );
    } catch (e) {
      handler?.onFailed?.call(
        ObjectStoragePutObjectResult(
          taskId: request.taskId,
          event: 'onFailed',
          errorMessage: e.toString(),
        ),
      );
      rethrow;
    }
  }

  static Future<String?> putObjectSimple(
    ObjectStoragePutObjectRequest request, {
    ObjectStoragePutObjectEventHandler? handler,
  }) async {
    try {
      cosLog("putObjectSimple");
      int fileSize = request.file.size;
      String? contentType = lookupMimeType(request.file.name);

      Stream<List<int>>? stream = request.file.readStream;
      Object? data = request.file.bytes;
      if (data == null && stream == null && request.file.path != null) {
        stream = File(request.file.path!).openRead();
      }
      if (data == null && stream == null) {
        throw COSException(400, "File has neither readStream, bytes, nor path");
      }

      final response = await cosRequest<String>(
        "PUT",
        request.objectName,
        putObjectRequest: request,
        headers: {
          "content-type": contentType,
          "content-length": fileSize.toString(),
        },
        token: request.securityToken,
        stream: stream,
        data: data,
      );
      cosLog("request-id:${response.headers["x-cos-request-id"]?.first ?? ""}");
      if (response.statusCode != 200) {
        cosLog("putObject error content: ${response.data}");
        throw COSException(response.statusCode!, response.data ?? "");
      }

      handler?.onProgress?.call(
        ObjectStoragePutObjectResult(
          taskId: request.taskId,
          event: 'onProgress',
          currentSize: fileSize,
          totalSize: fileSize,
        ),
      );

      handler?.onSuccess?.call(
        ObjectStoragePutObjectResult(
          taskId: request.taskId,
          event: 'onSuccess',
        ),
      );
      return request.objectName;
    } catch (e) {
      handler?.onFailed?.call(
        ObjectStoragePutObjectResult(
          taskId: request.taskId,
          event: 'onFailed',
          errorMessage: e.toString(),
        ),
      );
      rethrow;
    }
  }

  /// 初始化分块上传
  static Future<InitiateMultipartUploadResult> initiateMultipartUpload(
    ObjectStoragePutObjectRequest request,
  ) async {
    final resp = await cosRequest<String>(
      'POST',
      request.objectName,
      putObjectRequest: request,
      params: {"uploads": ""},
      token: request.securityToken,
    );
    if (resp.statusCode != 200) {
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
    return InitiateMultipartUploadResult.parse(resp.data!);
  }

  /// 上传分块（带重试）
  static Future<String?> _uploadPartWithRetry(
    String uploadId,
    int partNumber,
    List<int> partData,
    ObjectStoragePutObjectRequest request,
  ) async {
    for (var attempt = 1; attempt <= maxPartRetries; attempt++) {
      try {
        return await uploadPart(uploadId, partNumber, partData, request);
      } catch (e) {
        if (attempt == maxPartRetries) rethrow;
        cosLog(
          "Part $partNumber upload failed (attempt $attempt/$maxPartRetries), retrying...",
        );
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    return null;
  }

  /// 上传分块
  static Future<String?> uploadPart(
    String uploadId,
    int partNumber,
    List<int> partData,
    ObjectStoragePutObjectRequest request,
  ) async {
    String? contentType = lookupMimeType(request.file.name);

    final fs = Stream.value(partData);
    final resp = await cosRequest<String>(
      'PUT',
      request.objectName,
      putObjectRequest: request,
      params: {'uploadId': uploadId, 'partNumber': partNumber.toString()},
      headers: {
        "content-type": contentType,
        "content-length": partData.length.toString(),
      },
      token: request.securityToken,
      stream: fs,
    );
    if (resp.statusCode != 200) {
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
    return resp.headers.value('ETag');
  }

  /// 完成分块上传
  static Future<void> completeMultipartUpload(
    String uploadId,
    List<Chunk> chunks,
    ObjectStoragePutObjectRequest request,
  ) async {
    final payload = CompleteMultipartUpload(chunks);
    final xmlContent = payload.xmlContent();
    cosLog(xmlContent);
    final resp = await cosRequest<String>(
      'POST',
      request.objectName,
      putObjectRequest: request,
      params: {'uploadId': uploadId},
      token: request.securityToken,
      data: xmlContent,
      headers: {"content-type": "application/xml"},
    );
    if (resp.statusCode != 200) {
      cosLog("completeMultipartUpload error: ${resp.data}");
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
  }

  /// 取消分块上传
  /// Abort Multipart Upload 用来实现舍弃一个分块上传并删除已上传的块。
  /// 当您调用 Abort Multipart Upload 时，如果有正在使用这个 Upload Parts 上传块的请求，
  /// 则 Upload Parts 会返回失败。当该 UploadId 不存在时，会返回404 NoSuchUpload。
  static Future<void> abortMultipartUpload(
    String uploadId,
    ObjectStoragePutObjectRequest request,
  ) async {
    final resp = await cosRequest<String>(
      'DELETE',
      request.objectName,
      putObjectRequest: request,
      params: {'uploadId': uploadId},
      token: request.securityToken,
    );
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
  }

  static Future<ListMultipartUploadsResult> listMultipartUploads(
    ObjectStoragePutObjectRequest request,
  ) async {
    final resp = await cosRequest<String>(
      'GET',
      '',
      putObjectRequest: request,
      params: {'prefix': request.objectName, 'uploads': ''},
      token: request.securityToken,
    );
    if (resp.statusCode != 200) {
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
    return ListMultipartUploadsResult.parse(resp.data!);
  }

  /// 获取未完成的分块上传ID UploadId
  static Future<String?> getResumableUploadId(
    ObjectStoragePutObjectRequest request,
  ) async {
    try {
      final uploadsResult = await listMultipartUploads(request);
      if (uploadsResult.uploads.isEmpty) {
        return null;
      }
      final matches = uploadsResult.uploads.where(
        (element) => element.key == request.objectName,
      );
      if (matches.isEmpty) return null;
      return matches.last.uploadId;
    } on COSException {
      return null;
    }
  }

  /// List Parts 用来查询特定分块上传中的已上传的块，
  /// 即罗列出指定 UploadId 所属的所有已上传成功的分块。
  static Future<ListPartsResult> listParts(
    String uploadId,
    ObjectStoragePutObjectRequest request,
  ) async {
    final resp = await cosRequest<String>(
      'GET',
      request.objectName,
      putObjectRequest: request,
      params: {'uploadId': uploadId},
      token: request.securityToken,
    );
    if (resp.statusCode != 200) {
      throw COSException(resp.statusCode!, resp.data ?? "");
    }
    return ListPartsResult.parse(resp.data!);
  }
}
