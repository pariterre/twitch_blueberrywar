import 'dart:async';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:twitch_blueberry_war/models/agent.dart';
import 'package:twitch_blueberry_war/models/letter_agent.dart';
import 'package:twitch_blueberry_war/models/player_agent.dart';
import 'package:twitch_blueberry_war/models/serializable_treasure_hunt_game_state.dart';
import 'package:twitch_blueberry_war/to_remove/any_dumb_stuff.dart';
import 'package:twitch_blueberry_war/to_remove/generic_listener.dart';
import 'package:vector_math/vector_math.dart';

final _logger = Logger('BlueberryWarGameManager');
final _random = Random();

final _dictionary = DictionaryManager.wordsWithAtLeast(6).toList();

///
/// Easy accessors translating index into row/col pair or row/col pair into
/// index

class BlueberryWarGameManager implements MiniGameManager {
  ///
  /// Duration of each game tick (16ms for 60 FPS)
  final Duration _tickDuration = const Duration(milliseconds: 16);
  DateTime _lastTick = DateTime.now();
  Vector2 fieldSize = Vector2(1920, 1080);

  ///
  /// Whether the game manager is initialized
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  bool _isGameOver = false;
  bool get isGameOver => _isGameOver;
  bool? _hasWon = false;
  bool get hasWon => _hasWon!;

  ///
  /// Time related stuff for the game
  Timer? _gameTimer;
  DateTime? _startTime;
  DateTime get startTime => _startTime ?? DateTime.now();
  DateTime? _finalTime;
  DateTime? get finalTime => _finalTime;
  final Duration _roundDuration = const Duration(seconds: 30);
  Duration get timeRemaining =>
      _roundDuration -
      (_finalTime ?? DateTime.now()).difference(_startTime ?? DateTime.now());

  ///
  /// Current problem for the game
  SerializableLetterProblem? _problem;
  SerializableLetterProblem get problem => _problem!;

  ///
  /// List of agents in the game (players and letters)
  final allAgents = <Agent>[];
  List<LetterAgent> get letters =>
      allAgents.whereType<LetterAgent>().toList(growable: false);
  final initialPlayerCount = 10;
  List<PlayerAgent> get players =>
      allAgents.whereType<PlayerAgent>().toList(growable: false);

  ///
  /// Teleportation duration
  final teleportationDuration = const Duration(milliseconds: 1000);

  ///
  /// Velocity threshold for teleportation
  final double velocityThresholdSquared = 400.0;

  // Listeners
  final onGameIsReady = GenericListener<Function()>();
  final onClockTicked = GenericListener<Function()>();
  final onGameOver = GenericListener<Function(bool)>();
  final onTrySolution =
      GenericListener<Function(String sender, String word, bool isSuccess)>();

  ///
  /// Constructor
  BlueberryWarGameManager();

  Vector2 _generateRandomStartingPlayerPosition() {
    return Vector2(
      _random.nextDouble() * fieldSize.x * 1 / 10.0 + fieldSize.x / 10,
      _random.nextDouble() * fieldSize.y * 6 / 8.0 + fieldSize.y / 8,
    );
  }

  ///
  /// Initialize the game manager
  Future<void> initialize() async {
    _logger.info('BlueberryWarGameManager initializing');
    _isGameOver = false;
    _generateProblem();

    allAgents.clear();

    // Populate letters with random agents
    final bossIndex = _random.nextInt(problem.letters.length);
    for (int i = 0; i < problem.letters.length; i++) {
      final isBoss = i == bossIndex;
      allAgents.add(
        LetterAgent(
          id: i,
          isBoss: isBoss,
          problemIndex: i,
          letter: problem.letters[i],
          position: Vector2(fieldSize.x * 2 / 3, fieldSize.y * 2 / 5),
          velocity: Vector2(
            _random.nextDouble() * 1500 - 750,
            _random.nextDouble() * 1500 - 750,
          ),
          radius: Vector2(40.0, 50.0),
          mass: 1.0,
          coefficientOfFriction: (isBoss ? -0.2 : 0.5),
        ),
      );
    }

    // Populate players with random agents
    for (int i = 0; i < initialPlayerCount; i++) {
      allAgents.add(
        PlayerAgent(
          id: i,
          position: _generateRandomStartingPlayerPosition(),
          velocity: Vector2.zero(),
          radius: Vector2(15.0, 15.0),
          mass: 3.0,
          coefficientOfFriction: 0.8,
        ),
      );
    }

    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(_tickDuration, (timer) => _gameLoop());

    // Notify listeners that the game is ready
    _logger.info('BlueberryWarGameManager initialized');
    _isInitialized = true;
    _startTime = null;
    _finalTime = null;
    _isGameOver = false;
    _hasWon = null;
    _lastTick = DateTime.now();
    onGameIsReady.notifyListeners((callback) => callback());
  }

