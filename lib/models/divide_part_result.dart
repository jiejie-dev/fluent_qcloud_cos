class DividePartResult {
  final int partSize;
  final int partNumber;

  DividePartResult(this.partSize, this.partNumber);

  factory DividePartResult.parse(int filesize, int partSize) {
    int partNumber = filesize ~/ partSize;
    while (partNumber > 1000) {
      partSize = partSize * 2;
      partNumber = filesize ~/ partSize;
    }
    return DividePartResult(partSize, partNumber);
  }
}
