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

  test('pagination can reuse the current generation until the next refresh', () {
    final requests = RequestGeneration();
    final refresh = requests.begin();
    final nextPage = requests.current;

    expect(nextPage, refresh);
    expect(requests.isCurrent(nextPage), isTrue);

    requests.begin();
    expect(requests.isCurrent(nextPage), isFalse);
  });
}
