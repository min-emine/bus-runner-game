import 'dart:async';
import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: GameWidget<BusRunnerGame>(
          game: BusRunnerGame(),
          overlayBuilderMap: {
            'MainMenu': (context, game) => MainMenuOverlay(game: game),
            'GameOverMenu': (context, game) => GameOverOverlay(game: game),
            'DriveControls': (context, game) => DriveControlsOverlay(game: game),
          },
          initialActiveOverlays: const ['MainMenu'],
        ),
      ),
    ),
  );
}

// --- DİL SÖZLÜĞÜ (LOCALIZATION DICTIONARY) ---
class GameLocales {
  static const Map<String, Map<String, String>> texts = {
    'title': {'tr': 'OTOBÜS SİMÜLATÖRÜ', 'en': 'BUS SIMULATOR'},
    'gear_type': {'tr': 'VİTES TÜRÜ', 'en': 'TRANSMISSION'},
    'manual': {'tr': 'Manuel (Debriyajlı)', 'en': 'Manual (Clutch)'},
    'auto': {'tr': 'Otomatik', 'en': 'Automatic'},
    'steering_control': {'tr': 'DİREKSİYON KONTROLÜ', 'en': 'STEERING CONTROL'},
    'tilt': {'tr': 'Telefonu Eğerek', 'en': 'Tilt Device'},
    'wheel': {'tr': 'Ekranda Direksiyon', 'en': 'On-Screen Wheel'},
    'play': {'tr': 'OYUNA BAŞLA', 'en': 'START GAME'},
    'score': {'tr': 'Skor', 'en': 'Score'},
    'passengers': {'tr': 'Yolcu', 'en': 'Passengers'},
    'speed': {'tr': 'Hız', 'en': 'Speed'},
    'clutch': {'tr': 'DEBRİYAJ', 'en': 'CLUTCH'},
    'clutch_pressed': {'tr': 'DEBRİYAJ\n(BASILI)', 'en': 'CLUTCH\n(PRESSED)'},
    'gas': {'tr': 'GAZ', 'en': 'GAS'},
    'brake': {'tr': 'FREN', 'en': 'BRAKE'},
    'gear_indicator': {'tr': 'Vites', 'en': 'Gear'},
    'passengers_taken': {'tr': 'YOLCULAR ALINDI!', 'en': 'PASSENGERS BOARDED!'},
    'game_over': {'tr': 'OYUN BİTTİ', 'en': 'GAME OVER'},
    'try_again': {'tr': 'TEKRAR DENE', 'en': 'TRY AGAIN'},
    'back_settings': {'tr': 'Ayarlara Dön', 'en': 'Back to Settings'},
    'crash_reason': {'tr': 'KAZA YAPTIN!', 'en': 'YOU CRASHED!'},
    'stop_reason': {'tr': 'DURAKTA DURMADIN!', 'en': 'MISSED THE STOP!'},
    'left': {'tr': '< SOL', 'en': '< LEFT'},
    'right': {'tr': 'SAĞ >', 'en': 'RIGHT >'},
  };
}

// 1. OYUN SINIFI
class BusRunnerGame extends FlameGame with TapCallbacks, HasCollisionDetection {
  Player? player;
  final _random = Random();
  int score = 0;
  int collectedCoins = 0;
  bool isGameOver = false;
  String gameOverReasonKey = "crash_reason";

  late TextComponent scoreText;
  late TextComponent coinText;
  late TextComponent speedText;

  // AYARLAR
  bool useAutoTransmission = false;
  bool useSensorControl = true;
  String currentLang = 'tr'; // Varsayılan Dil

  // HIZ VE VİTES DEĞİŞKENLERİ
  final double maxObstacleSpeed = 1000.0;
  double currentObstacleSpeed = 0.0;

  int currentGear = 0;
  bool isClutchPressed = false;
  bool isGasPressed = false;
  bool isBrakePressed = false;

  double steeringWheelAngle = 0.0;

  final double playerLateralSpeed = 500.0;
  double playerTargetLaneX = 0.0;

  // Çeviri Yardımcı Fonksiyonu
  String t(String key) => GameLocales.texts[key]?[currentLang] ?? key;

  @override
  Color backgroundColor() => const Color(0xFF222222);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewfinder.anchor = Anchor.topLeft;

    try { await FlameAudio.audioCache.loadAll(['coin.mp3', 'crash.mp3']); } catch (_) {}

    await world.add(ScrollingRoadBackground());
    player = Player();
    await world.add(player!);

