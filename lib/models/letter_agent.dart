import 'package:twitch_blueberry_war/models/agent.dart';
import 'package:twitch_blueberry_war/to_remove/generic_listener.dart';

class LetterAgent extends Agent {
  int problemIndex;
  String letter;

  final onHit = GenericListener<Function>();
  final onDestroyed = GenericListener<Function>();

  int _numberOfHits = 0;
  void hit() {
    _numberOfHits++;
    onHit.notifyListeners((callback) => callback());
    if (isDestroyed) onDestroyed.notifyListeners((callback) => callback());
  }

  bool get isWeak => _numberOfHits == 1;
  bool get isDestroyed => _numberOfHits >= 2;

  @override
  AgentShape get shape => AgentShape.rectangle;

  LetterAgent({
    required super.id,
    required this.problemIndex,
    required this.letter,
    required super.position,
    required super.velocity,
    required super.radius,
    required super.mass,
  });
}
