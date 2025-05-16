class QZoneAlgorithms {
  /// Calculates the g_tk value from p_skey.
  /// Corresponds to the gtk(skey string) function in Go.
  static String calculateGtk(String pSkey) {
    int hash = 5381;
    for (int i = 0; i < pSkey.length; i++) {
      hash += (hash << 5) + pSkey.codeUnitAt(i);
    }
    return (hash & 2147483647).toString();
  }

  /// Calculates the ptqrtoken from qrsig.
  /// Corresponds to the ptqrtoken(qrsig string) function in Go.
  static String calculatePtqrtoken(String qrsig) {
    int e = 0;
    for (int i = 0; i < qrsig.length; i++) {
      // In Dart, char codes are accessed via codeUnitAt(i)
      e += (e << 5) + qrsig.codeUnitAt(i);
    }
    // In Dart, bitwise AND with a mask ensures the result fits within a signed 32-bit integer range,
    // then we take the positive part if it's meant to be an unsigned-like 31-bit positive number.
    // The Go code `2147483647 & e` effectively does this.
    return (e & 2147483647).toString();
  }
} 