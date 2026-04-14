import 'dart:developer';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fluent_object_storage/fluent_object_storage.dart';
import 'package:fluent_qcloud_cos/models/chunks.dart';
import 'package:fluent_qcloud_cos/models/divide_part_result.dart';
import 'package:platform_file/platform_file.dart';
import 'package:xml/xml.dart';

/// Set to true to enable debug logging (includes sensitive signing data).
/// Disabled by default to avoid leaking secrets in production.
bool cosDebugLogEnabled = false;

void cosLog(String msg) {
  if (cosDebugLogEnabled) {
    log(msg, name: "Fluent QCloud COS");
  }
}

XmlElement subElem(XmlElement node, String name) {
  return node.childElements.singleWhere((node) => node.name.local == name);
}

/// Dio factory — override in tests via [cosCreateDio] assignment.
Dio Function() cosCreateDio = defaultCreateDio;

Dio defaultCreateDio() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 120),
    ));

/// 生成签名
String getSign(
  String method,
  String key, {
  required String secretId,
  required String secretKey,
  Map<String, String?> headers = const {},
  Map<String, String?> params = const {},
  DateTime? signTime,
  bool anonymous = false,
  Duration signDuration = const Duration(hours: 1),
}) {
  if (anonymous) {
    return "";
  }
  signTime = signTime ?? DateTime.now();
  int startSignTime = signTime.millisecondsSinceEpoch ~/ 1000 - 60;
  int stopSignTime =
      signTime.millisecondsSinceEpoch ~/ 1000 + signDuration.inSeconds;
  String keyTime = "$startSignTime;$stopSignTime";
  String signKey = hmacSha1(keyTime, secretKey);

  var lap = getListAndParameters(params);
  String urlParamList = lap[0];
  String httpParameters = lap[1];

  lap = getListAndParameters(filterHeaders(headers));
  String headerList = lap[0];
  String httpHeaders = lap[1];

  String httpString =
      "${method.toLowerCase()}\n$key\n$httpParameters\n$httpHeaders\n";
  String stringToSign =
      "sha1\n$keyTime\n${hex.encode(sha1.convert(httpString.codeUnits).bytes)}\n";
  String signature = hmacSha1(stringToSign, signKey);
  String res =
      "q-sign-algorithm=sha1&q-ak=$secretId&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=$headerList&q-url-param-list=$urlParamList&q-signature=$signature";
  cosLog("Authorization=$res");
  return res;
}

Map<String, String?> filterHeaders(Map<String, String?> src) {
  Map<String, String?> res = {};
  const validHeaders = {
    "cache-control",
    "content-disposition",
    "content-encoding",
    "content-type",
    "expires",
    "content-md5",
    "content-length",
    "host"
  };
  for (String key in src.keys) {
    final lowerKey = key.toLowerCase();
    if (validHeaders.contains(lowerKey) || lowerKey.startsWith("x-cos-")) {
      if (lowerKey == "content-length" && src[key] == "0") {
        continue;
      }
      res[key] = src[key];
    }
  }
  return res;
}

/// 处理请求头和参数列表
List<String> getListAndParameters(Map<String, String?> params) {
  params = params.map((key, value) => MapEntry(
      Uri.encodeComponent(key).toLowerCase(),
      Uri.encodeComponent(value ?? "")));

  var keys = params.keys.toList();
  keys.sort();
  String urlParamList = keys.join(";");
  String httpParameters = keys.map((e) => "$e=${params[e] ?? ""}").join("&");
  return [urlParamList, httpParameters];
}

/// 使用HMAC-SHA1计算摘要
String hmacSha1(String msg, String key) {
  return hex.encode(Hmac(sha1, key.codeUnits).convert(msg.codeUnits).bytes);
}

Future<Response<T>> cosRequest<T>(
  String method,
  String action, {
  required ObjectStoragePutObjectRequest putObjectRequest,
  Map<String, String?> params = const {},
  Map<String, String?> headers = const {},
  String? token,
  String scheme = "https",
  Stream<List<int>>? stream,
  Object? data,
}) async {
  final dio = cosCreateDio();

  if (!action.startsWith("/")) {
    action = "/$action";
  }

  final uri =
      "$scheme://${putObjectRequest.bucketName}.cos.${putObjectRequest.accelerate ? "accelerate" : putObjectRequest.region}.myqcloud.com";
  var sign = getSign(
    method,
    action,
    secretId: putObjectRequest.accessKeyId,
    secretKey: putObjectRequest.accessKeySecret,
    params: params,
    headers: headers,
  );
  final reqHeaders = headers.map((key, value) => MapEntry(key, value ?? ""));
  reqHeaders["Authorization"] = sign;
  if (token != null && token.isNotEmpty) {
    reqHeaders["x-cos-security-token"] = token;
  }
  try {
    final resp = await dio.request<T>(
      "$uri$action",
      queryParameters: params,
      data: data ?? stream,
      options: Options(
        method: method,
        headers: reqHeaders,
        validateStatus: (status) => true,
      ),
    );
    return resp;
  } catch (e) {
    cosLog("request error: $e");
    rethrow;
  }
}

Future<SplitFileChunksResult> splitFileIntoChunks(
    PlatformFile file, int partSize) async {
  final filesize = file.size;
  if (filesize <= 0) {
    return SplitFileChunksResult(DividePartResult(partSize, 0), []);
  }
  final divider = DividePartResult.parse(filesize, partSize);
  final List<Chunk> chunks = [];
  for (var i = 0; i < divider.partNumber; i++) {
    final number = i + 1;
    final offset = i * divider.partSize;
    final size = divider.partSize;
    final chunk = Chunk(number, offset, size, false);
    chunks.add(chunk);
  }
  if (filesize % divider.partSize > 0) {
    final number = chunks.length + 1;
    final offset = chunks.length * divider.partSize;
    final size = filesize % divider.partSize;
    final chunk = Chunk(number, offset, size, false);
    chunks.add(chunk);

    return SplitFileChunksResult(
        DividePartResult(divider.partSize, divider.partNumber + 1), chunks);
  }
  return SplitFileChunksResult(divider, chunks);
}
