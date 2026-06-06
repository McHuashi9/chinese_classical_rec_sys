import 'package:flutter/foundation.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/recommendation.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';

class UserController extends ChangeNotifier {
  KnowledgeTracker? _tracker;
  final ReadTracker _readTracker;

  User? _user;
  List<RecommendResult> _recommendations = [];

  UserController(this._readTracker);

  void initTracker(KnowledgeTracker tracker) { _tracker = tracker; }

  User? get user => _user;
  double get averageAbility => _user?.averageAbility ?? 0.3;
  List<RecommendResult> get recommendations => _recommendations;

  void getRecommendations(RecommendationEngine engine, List<ChineseText> textCache, int topK) {
    if (_user == null) return;
    _recommendations = engine.getRecommendations(_user!, topK, textCache);
    notifyListeners();
  }

  bool applyReadEffect(int textId, double seconds) {
    if (_user == null || _tracker == null) return false;
    final updated = _tracker!.applyRead(_user!, textId, seconds);
    return _updateUser(updated);
  }

  void recordReading(int textId, double seconds) {
    if (_user == null || _tracker == null) return;
    final updated = _tracker!.applyRead(_user!, textId, seconds);
    if (_updateUser(updated)) {
      _readTracker.markEffectApplied(textId);
      notifyListeners();
    }
  }

  bool _updateUser(User? updated) {
    if (updated == null) return false;
    _user!.dispose();
    final pruned = _tracker!.prune(updated);
    if (pruned != null) {
      _user = pruned;
      updated.dispose();
    } else {
      _user = updated;
    }
    return true;
  }

  void setUser(User? user) {
    _user = user;
  }

  @override
  void dispose() {
    _user?.dispose();
    super.dispose();
  }
}
