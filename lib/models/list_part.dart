import 'package:fluent_qcloud_cos/utils.dart';
import 'package:xml/xml.dart';

class ListPart {
  final int partNumber;
  final String lastModified;
  final String eTag;
  final int size;
  ListPart(this.partNumber, this.lastModified, this.eTag, this.size);
}

class ListPartsResult {
  List<ListPart> parts = [];
  ListPartsResult(this.parts);

  ListPartsResult.parse(String xmlContent) {
    final doc = XmlDocument.parse(xmlContent);
    final partNodes = doc.rootElement.childElements
        .where((element) => element.name.local == "Part")
        .toList();
    for (var node in partNodes) {
      final part = ListPart(
        int.parse(subElem(node, "PartNumber").innerText),
        subElem(node, "LastModified").innerText,
        subElem(node, "ETag").innerText,
        int.parse(subElem(node, "Size").innerText),
      );
      parts.add(part);
    }
  }
}
