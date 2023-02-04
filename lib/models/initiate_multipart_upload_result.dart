import 'package:fluent_qcloud_cos/utils.dart';
import 'package:xml/xml.dart';

class InitiateMultipartUploadResult {
  final String uploadId;
  InitiateMultipartUploadResult(this.uploadId);

  factory InitiateMultipartUploadResult.parse(String xmlContent) {
    var content = XmlDocument.parse(xmlContent);
    final uploadId = subElem(content.rootElement, "UploadId").innerText;
    return InitiateMultipartUploadResult(uploadId);
  }
}
