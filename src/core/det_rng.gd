class_name DetRng
extends RefCounted
## Детерминированные хэши и генераторы от seed и координат.
## Глобальные randf()/randi() в проекте запрещены: всё случайное выводится отсюда.
## Арифметика держится в 32 битах, поэтому произведения не переполняют int64.

const _MASK := 0xFFFFFFFF


static func mix(x: int) -> int:
	x &= _MASK
	x = (((x >> 16) ^ x) * 0x45d9f3b) & _MASK
	x = (((x >> 16) ^ x) * 0x45d9f3b) & _MASK
	return ((x >> 16) ^ x) & _MASK


## Хэш от seed и трёх целых (координаты, номер потока). Результат в [0, 2^32).
static func hash4(seed: int, a: int, b: int, c: int = 0) -> int:
	var h := mix(seed ^ 0x9E3779B9)
	h = mix(h ^ mix(a + 0x7F4A7C15))
	h = mix(h ^ mix(b + 0x632BE59B))
	return mix(h ^ mix(c + 0x2545F491))


## Равномерное число в [0, 1).
static func unit(seed: int, a: int, b: int, c: int = 0) -> float:
	return hash4(seed, a, b, c) / 4294967296.0


static func rng_for(seed: int, a: int, b: int, c: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash4(seed, a, b, c)
	return rng
