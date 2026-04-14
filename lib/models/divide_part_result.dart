class DividePartResult {
  final int partSize;
  final int partNumber;

  DividePartResult(this.partSize, this.partNumber);

  factory DividePartResult.parse(int filesize, int partSize) {
    if (filesize <= 0) {
      return DividePartResult(partSize, 0);
    }
    if (partSize <= 0) {
      throw ArgumentError.value(
          partSize, 'partSize', 'must be greater than 0');
    }
    int partNumber = filesize ~/ partSize;
    while (partNumber > 1000) {
      partSize = partSize * 2;
      partNumber = filesize ~/ partSize;
    }
    return DividePartResult(partSize, partNumber);
  }
}
