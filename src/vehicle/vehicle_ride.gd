class_name VehicleRide
extends RefCounted
## Анимация хода — только модель (VehicleModels.Model), на кинематику не влияет (GDD §4, «Облик»).
## Ровер и танк мелко трясутся: чуть-чуть на холостом, на ходу — по скорости, на неровном грунте
## (FLAG_ROUGH) сильнее; тяжёлый танк — ниже частотой и чуть слабее. В зыбучем грунте (FLAG_MIRE) вместо
## тряски — осадка и медленное покачивание. Корпус на подвеске (body) приседает при разгоне, клюёт носом
## при торможении, кренится наружу в повороте. Ховер не трясётся: плавно колышется на подушке, кренится в
## поворот, задирает нос при разгоне; только в ядре водоворота (VehicleState.churn) его болтает — той же
## тряской, что ровер на неровном грунте, но медленнее. Антенна — хлыст на пружине: при разгоне
## отклоняется назад, при торможении — вперёд, в повороте — наружу; вздрагивает от тряски и раскачки от ударов.
## Шум — сумма синусов несоизмеримых частот: гладкий, без покадрового дрожания. В полёте, в воде,
## у разбитой машины тряска и наклоны стихают, антенна успокаивается.

## Тряска корпуса: сила 1 — амплитуды SHAKE_Y и SHAKE_TILT (у ровера; тяжелее — слабее, см. _heft).
const SHAKE_IDLE := 0.12                  ## сила на холостом ходу
const SHAKE_SMOOTH := 0.35                ## прибавка на полном ходу по ровному грунту…
const SHAKE_ROUGH := 1.5                  ## …и по неровному (там скорость ≤ 0,65 полной — выходит ≈ 1)
const SHAKE_Y := 0.07                     ## тайла — подскок корпуса (≈ 1 пиксель рендера)
const SHAKE_TILT := 0.05                  ## рад — тангаж и крен корпуса
const SHAKE_HZ := Vector3(3.1, 5.3, 8.9)  ## Гц — частоты шума на холостом (у ровера; танк ниже в √масса раз)…
const SHAKE_HZ_SPEED := 0.4               ## …на полном ходу выше в 1 + это раз
const SHAKE_FOLLOW := 8.0                 ## 1/с — сила тряски догоняет цель: смена грунта без рывка
## Зыбучий грунт: осадка и медленное покачивание вместо тряски.
const MIRE_SINK := 0.06                   ## тайла — колёса и гусеницы уходят в грунт…
const MIRE_STUCK_SINK := 0.05             ## …и ещё глубже, пока машину засасывает (VehicleState.mire_stuck)
const PULL_SINK := 0.3                    ## тайла — ядро водоворота затягивает машину в воду (VehicleState.pull_under)
const MIRE_TILT := 0.05                   ## рад
const MIRE_HZ := 0.6
const MIRE_FOLLOW := 2.0                  ## 1/с — оседает и выбирается не сразу
## Инерция корпуса от ускорения в осях машины (сглаженного).
const ACCEL_MAX := 30.0                   ## тайл/с² — удар о стенку не даёт огромных значений
const ACCEL_FOLLOW := 6.0                 ## 1/с
const DIVE := 0.006                       ## рад на тайл/с² — ровер и танк: приседание, клевок, крен наружу
const DIVE_MAX := 0.06                    ## рад
## Ховер: колышется на подушке, кренится в поворот, задирает нос при разгоне; в ядре водоворота его болтает.
const HOVER_BOB := 0.02                   ## тайла
const HOVER_BOB_HZ := 0.48
const HOVER_SWAY := 0.03                  ## рад — медленное покачивание
const HOVER_LEAN := 0.012                 ## рад на тайл/с²
const HOVER_LEAN_MAX := 0.16              ## рад
const HOVER_FOLLOW := 2.0                 ## 1/с — колыхание стихает и возвращается плавно
const CHURN := 1.5                        ## болтанка в водовороте (VehicleState.churn = 1) — тряска такой силы…
const CHURN_HZ := 0.7                     ## …на частотах SHAKE_HZ × это: волны, а не дрожь колёс
## Антенна-хлыст: пружина с малым затуханием.
const ANT_HZ := 2.4                       ## Гц — ровер и танк
const ANT_HZ_HOVER := 1.6                 ## ховер — мягче
const ANT_DAMPING := 0.18                 ## доля критического
const ANT_DAMPING_HOVER := 0.25
const ANT_INERTIA := 0.03                 ## рад на тайл/с²: разгон — назад, торможение — вперёд, поворот — наружу
const ANT_LEAN_MAX := 0.3                 ## рад — предел отклонения от ускорения
const ANT_COUPLING := 1.5                 ## во сколько раз антенна отстаёт от поворота корпуса (тряска, удары)
const ANT_MAX := 0.5                      ## рад
const PIVOT := Vector3(0, 0.25, 0)        ## вокруг этой точки модели качается корпус

