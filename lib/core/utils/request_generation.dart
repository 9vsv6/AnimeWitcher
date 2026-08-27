/// Tracks the currently authoritative request for a stateful UI flow.
///
/// Starting a refresh invalidates earlier requests. Callers can then ignore a
/// completion from an obsolete request without cancelling the underlying I/O.
class RequestGeneration {
  int _current = 0;

  int begin() => ++_current;

  int get current => _current;

  bool isCurrent(int generation) => generation == _current;
}
