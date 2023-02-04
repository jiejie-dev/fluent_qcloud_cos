import 'package:fluent_qcloud_cos/models/chunks.dart';
import 'package:fluent_qcloud_cos/utils.dart';
import 'package:xml/xml.dart';

class MultipartUploadPart {
  final int partNumber;
  final String eTag;

  MultipartUploadPart(this.partNumber, this.eTag);
}

class CompleteMultipartUpload {
  final List<Chunk> chunks;

  CompleteMultipartUpload(this.chunks);

  String xmlContent() {
    final builder = XmlBuilder();
    builder.element("CompleteMultipartUpload", nest: () {
      for (var chunk in chunks) {
        builder.element("Part", nest: () {
          builder.element("PartNumber", nest: () {
            builder.text(chunk.number.toString());
          });
          builder.element("ETag", nest: () {
            builder.text(chunk.eTag ?? "");
          });
        });
      }
    });
    return builder.buildDocument().toXmlString();
  }
}

class CompleteMultipartUploadResult {
  final String location;
  final String bucket;
  final String key;
  final String eTag;

  CompleteMultipartUploadResult(
      this.location, this.bucket, this.key, this.eTag);

  factory CompleteMultipartUploadResult.parse(String xmlContent) {
    var content = XmlDocument.parse(xmlContent);
    return CompleteMultipartUploadResult(
      subElem(content.rootElement, "Location").innerText,
      subElem(content.rootElement, "Bucket").innerText,
      subElem(content.rootElement, "Key").innerText,
      subElem(content.rootElement, "ETag").innerText,
    );
  }
}
