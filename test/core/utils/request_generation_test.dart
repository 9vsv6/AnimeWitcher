import 'package:animewitcher/core/utils/request_generation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a newer refresh invalidates the preceding request', () {
    final requests = RequestGeneration();

    final first = requests.begin();
    expect(requests.isCurrent(first), isTrue);

    final second = requests.begin();
    expect(requests.isCurrent(first), isFalse);
    expect(requests.current, second);
    expect(requests.isCurrent(second), isTrue);
  });
}
