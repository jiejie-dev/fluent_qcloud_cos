import 'package:fluent_qcloud_cos/models/divide_part_result.dart';

/// 分快上传的块信息
class Chunk {
  final int number;
  final int offset;
  final int size;
  bool done = false;
  String? eTag;

  Chunk(this.number, this.offset, this.size, this.done);
}

/// 文件分块结果
class SplitFileChunksResult {
  final DividePartResult divider;
  final List<Chunk> chunks;
  SplitFileChunksResult(this.divider, this.chunks);
}