var _time := 0.0
var _phase := 0.0               ## «время» шума тряски: на скорости бежит быстрее
var _shake := 0.0               ## текущая сила тряски
var _mire := 0.0                ## 0..1 — осадка в зыбучем грунте
var _float := 0.0               ## 0..1 — колыхание ховера
var _acc := Vector2.ZERO        ## сглаженное ускорение в осях машины: x — вперёд, y — вправо
var _prev_vel := Vector2.ZERO
var _frame := Vector2.ZERO      ## тангаж и крен корпуса относительно машины (раскачка + ход) в прошлом кадре…
var _frame_vel := Vector2.ZERO  ## …и их скорость
var _ant := Vector2.ZERO        ## антенна: x — rotation.x (верх назад +), y — rotation.z (верх влево +)
var _ant_vel := Vector2.ZERO


## Кадр анимации (физический). active — машина цела и не поднята челноком; в полёте и в воде тряска
## стихает сама. rock — раскачка root от ударов (тангаж, крен): антенна от неё отстаёт.
func update(dt: float, m: VehicleModels.Model, s: VehicleState, cls: VehicleClass, ground_flags: int,
		active: bool, rock: Vector2) -> void:
	if dt <= 0.0:
		return
	_time += dt
	var grounded := active and not s.falling and not s.drowning
	var fwd := s.forward()
	var right := Vector2(-fwd.y, fwd.x)
	# Ускорение в осях машины; в повороте — центростремительное (к центру поворота).
	var a := Vector2.ZERO
	if grounded:
		var aw := (s.vel - _prev_vel) / dt
		a = Vector2(aw.dot(fwd), aw.dot(right)).limit_length(ACCEL_MAX)
	_prev_vel = s.vel
	_acc = _acc.lerp(a, 1.0 - exp(-ACCEL_FOLLOW * dt))
	var speed_k := clampf(s.vel.length() / cls.max_speed, 0.0, 1.0)

	var y := 0.0
	var tilt := Vector2.ZERO        # тангаж (нос вверх +), крен (правый борт вверх +)
	if cls.hovers:
		_float = lerpf(_float, 1.0 if grounded else 0.0, 1.0 - exp(-HOVER_FOLLOW * dt))
		y = HOVER_BOB * _float * sin(TAU * HOVER_BOB_HZ * _time)
		tilt = Vector2(sin(TAU * 0.31 * _time + 0.7), sin(TAU * 0.23 * _time + 2.1)) * HOVER_SWAY * _float
		var lean := Vector2(_acc.x, -_acc.y) * HOVER_LEAN     # разгон — нос вверх; в поворот — внутренним бортом вниз
		tilt += lean.clamp(-Vector2.ONE * HOVER_LEAN_MAX, Vector2.ONE * HOVER_LEAN_MAX)
		# Ядро водоворота: болтает, как ровер на неровном грунте, — та же тряска, только медленнее.
		_shake = lerpf(_shake, CHURN * s.churn if grounded else 0.0, 1.0 - exp(-SHAKE_FOLLOW * dt))
		_phase += dt * CHURN_HZ
		y += SHAKE_Y * _shake * _noise(_phase, 0.0)
		tilt += Vector2(_noise(_phase * 1.13, 1.7), _noise(_phase * 0.91, 3.9)) * SHAKE_TILT * _shake
	else:
		var target := shake_strength(cls, s.vel.length(), ground_flags) if grounded else 0.0
		_shake = lerpf(_shake, target, 1.0 - exp(-SHAKE_FOLLOW * dt))
		_phase += dt * (1.0 + SHAKE_HZ_SPEED * speed_k) / sqrt(_heft(cls))
		y = SHAKE_Y * _shake * _noise(_phase, 0.0)
		tilt = Vector2(_noise(_phase * 1.13, 1.7), _noise(_phase * 0.91, 3.9)) * SHAKE_TILT * _shake
		var mire := (ground_flags & ChunkData.FLAG_MIRE) != 0 and not s.falling and not s.drowning
		_mire = lerpf(_mire, 1.0 if mire else 0.0, 1.0 - exp(-MIRE_FOLLOW * dt))
		var wobble := _mire * (0.4 + 0.6 * speed_k) if grounded else 0.0
		tilt += Vector2(sin(TAU * MIRE_HZ * _time), sin(TAU * MIRE_HZ * 0.73 * _time + 1.3)) * MIRE_TILT * wobble
		var dive := _acc * DIVE                                 # разгон — нос вверх; в повороте — крен наружу
		tilt += dive.clamp(-Vector2.ONE * DIVE_MAX, Vector2.ONE * DIVE_MAX)
	m.root.position.y = m.hover_height - MIRE_SINK * _mire - MIRE_STUCK_SINK * s.mire_stuck - PULL_SINK * s.pull_under
	var b := Basis.from_euler(Vector3(tilt.x, 0.0, tilt.y))
	m.body.transform = Transform3D(b, PIVOT - b * PIVOT + Vector3(0.0, y, 0.0))

	# Антенна: корпус повернулся — она по инерции отстаёт; ускорение отклоняет её в обратную сторону.
	var frame := rock + tilt
	var frame_vel := (frame - _frame) / dt
	_ant_vel -= (frame_vel - _frame_vel) * ANT_COUPLING
	_frame = frame
	_frame_vel = frame_vel
	var w0 := TAU * (ANT_HZ_HOVER if cls.hovers else ANT_HZ)
	var zeta := ANT_DAMPING_HOVER if cls.hovers else ANT_DAMPING
	var bend := antenna_lean(a) if grounded else Vector2.ZERO
	_ant_vel += (-(_ant - bend) * w0 * w0 - _ant_vel * 2.0 * zeta * w0) * dt
	_ant += _ant_vel * dt
	if _ant.length() > ANT_MAX:
		# Упор: дальше не гнётся, скорость наружу гасится — без залипания на пределе.
		var out := _ant.normalized()
		_ant = out * ANT_MAX
		_ant_vel -= out * maxf(_ant_vel.dot(out), 0.0)
	m.antenna.rotation = Vector3(_ant.x, 0.0, _ant.y)


