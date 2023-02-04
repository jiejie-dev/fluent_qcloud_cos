class DividePartResult {
  final int partSize;
  final int partNumber;

  DividePartResult(this.partSize, this.partNumber);

  factory DividePartResult.parse(int filesize) {
    int partSize = 1024 * 1024 * 20;
    int partNumber = filesize ~/ partSize;
    while (partNumber > 1000) {
      partSize = partSize * 2;
      partNumber = filesize ~/ partSize;
    }
    return DividePartResult(partSize, partNumber);
  }
}