    scoreText = TextComponent(text: '${t('score')}: 0', position: Vector2(20, 20));
    coinText = TextComponent(text: '${t('passengers')}: 0', position: Vector2(20, 50));
    speedText = TextComponent(text: '${t('speed')}: 0 km/h', position: Vector2(20, 80));

    camera.viewport.addAll([scoreText, coinText, speedText]);

    add(TimerComponent(period: 1.5, repeat: true, onTick: () { if (!isGameOver && currentObstacleSpeed > 50) spawnObstacle(); }));
    add(TimerComponent(period: 3.0, repeat: true, onTick: () { if (!isGameOver && currentObstacleSpeed > 50) spawnCoin(); }));
    add(TimerComponent(period: 12.0, repeat: true, onTick: () { if (!isGameOver) spawnBusStop(); }));

    pauseEngine();
  }

  void spawnObstacle() {
    bool isBusStopActive = world.children.whereType<BusStop>().isNotEmpty;
    int lane = isBusStopActive ? _random.nextInt(2) : _random.nextInt(3);
    world.add(Obstacle(lane: lane));
  }

  void spawnCoin() {
    bool isBusStopActive = world.children.whereType<BusStop>().isNotEmpty;
    int lane = isBusStopActive ? _random.nextInt(2) : _random.nextInt(3);
    world.add(Coin(lane: lane));
  }

  void spawnBusStop() {
    for (var obstacle in world.children.whereType<Obstacle>()) {
      if (obstacle.lane == 2) obstacle.removeFromParent();
    }
    world.add(BusStop());
  }

  void collectCoin() {
    collectedCoins++;
    score += 5;
    updateTexts();
  }

  void collectStopBonus() {
    try { FlameAudio.play('coin.mp3', volume: 0.8); } catch (_) {}
    collectedCoins += 10;
    score += 50;
    updateTexts();

    final bonusText = TextComponent(text: t('passengers_taken'), position: Vector2(size.x / 2, size.y / 2), anchor: Anchor.center, textRenderer: TextPaint(style: const TextStyle(color: Colors.greenAccent, fontSize: 32, fontWeight: FontWeight.bold)));
    camera.viewport.add(bonusText);
    Future.delayed(const Duration(seconds: 1), () => bonusText.removeFromParent());
  }

  void updateTexts() {
    scoreText.text = '${t('score')}: $score';
    coinText.text = '${t('passengers')}: $collectedCoins';
  }

  void gameOver(String reasonKey) {
    if (isGameOver) return;
    gameOverReasonKey = reasonKey;
    isGameOver = true;
    pauseEngine();
    overlays.remove('DriveControls');
    overlays.add('GameOverMenu');
  }

  void resetGame() {
    score = 0;
    collectedCoins = 0;
    currentObstacleSpeed = 0.0;
    currentGear = useAutoTransmission ? 1 : 0;
    isGasPressed = false;
    isBrakePressed = false;
    isClutchPressed = false;
    steeringWheelAngle = 0.0;

    updateTexts();
    world.children.whereType<Obstacle>().forEach((o) => o.removeFromParent());
    world.children.whereType<Coin>().forEach((c) => c.removeFromParent());
    world.children.whereType<BusStop>().forEach((bs) => bs.removeFromParent());

    player?.resetPosition();

    isGameOver = false;
    resumeEngine();
    overlays.add('DriveControls');
  }

  void shiftGearUp() { if (isClutchPressed && currentGear < 5) currentGear++; }
  void shiftGearDown() { if (isClutchPressed && currentGear > 0) currentGear--; }

  @override
  void update(double dt) {
    super.update(dt);
    if (isGameOver) return;

    double targetSpeed = currentObstacleSpeed;

    if (useAutoTransmission) {
      if (isBrakePressed) targetSpeed -= 800.0 * dt;
      else if (isGasPressed) targetSpeed += 400.0 * dt;
      else targetSpeed -= 150.0 * dt;

      if (targetSpeed < 10) currentGear = 1;
      else currentGear = (targetSpeed / 200).ceil().clamp(1, 5);
    } else {
      double maxGearSpeed = currentGear * 200.0;

      if (isBrakePressed) targetSpeed -= 800.0 * dt;
      else if (isGasPressed && !isClutchPressed && currentGear > 0) targetSpeed += 400.0 * dt;
      else targetSpeed -= (isClutchPressed || currentGear == 0) ? 50.0 * dt : 150.0 * dt;

      if (!isClutchPressed && currentGear > 0 && targetSpeed > maxGearSpeed) {
        targetSpeed -= 300.0 * dt;
        if (targetSpeed < maxGearSpeed) targetSpeed = maxGearSpeed;
      }
    }

    currentObstacleSpeed = targetSpeed.clamp(0.0, maxObstacleSpeed);
    speedText.text = '${t('speed')}: ${(currentObstacleSpeed / 5).round()} km/h';
  }
}

