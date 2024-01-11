import 'dart:developer';
import 'package:convert/convert.dart';
import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fluent_object_storage/fluent_object_storage.dart';
import 'package:fluent_qcloud_cos/models/chunks.dart';
import 'package:fluent_qcloud_cos/models/divide_part_result.dart';
import 'package:xml/xml.dart';

cosLog(String msg) {
  log(msg, name: "Fluent QCloud COS");
}

XmlElement subElem(XmlElement node, String name) {
  return node.childElements.singleWhere((node) => node.name.local == name);
}

///生成签名
String getSign(
  String method,
  String key, {
  required String secretId,
  required String secretKey,
  Map<String, String?> headers = const {},
  Map<String, String?> params = const {},
  DateTime? signTime,
  bool anonymous = false,
}) {
  if (anonymous) {
    return "";
  } else {
    signTime = signTime ?? DateTime.now();
    int startSignTime = signTime.millisecondsSinceEpoch ~/ 1000 - 60;
    int stopSignTime = signTime.millisecondsSinceEpoch ~/ 1000 + 120;
    String keyTime = "$startSignTime;$stopSignTime";
    cosLog("keyTime=$keyTime");
    String signKey = hmacSha1(keyTime, secretKey);
    cosLog("signKey=$signKey");

    var lap = getListAndParameters(params);
    String urlParamList = lap[0];
    String httpParameters = lap[1];
    cosLog("urlParamList=$urlParamList");
    cosLog("httpParameters=$httpParameters");

    lap = getListAndParameters(filterHeaders(headers));
    String headerList = lap[0];
    String httpHeaders = lap[1];
    cosLog("headerList=$headerList");
    cosLog("httpHeaders=$httpHeaders");

    String httpString =
        "${method.toLowerCase()}\n$key\n$httpParameters\n$httpHeaders\n";
    cosLog("httpString=$httpString");
    String stringToSign =
        "sha1\n$keyTime\n${hex.encode(sha1.convert(httpString.codeUnits).bytes)}\n";
    cosLog("stringToSign=$stringToSign");
    String signature = hmacSha1(stringToSign, signKey);
    cosLog("signature=$signature");
    String res =
        "q-sign-algorithm=sha1&q-ak=$secretId&q-sign-time=$keyTime&q-key-time=$keyTime&q-header-list=$headerList&q-url-param-list=$urlParamList&q-signature=$signature";
    cosLog("Authorization=$res");
    return res;
  }
}

filterHeaders(Map<String, String?> src) {
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
    if (validHeaders.contains(key) || key.toLowerCase().startsWith("x")) {
      if (key == "content-length" && src["content-length"] == "0") {
        continue;
      }
      res[key] = src[key];
    }
  }
  return res;
}

///处理请求头和参数列表
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

Future<Response<T>> request<T>(
  String method,
  String action, {
  required ObjectStoragePutObjectRequest putObjectRequest,
  Map<String, String?> params = const {},
  Map<String, String?> headers = const {},
  String? token,
  String scheme = "https",
  Stream? stream,
  Object? data,
}) async {
  String urlParams =
      params.keys.toList().map((e) => "$e=${params[e] ?? ""}").join("&");
  if (urlParams.isNotEmpty) {
    urlParams = "?$urlParams";
  }
  final dio = Dio();

  if (!action.startsWith("/")) {
    action = "/$action";
  }

  // "$scheme://$bucketName.cos.$region.myqcloud.com"
  final uri =
      "$scheme://${putObjectRequest.bucketName}.cos.${putObjectRequest.region}.myqcloud.com";
  var sighn = getSign(
    method,
    action,
    secretId: putObjectRequest.accessKeyId,
    secretKey: putObjectRequest.accessKeySecret,
    params: params,
    headers: headers,
  );
  final reqHeaders = headers.map((key, value) => MapEntry(key, value ?? ""));
  reqHeaders["Authorization"] = sighn;
  if (token != null) {
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
      ),
    );
    return resp;
  } catch (e) {
    cosLog("request error: $e");
    rethrow;
  }
}

Future<SplitFileChunksResult> splitFileIntoChunks(XFile file) async {
  final filesize = await file.length();
  final divider = DividePartResult.parse(filesize);
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
