import 'package:twitch_blueberry_war/models/agent.dart';

class PlayerAgent extends Agent {
  @override
  AgentShape get shape => AgentShape.circle;

  PlayerAgent({
    required super.id,
    required super.position,
    required super.velocity,
    required super.radius,
    required super.mass,
  });
}