// 2. OYUNCU (OTOBÜS) SINIFI
class Player extends SpriteComponent with HasGameRef<BusRunnerGame>, CollisionCallbacks {
  int currentLane = 1;
  BusStop? overlappingBusStop;
  StreamSubscription? _accelSub;

  Player() : super(size: Vector2(80, 160), anchor: Anchor.center, priority: 10);

  @override
  Future<void> onLoad() async {
    try { sprite = await gameRef.loadSprite('bus.png'); } catch (_) {}
    add(RectangleHitbox());
    resetPosition();

    _accelSub = accelerometerEventStream().listen((event) {
      if (gameRef.isGameOver || !gameRef.useSensorControl) return;

      int newLane = currentLane;
      if (event.x > 2.5) newLane = 0;
      else if (event.x < -2.5) newLane = 2;
      else if (event.x < 1.0 && event.x > -1.0) newLane = 1;

      if (currentLane != newLane) {
        currentLane = newLane;
        updateTarget();
      }
    });
  }

  void resetPosition() {
    currentLane = 1;
    angle = 0.0;
    if (gameRef.size.x > 0) {
      double lw = gameRef.size.x / 3;
      x = (currentLane * lw) + (lw / 2);
      y = gameRef.size.y - 150;
      gameRef.playerTargetLaneX = x;
    }
  }

  @override
  void onRemove() {
    _accelSub?.cancel();
    super.onRemove();
  }

  void updateTarget() {
    double lw = gameRef.size.x / 3;
    gameRef.playerTargetLaneX = (currentLane * lw) + (lw / 2);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameRef.isGameOver) return;

    if (!gameRef.useSensorControl) {
      int newLane = 1;
      if (gameRef.steeringWheelAngle < -0.3) newLane = 0;
      else if (gameRef.steeringWheelAngle > 0.3) newLane = 2;

      if (currentLane != newLane) {
        currentLane = newLane;
        updateTarget();
      }
    }

    if (overlappingBusStop != null && !overlappingBusStop!.isServed && currentLane == 2) {
      if (gameRef.currentObstacleSpeed < 5.0) {
        overlappingBusStop!.isServed = true;
        gameRef.collectStopBonus();
      }
    }

    double diff = gameRef.playerTargetLaneX - x;
    double step = gameRef.playerLateralSpeed * dt;

    if (diff.abs() < step) {
      x = gameRef.playerTargetLaneX;
    } else {
      x += (diff > 0 ? 1 : -1) * step;
    }

    double maxDiff = gameRef.size.x / 3;
    double targetAngle = (diff / maxDiff) * 0.4;
    angle += (targetAngle - angle) * 10 * dt;
  }

  @override
  void onCollisionStart(Set<Vector2> pts, PositionComponent other) {
    super.onCollisionStart(pts, other);
    if (other is Obstacle) gameRef.gameOver("crash_reason");
    if (other is Coin) { gameRef.collectCoin(); other.removeFromParent(); }
    if (other is BusStop) overlappingBusStop = other;
  }

  @override
  void onCollisionEnd(PositionComponent other) {
    if (other is BusStop && overlappingBusStop == other) overlappingBusStop = null;
    super.onCollisionEnd(other);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    y = size.y - 150;
    updateTarget();
  }
}

// 3. OTOBÜS DURAĞI
class BusStop extends SpriteComponent with HasGameRef<BusRunnerGame> {
  bool isServed = false;
  BusStop() : super(size: Vector2(60, 250), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    try { sprite = await gameRef.loadSprite('bus_stop.png'); } catch (_) {}
    add(RectangleHitbox(isSolid: false));
    x = gameRef.size.x - 40;
    y = -200;
  }

  @override
  void update(double dt) {
    if (gameRef.isGameOver) return;
    y += gameRef.currentObstacleSpeed * dt;
    if (y > gameRef.size.y + 200) {
      if (!isServed) { gameRef.gameOver("stop_reason"); }
      removeFromParent();
    }
  }
}

// 4. ARKA PLAN VE ENGELLER
class ScrollingRoadBackground extends Component with HasGameRef<BusRunnerGame> {
  final Paint p = Paint()..color = Colors.white70..strokeWidth = 4;
  double offset = 0;
  @override
  void render(Canvas c) {
    double lw = gameRef.size.x / 3;
    for (int i = 1; i < 3; i++) {
      for (double y = -60 + offset; y < gameRef.size.y + 60; y += 60) {
        c.drawLine(Offset(i * lw, y), Offset(i * lw, y + 30), p);
      }
    }
  }
  @override
  void update(double dt) {
    if (gameRef.isGameOver) return;
    offset += gameRef.currentObstacleSpeed * dt;
    if (offset > 60) offset %= 60;
  }
}

