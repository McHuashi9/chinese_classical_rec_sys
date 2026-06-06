class _TextReadState {
  int totalSeconds = 0;
  bool effectApplied = false;
}

class ReadTracker {
  final Map<int, _TextReadState> _states = {};
  static const int _maxEntries = 500;

  bool isTextRead(int textId) => _states[textId]?.effectApplied ?? false;

  bool hasUnrecordedReading(int? currentTextId) {
    if (currentTextId == null) return false;
    final state = _states[currentTextId];
    if (state == null) return false;
    return !state.effectApplied;
  }

  void ensureState(int textId) {
    _states.putIfAbsent(textId, () => _TextReadState());
    _trim();
  }

  void saveDuration(int textId, int seconds) {
    ensureState(textId);
    _states[textId]!.totalSeconds = seconds;
  }

  void markEffectApplied(int textId) {
    ensureState(textId);
    _states[textId]!.effectApplied = true;
  }

  void loadFromIds(List<int> ids) {
    for (final id in ids) {
      _states[id] = _TextReadState()..effectApplied = true;
    }
    _trim();
  }

  List<int> getAllTrackedIds() {
    return _states.entries
        .where((e) => e.value.effectApplied)
        .map((e) => e.key)
        .toList();
  }

  int totalSecondsFor(int textId) => _states[textId]?.totalSeconds ?? 0;

  void _trim() {
    while (_states.length > _maxEntries) {
      _states.remove(_states.keys.first);
    }
  }
}
