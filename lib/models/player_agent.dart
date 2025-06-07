import 'package:twitch_blueberry_war/models/agent.dart';

class PlayerAgent extends Agent {
  @override
  AgentShape get shape => AgentShape.circle;

  bool _isDestroyed = false;
  @override
  bool get isDestroyed => _isDestroyed;
  void destroy() {
    _isDestroyed = true;
    onDestroyed.notifyListeners((callback) => callback());
  }

  PlayerAgent({
    required super.id,
    required super.position,
    required super.velocity,
    required super.radius,
    required super.mass,
  });
}