## Сила тряски корпуса (1 — амплитуды SHAKE_Y и SHAKE_TILT): на холостом чуть-чуть, на ходу — по
## скорости, на неровном грунте сильнее, тяжёлая машина — слабее. Ховер не трясётся; в зыбучем
## грунте вместо тряски — покачивание.
static func shake_strength(cls: VehicleClass, speed: float, ground_flags: int) -> float:
	if cls.hovers or (ground_flags & ChunkData.FLAG_MIRE) != 0:
		return 0.0
	var k := clampf(speed / cls.max_speed, 0.0, 1.0)
	var rough := (ground_flags & ChunkData.FLAG_ROUGH) != 0
	return (SHAKE_IDLE + k * (SHAKE_ROUGH if rough else SHAKE_SMOOTH)) * pow(_heft(cls), -0.25)


## Равновесный наклон антенны от ускорения a в осях машины (x — вперёд, y — вправо), рад:
## x — rotation.x (разгон — верх назад), y — rotation.z (ускорение вправо — верх влево, наружу поворота).
static func antenna_lean(a: Vector2) -> Vector2:
	return (a * ANT_INERTIA).limit_length(ANT_LEAN_MAX)


## Тяжесть класса — масса (не меньше 0,1): тяжелее — тряска ниже частотой (∝ 1/√масса) и чуть слабее.
static func _heft(cls: VehicleClass) -> float:
	return maxf(cls.mass, 0.1)


## Гладкий шум в пределах −1..1: три синуса несоизмеримых частот SHAKE_HZ, shift сдвигает фазы.
static func _noise(t: float, shift: float) -> float:
	return (sin(TAU * SHAKE_HZ.x * t + shift) + 0.6 * sin(TAU * SHAKE_HZ.y * t + shift * 2.3)
			+ 0.35 * sin(TAU * SHAKE_HZ.z * t + shift * 4.1)) / 1.95
