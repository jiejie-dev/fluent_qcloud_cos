import 'package:fluent_qcloud_cos/utils.dart';
import 'package:xml/xml.dart';

class ListMultipartUpload {
  final String key;
  final String uploadId;

  ListMultipartUpload(this.key, this.uploadId);
}

class ListMultipartUploadsResult {
  List<ListMultipartUpload> uploads = [];

  ListMultipartUploadsResult(this.uploads);

  ListMultipartUploadsResult.parse(String xmlContent) {
    final doc = XmlDocument.parse(xmlContent);
    final partNodes = doc.rootElement.childElements
        .where((element) => element.name.local == "Upload")
        .toList();
    for (var node in partNodes) {
      final part = ListMultipartUpload(
        subElem(node, "Key").innerText,
        subElem(node, "UploadId").innerText,
      );
      uploads.add(part);
    }
  }
}