class Obstacle extends SpriteComponent with HasGameRef<BusRunnerGame> {
  final int lane;
  Obstacle({required this.lane}) : super(size: Vector2(70, 120), anchor: Anchor.center);
  @override
  Future<void> onLoad() async {
    try { sprite = await gameRef.loadSprite('car.png'); } catch (_) {}
    add(RectangleHitbox());
    double lw = gameRef.size.x / 3;
    x = (lane * lw) + (lw / 2);
    y = -100;
  }
  @override
  void update(double dt) {
    if (gameRef.isGameOver) return;
    y += gameRef.currentObstacleSpeed * dt;
    if (y > gameRef.size.y + 100) removeFromParent();
  }
}

class Coin extends SpriteComponent with HasGameRef<BusRunnerGame> {
  final int lane;
  Coin({required this.lane}) : super(size: Vector2(50, 50), anchor: Anchor.center);
  @override
  Future<void> onLoad() async {
    try { sprite = await gameRef.loadSprite('person.png'); } catch (_) {}
    add(CircleHitbox());
    double lw = gameRef.size.x / 3;
    x = (lane * lw) + (lw / 2);
    y = -50;
  }
  @override
  void update(double dt) {
    if (gameRef.isGameOver) return;
    y += gameRef.currentObstacleSpeed * dt;
    if (y > gameRef.size.y + 50) removeFromParent();
  }
}

// ÇEVİRMELİ DİREKSİYON
class SteeringWheelWidget extends StatefulWidget {
  final ValueChanged<double> onAngleChanged;
  const SteeringWheelWidget({super.key, required this.onAngleChanged});

  @override
  State<SteeringWheelWidget> createState() => _SteeringWheelWidgetState();
}

class _SteeringWheelWidgetState extends State<SteeringWheelWidget> {
  double _angle = 0.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _angle += details.delta.dx * 0.015;
          _angle = _angle.clamp(-1.0, 1.0);
        });
        widget.onAngleChanged(_angle);
      },
      onPanEnd: (_) {
        setState(() { _angle = 0.0; });
        widget.onAngleChanged(0.0);
      },
      child: Transform.rotate(
        angle: _angle,
        child: Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: Colors.blueGrey.withOpacity(0.8),
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(2, 4))]
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: 20, height: 20, margin: const EdgeInsets.only(top: 5),
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

// 5. ARAYÜZ (KONTROLLER VE MENÜLER)
class DriveControlsOverlay extends StatefulWidget {
  final BusRunnerGame game;
  const DriveControlsOverlay({super.key, required this.game});
  @override
  State<DriveControlsOverlay> createState() => _DriveControlsOverlayState();
}