  ///
  /// Get a random word from the list (capitalized)
  void _generateProblem() {
    final word = _dictionary[_random.nextInt(_dictionary.length)];

    // One letter will not be on the grid. For internal reasons of LetterDisplayer,
    // we must flag it as "revealed"
    final mysteryLetterIndex = _random.nextInt(word.length);

    _problem = SerializableLetterProblem(
      letters: word.split(''),
      scrambleIndices: List.generate(word.length, (index) => index),
      uselessLetterStatuses: List.generate(
        word.length,
        (i) =>
            i == mysteryLetterIndex
                ? LetterStatus.revealed
                : LetterStatus.normal,
      ),
      hiddenLetterStatuses: List.generate(
        word.length,
        (_) => LetterStatus.hidden,
      ),
    );
  }

  SerializableBlueberryWarGameState serialize() {
    return SerializableBlueberryWarGameState();
  }

  ///
  /// The game loop
  void _gameLoop() {
    if (!_isInitialized) {
      _logger.warning('Game loop called before initialization');
      return;
    }

    // Check if the game is over
    _manageStartOfGame();
    _manageForGameOver();
    _updateAgents();
    _tickClock();
  }

  void _manageStartOfGame() {
    if (_startTime != null) return;

    for (final agent in allAgents) {
      if (agent is! PlayerAgent) continue;
      if (agent.velocity.length2 != 0.0) {
        _logger.info('Timer started');
        _startTime = DateTime.now();
        break;
      }
    }
  }

  void _manageForGameOver() {
    if (_isGameOver) {
      // Stop the timer if all the agents have stopped moving
      if (allAgents.every(
        (agent) =>
            agent.velocity.length2 < velocityThresholdSquared ||
            agent.isDestroyed,
      )) {
        _logger.info('Game over, stopping the timer');
        _gameTimer?.cancel();
      }
      return;
    }

    if (letters.every((letter) => letter.isDestroyed)) {
      _logger.info('All letters revealed, you win!');
      _isGameOver = true;
      _hasWon = true;
    } else if (timeRemaining.isNegative) {
      _logger.info('Game over due to time running out');
      _isGameOver = true;
      _hasWon = false;
    } else if (players.every((player) => player.isDestroyed)) {
      _logger.info('All players destroyed, you lose!');
      _isGameOver = true;
      _hasWon = false;
    }

    if (!_isGameOver) return;

    // Make all the agents quickly slowing down
    for (final agent in allAgents) {
      agent.coefficientOfFriction = 0.9;
    }

    _finalTime = DateTime.now();
    onGameOver.notifyListeners((callback) => callback(_hasWon!));
  }

  void _updateAgents() {
    final dt = DateTime.now().difference(_lastTick);

    for (int i = 0; i < allAgents.length; i++) {
      // Move all agents
      final agent = allAgents[i];

      final isPlayer = agent is PlayerAgent;
      agent.update(
        dt: dt,
        horizontalBounds:
            isPlayer
                ? Vector2(0, fieldSize.x)
                : Vector2(fieldSize.x / 5, fieldSize.x),
        verticalBounds:
            isPlayer ? Vector2(0, fieldSize.y) : Vector2(0, fieldSize.y),
      );

      // Check for collisions with other agents.
      // Do not redo collisions with agents that have already been checked.
      for (final other in allAgents.sublist(i + 1)) {
        if (agent.isCollidingWith(other)) {
          agent.performCollisionWith(other);
          if (agent is LetterAgent && other is PlayerAgent) {
            performHitOfPlayerOnLetter(other, agent);
          }
          if (agent is PlayerAgent && other is LetterAgent) {
            performHitOfPlayerOnLetter(agent, other);
          }
        }
      }

      // Check for teleportation
      if (isPlayer) {
        // Teleport back to starting if the player is out of starting block and does not move anymore
        if (agent.position.x > fieldSize.x / 5 &&
            agent.velocity.length2 < velocityThresholdSquared) {
          agent.teleport(to: _generateRandomStartingPlayerPosition());
        }
      }
    }

    // Check if collision revealed the letter
    for (int i = allAgents.length - 1; i >= 0; i--) {
      final agent = allAgents[i];
      if (agent is LetterAgent && agent.isDestroyed) {
        problem.hiddenLetterStatuses[agent.problemIndex] =
            LetterStatus.revealed;
      }
    }
  }

  void performHitOfPlayerOnLetter(PlayerAgent player, LetterAgent letter) {
    if (letter.isBoss) {
      // Destroy the player
      player.destroy();
    } else {
      letter.hit();
    }
  }

  ///
  /// Tick the clock by one second
  void _tickClock() {
    _logger.finer('Game loop ticked at ${DateTime.now()}');
    _lastTick = DateTime.now();
    onClockTicked.notifyListeners((callback) => callback());
  }
}
