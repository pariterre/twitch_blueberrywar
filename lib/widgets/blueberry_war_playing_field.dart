import 'package:flutter/material.dart';
import 'package:twitch_blueberry_war/managers/blueberry_war_game_manager.dart';
import 'package:twitch_blueberry_war/models/letter_agent.dart';
import 'package:twitch_blueberry_war/models/player_agent.dart';
import 'package:twitch_blueberry_war/to_remove/any_dumb_stuff.dart';
import 'package:vector_math/vector_math.dart' as vector_math;

class BlueberryWarPlayingField extends StatelessWidget {
  const BlueberryWarPlayingField({super.key});

  @override
  Widget build(BuildContext context) {
    final gm = Managers.instance.miniGames.blueberryWar;

    return Stack(
      children: [
        ...gm.players.map((e) => _Player(player: e)),
        ...gm.letters.map((e) => _Letter(letter: e)),
      ],
    );
  }
}

class _Player extends StatefulWidget {
  const _Player({required this.player});

  final PlayerAgent player;

  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  vector_math.Vector2 previousPosition = vector_math.Vector2.zero();
  bool _isDragging = false;
  Offset? _dragStartPosition;
  Offset? _dragCurrentPosition;

  DateTime? _teleportStartTime;
  bool get _isTeleporting => _teleportStartTime != null;
  double _teleportingAnimationProgress = 0.0;

  BlueberryWarGameManager get _gm => Managers.instance.miniGames.blueberryWar;

  @override
  void initState() {
    super.initState();

    widget.player.onTeleport.listen(_hasStartedTeleporting);
    _gm.onClockTicked.listen(_clockTicked);
  }

  @override
  void dispose() {
    widget.player.onTeleport.cancel(_hasStartedTeleporting);
    _gm.onClockTicked.cancel(_clockTicked);

    super.dispose();
  }

  void _hasStartedTeleporting(
    vector_math.Vector2 from,
    vector_math.Vector2 to,
  ) {
    setState(() {
      _isDragging = false;
      _teleportStartTime = DateTime.now();
      _teleportingAnimationProgress = 0.0;
    });
  }

  void _performTeleport() {
    if (!_isTeleporting) return;
    final dt = DateTime.now().difference(_teleportStartTime!);
    _teleportingAnimationProgress =
        dt.inMilliseconds / _gm.teleportationDuration.inMilliseconds;
    if (_teleportingAnimationProgress >= 2.0) {
      _teleportStartTime = null;
      _teleportingAnimationProgress = 0.0;
    }
  }

  void _clockTicked(Duration dt) {
    _performTeleport();
    setState(() {});
  }

  ///
  /// Only allow dragging if not teleporting and not moving
  bool get _canBeDragged =>
      !(_isTeleporting ||
          widget.player.velocity.length > _gm.velocityThreshold);

  void _onDragStart(DragStartDetails details) {
    if (_isDragging) return;

    setState(() {
      _isDragging = true;
      // Start at the middle of the widget
      _dragStartPosition = Offset(
        widget.player.radius.x,
        widget.player.radius.y,
      );
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    setState(() {
      _dragCurrentPosition = details.localPosition;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;

    _dragCurrentPosition = details.localPosition;
    final newVelocity = (_dragStartPosition! - _dragCurrentPosition!) * 4;

    // Ensure the velocity is within a reasonable range
    final maxVelocity = 1000.0;
    double scale = 1.0;
    if (newVelocity.distance > maxVelocity) {
      scale = maxVelocity / newVelocity.distance;
    }
    widget.player.velocity = vector_math.Vector2(
      newVelocity.dx * scale,
      newVelocity.dy * scale,
    );

    setState(() {
      _isDragging = false;
      _dragStartPosition = null;
      _dragCurrentPosition = null;
    });
  }

  vector_math.Vector2 _getPlayerPosition() {
    if (!_isTeleporting || _teleportingAnimationProgress >= 1.0) {
      previousPosition = widget.player.position - widget.player.radius;
    }
    return previousPosition;
  }

  int _computeAlpha() {
    if (!_isTeleporting) return 255;
    if (_teleportingAnimationProgress <= 1.0) {
      // Fade out before teleporting
      return ((1.0 - _teleportingAnimationProgress) * 255).toInt();
    } else {
      // Fade in after teleporting
      return ((_teleportingAnimationProgress - 1.0) * 255.0).toInt();
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = _getPlayerPosition();
    final alpha = _computeAlpha();

    final mainWidget = Container(
      width: widget.player.radius.x * 2,
      height: widget.player.radius.y * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(alpha),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withAlpha(alpha), width: 2.0),
      ),
    );

    return Positioned(
      left: position.x,
      top: position.y,
      child: Stack(
        children: [
          _canBeDragged
              ? MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onVerticalDragStart: _onDragStart,
                  onHorizontalDragStart: _onDragStart,
                  onVerticalDragUpdate: _onDragUpdate,
                  onHorizontalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  onHorizontalDragEnd: _onDragEnd,
                  child: mainWidget,
                ),
              )
              : mainWidget,
          if (_isDragging)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: DragLinePainter(
                    start: _dragStartPosition,
                    current: _dragCurrentPosition,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DragLinePainter extends CustomPainter {
  final Offset? start;
  final Offset? current;

  DragLinePainter({this.start, this.current});

  @override
  void paint(Canvas canvas, Size size) {
    if (start == null || current == null) return;

    final paint =
        Paint()
          ..color = const Color.fromARGB(255, 15, 37, 48)
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke;

    canvas.drawLine(start!, current!, paint);
  }

  @override
  bool shouldRepaint(covariant DragLinePainter oldDelegate) {
    return start != oldDelegate.start || current != oldDelegate.current;
  }
}

class _Letter extends StatefulWidget {
  const _Letter({required this.letter});

  final LetterAgent letter;

  @override
  State<_Letter> createState() => _LetterState();
}

class _LetterState extends State<_Letter> {
  @override
  void initState() {
    super.initState();

    final gm = Managers.instance.miniGames.blueberryWar;
    gm.onClockTicked.listen(_clockTicked);
  }

  @override
  void dispose() {
    final gm = Managers.instance.miniGames.blueberryWar;
    gm.onClockTicked.cancel(_clockTicked);

    super.dispose();
  }

  void _clockTicked(Duration duration) => setState(() {});

  @override
  Widget build(BuildContext context) {
    return widget.letter.isDestroyed
        ? Container()
        : Positioned(
          left: widget.letter.position.x - widget.letter.radius.x,
          top: widget.letter.position.y - widget.letter.radius.y,
          child: Container(
            width: widget.letter.radius.x * 2,
            height: widget.letter.radius.y * 2,
            decoration: BoxDecoration(
              color: Colors.blue,
              border: Border.all(color: Colors.black, width: 2.0),
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: Center(
              child: Text(
                widget.letter.isWeak ? widget.letter.letter : '',
                style: TextStyle(fontSize: 30, color: Colors.black),
              ),
            ),
          ),
        );
  }
}