class _DriveControlsOverlayState extends State<DriveControlsOverlay> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (!widget.game.useSensorControl)
          Positioned(
            bottom: 30, left: 30,
            child: SteeringWheelWidget(
              onAngleChanged: (angle) {
                widget.game.steeringWheelAngle = angle;
              },
            ),
          ),

        if (!widget.game.useAutoTransmission) ...[
          Positioned(
            bottom: widget.game.useSensorControl ? 20 : 160,
            left: 20,
            child: GestureDetector(
              onTap: () {
                setState(() { widget.game.isClutchPressed = !widget.game.isClutchPressed; });
              },
              child: Container(
                width: 110, height: 60,
                decoration: BoxDecoration(
                    color: widget.game.isClutchPressed ? Colors.orange : Colors.orange.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 2)
                ),
                child: Center(child: Text(widget.game.isClutchPressed ? widget.game.t('clutch_pressed') : widget.game.t('clutch'),
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))),
              ),
            ),
          ),
          Positioned(
            bottom: widget.game.useSensorControl ? 100 : 240,
            left: 20,
            child: Row(
              children: [
                _gearBtn('-', () { widget.game.shiftGearDown(); setState((){}); }),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10), padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                  child: Text(widget.game.currentGear == 0 ? 'N' : widget.game.currentGear.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                ),
                _gearBtn('+', () { widget.game.shiftGearUp(); setState((){}); }),
              ],
            ),
          ),
        ],

        if (widget.game.useAutoTransmission)
          Positioned(
            bottom: widget.game.useSensorControl ? 20 : 160,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.greenAccent)),
              child: Text(widget.game.currentObstacleSpeed < 10 ? '${widget.game.t('gear_indicator')}: N' : '${widget.game.t('gear_indicator')}: D${widget.game.currentGear}',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),

        Positioned(
          bottom: 20, right: 20,
          child: Row(
            children: [
              _actionBtn(widget.game.t('brake'), Colors.red, () => widget.game.isBrakePressed = true, () => widget.game.isBrakePressed = false),
              const SizedBox(width: 15),
              _actionBtn(widget.game.t('gas'), Colors.green, () => widget.game.isGasPressed = true, () => widget.game.isGasPressed = false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(String txt, MaterialColor color, Function down, Function up) => GestureDetector(
    onTapDown: (_) => down(), onTapUp: (_) => up(), onTapCancel: () => up(),
    child: Container(
      width: 90, height: 80,
      decoration: BoxDecoration(color: color.withOpacity(0.8), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 2)),
      child: Center(child: Text(txt, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
    ),
  );

  Widget _gearBtn(String txt, VoidCallback tap) => GestureDetector(
    onTap: tap,
    child: Container(
      width: 50, height: 50,
      decoration: BoxDecoration(color: Colors.blueGrey, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      child: Center(child: Text(txt, style: const TextStyle(color: Colors.white, fontSize: 30))),
    ),
  );
}

// ANA MENÜ (AYARLAR VE DİL EKRANI)
class MainMenuOverlay extends StatefulWidget {
  final BusRunnerGame game;
  const MainMenuOverlay({super.key, required this.game});

  @override
  State<MainMenuOverlay> createState() => _MainMenuOverlayState();
}

class _MainMenuOverlayState extends State<MainMenuOverlay> {
  bool isAuto = false;
  bool isSensor = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // DİL SEÇİMİ (Sağ Üste Sabitleyebiliriz ama basitlik için menünün içine koydum)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.language, color: Colors.white),
                const SizedBox(width: 10),
                ChoiceChip(text: 'Türkçe', isSelected: widget.game.currentLang == 'tr', onTap: () => setState(() => widget.game.currentLang = 'tr')),
                const SizedBox(width: 10),
                ChoiceChip(text: 'English', isSelected: widget.game.currentLang == 'en', onTap: () => setState(() => widget.game.currentLang = 'en')),
              ],
            ),
            const SizedBox(height: 30),

            Text(widget.game.t('title'), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),

            Text(widget.game.t('gear_type'), style: const TextStyle(color: Colors.white70, fontSize: 18)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(text: widget.game.t('manual'), isSelected: !isAuto, onTap: () => setState(() => isAuto = false)),
                const SizedBox(width: 10),
                ChoiceChip(text: widget.game.t('auto'), isSelected: isAuto, onTap: () => setState(() => isAuto = true)),
              ],
            ),
            const SizedBox(height: 20),

            Text(widget.game.t('steering_control'), style: const TextStyle(color: Colors.white70, fontSize: 18)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(text: widget.game.t('tilt'), isSelected: isSensor, onTap: () => setState(() => isSensor = true)),
                const SizedBox(width: 10),
                ChoiceChip(text: widget.game.t('wheel'), isSelected: !isSensor, onTap: () => setState(() => isSensor = false)),
              ],
            ),

            const SizedBox(height: 40),
            ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15), backgroundColor: Colors.green),
                onPressed: () {
                  widget.game.useAutoTransmission = isAuto;
                  widget.game.useSensorControl = isSensor;
                  widget.game.overlays.remove('MainMenu');
                  widget.game.resetGame();
                },
                child: Text(widget.game.t('play'), style: const TextStyle(fontSize: 22, color: Colors.white))
            ),
          ],
        ),
      ),
    );
  }
}

class ChoiceChip extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const ChoiceChip({super.key, required this.text, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.transparent,
          border: Border.all(color: Colors.blueAccent),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: TextStyle(color: isSelected ? Colors.white : Colors.blueAccent, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class GameOverOverlay extends StatelessWidget {
  final BusRunnerGame game;
  const GameOverOverlay({super.key, required this.game});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(game.t(game.gameOverReasonKey), style: const TextStyle(color: Colors.red, fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Text('${game.t('score')}: ${game.score}', style: const TextStyle(color: Colors.white, fontSize: 24)),
            const SizedBox(height: 40),
            ElevatedButton(onPressed: () { game.overlays.remove('GameOverMenu'); game.resetGame(); }, child: Text(game.t('try_again'), style: const TextStyle(fontSize: 20))),
            const SizedBox(height: 15),
            TextButton(onPressed: () {
              game.overlays.remove('GameOverMenu');
              game.overlays.add('MainMenu');
            }, child: Text(game.t('back_settings'), style: const TextStyle(color: Colors.white70)))
          ],
        ),
      ),
    );
  }
}