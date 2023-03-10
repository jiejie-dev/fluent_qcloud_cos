import 'dart:developer';
import 'dart:io';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
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

///ηζη­Ύε
String getSign(String method, String key,
    {required String secretId,
    required String secretKey,
    Map<String, String?> headers = const {},
    Map<String, String?> params = const {},
    DateTime? signTime,
    bool anonymous = false}) {
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

///ε€ηθ―·ζ±ε€΄εεζ°εθ‘¨
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

/// δ½Ώη¨HMAC-SHA1θ?‘η?ζθ¦
String hmacSha1(String msg, String key) {
  return hex.encode(Hmac(sha1, key.codeUnits).convert(msg.codeUnits).bytes);
}

Future<HttpClientRequest> getRequest(String method, String action,
    {required ObjectStoragePutObjectRequest putObjectRequest,
    Map<String, String?> params = const {},
    Map<String, String?> headers = const {},
    String? token,
    String scheme = "https"}) async {
  String urlParams =
      params.keys.toList().map((e) => "$e=${params[e] ?? ""}").join("&");
  if (urlParams.isNotEmpty) {
    urlParams = "?$urlParams";
  }
  HttpClient client = HttpClient();

  if (!action.startsWith("/")) {
    action = "/$action";
  }

  // "$scheme://$bucketName.cos.$region.myqcloud.com"
  final uri =
      "$scheme://${putObjectRequest.bucketName}.cos.${putObjectRequest.region}.myqcloud.com";
  var req = await client.openUrl(method, Uri.parse("$uri$action$urlParams"));

  headers.forEach((key, value) {
    req.headers.add(key, value ?? "");
  });
  Map<String, String> signHeaders = {};
  req.headers.forEach((name, values) {
    signHeaders[name] = values[0];
  });
  var sighn = getSign(
    method,
    action,
    secretId: putObjectRequest.accessKeyId,
    secretKey: putObjectRequest.accessKeySecret,
    params: params,
    headers: signHeaders,
  );
  req.headers.add("Authorization", sighn);
  if (token != null) {
    req.headers.add("x-cos-security-token", token);
  }
  return req;
}

Future<HttpClientResponse> getResponse(
  String method,
  String action, {
  required ObjectStoragePutObjectRequest putObjectRequest,
  Map<String, String?> params = const {},
  Map<String, String?> headers = const {},
  String? token,
  String scheme = "https",
}) async {
  var req = await getRequest(
    method,
    action,
    putObjectRequest: putObjectRequest,
    params: params,
    headers: headers,
    token: token,
    scheme: scheme,
  );
  var res = await req.close();
  return res;
}

Future<SplitFileChunksResult> splitFileIntoChunks(String filepath) async {
  final file = File(filepath);
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
