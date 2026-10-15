class_name Leaderboard
extends RefCounted
## Локальная таблица рекордов (GDD §6): общий топ-10 для всех машин, user://. Машина рекорда — в записи
## (`vehicle`, id класса), на экране её не называем. Файл старого вида (топ-10 отдельно по каждому классу)
## при чтении сливается в общую таблицу; копия старого файла остаётся рядом (leaderboard.json.v1).
## Файл мог быть испорчен (обрыв записи, правка руками): при чтении записи без счёта и чужих типов
## отбрасываются, остальные приводятся к своим типам и сортируются; если что-то пришлось выбросить
## (или файл не разобрать), копия остаётся в leaderboard.json.bad, а в консоль — предупреждение.
## Запись — во временный файл и переименованием поверх: оборванная запись не портит таблицу. В браузере
## user:// — IndexedDB: переименование идёт в памяти (MEMFS), в базу уходит уже итог; если
## переименовать не вышло — пишем прямо в файл.

const DEFAULT_PATH := "user://leaderboard.json"
const SIZE := 10
const NAME_MAX := 8                    ## имя в таблице — до стольких знаков
const BAD_SUFFIX := ".bad"
const TMP_SUFFIX := ".tmp"
const V1_SUFFIX := ".v1"               ## копия файла старого вида (таблицы по классам) до слияния
const KEY := "entries"                 ## файл: {"entries": [...]}

var path: String
var _list: Array = []                  ## записи {name, score, time, shipments, cause, date, vehicle} по убыванию счёта


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	_load()


func entries() -> Array:
	return _list


## Позиция, которую займёт счёт (0 — первое место), или -1, если в топ не попадает.
func rank_for(score: int) -> int:
	for i in _list.size():
		if score > int(_list[i]["score"]):
			return i
	return _list.size() if _list.size() < SIZE else -1


## Добавляет запись и сохраняет файл. Возвращает её место (0..9) или -1.
func add(entry: Dictionary) -> int:
	var rank := rank_for(int(entry["score"]))
	if rank < 0:
		return -1
	_list.insert(rank, entry)
	if _list.size() > SIZE:
		_list.resize(SIZE)
	_save()
	return rank


## Запись из файла в привычном виде: счёт обязателен (конечное число), прочие поля — своего типа или
## по умолчанию; vehicle — машина рекорда (в файле старого вида — ключ таблицы). null — запись не годится.
static func clean_entry(raw: Variant, vehicle: String = "") -> Variant:
	if not raw is Dictionary:
		return null
	var e: Dictionary = raw
	var score: Variant = e.get("score")
	if not (score is float or score is int) or not is_finite(float(score)):
		return null
	var time: Variant = e.get("time", 0.0)
	var shipments: Variant = e.get("shipments", 0)
	return {
		"name": (e["name"] as String).substr(0, NAME_MAX) if e.get("name") is String else "???",
		"score": int(score),
		"time": float(time) if (time is float or time is int) and is_finite(float(time)) else 0.0,
		"shipments": int(shipments) if (shipments is float or shipments is int) and is_finite(float(shipments)) else 0,
		"cause": e["cause"] if e.get("cause") is String else "",
		"date": e["date"] if e.get("date") is String else "",
		"vehicle": e["vehicle"] if e.get("vehicle") is String else vehicle,
	}


func _load() -> void:
	var from := path
	if not FileAccess.file_exists(from):
		# Запись оборвалась между удалением старого файла и переименованием (Windows) — новый целиком во .tmp.
		from = path + TMP_SUFFIX
		if not FileAccess.file_exists(from):
			return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(from)) != OK:
		_keep_bad(from, "JSON error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		_keep_bad(from, "not a JSON object")
		return
	var dropped := 0
	var legacy := false
	var all: Array = []
	for key: Variant in parsed:
		var list: Variant = parsed[key]
		if not key is String or not list is Array:
			dropped += 1
			continue
		legacy = legacy or key != KEY          # старый вид: ключ — класс машины
		for raw: Variant in list:
			var e: Variant = clean_entry(raw, "" if key == KEY else key)
			if e == null:
				dropped += 1
			else:
				all.append(e)
	if legacy and not FileAccess.file_exists(path + V1_SUFFIX):
		DirAccess.copy_absolute(from, path + V1_SUFFIX)
	# Таблица — по убыванию счёта (rank_for на это рассчитывает); равные — в прежнем порядке.
	var order := range(all.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var sa := int(all[a]["score"])
		var sb := int(all[b]["score"])
		return sa > sb or (sa == sb and a < b))
	for i in mini(order.size(), SIZE):
		_list.append(all[order[i]])
	if not legacy and all.size() > SIZE:
		dropped += all.size() - SIZE
	if dropped > 0:
		_keep_bad(from, "%d bad entries dropped" % dropped)


## Испорченный файл — копия рядом (.bad): следующая запись перезапишет таблицу, а прежнее не пропадёт.
func _keep_bad(from: String, why: String) -> void:
	var bad := path + BAD_SUFFIX
	var err := DirAccess.copy_absolute(from, bad)
	push_warning("Leaderboard: %s is damaged (%s); copy kept in %s%s" % [from, why, bad,
			"" if err == OK else " — copy failed, error %d" % err])


func _save() -> void:
	var text := JSON.stringify({KEY: _list}, "\t")
	var tmp := path + TMP_SUFFIX
	if _write(tmp, text) and DirAccess.rename_absolute(tmp, path) == OK:
		return
	# Временный файл не записать или не переименовать — пишем прямо в файл таблицы.
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	if not _write(path, text):
		push_error("Leaderboard: cannot write %s" % path)


func _write(file_path: String, text: String) -> bool:
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	var ok := f.get_error() == OK
	f.close()
	return ok
