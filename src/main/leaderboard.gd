class_name Leaderboard
extends RefCounted
## Локальная таблица рекордов (GDD §6): топ-10 отдельно по каждому классу машины, user://.

const DEFAULT_PATH := "user://leaderboard.json"
const SIZE := 10

var path: String
var _tables: Dictionary = {}     ## класс → массив записей {name, score, time, shipments, cause, date}


func _init(file_path: String = DEFAULT_PATH) -> void:
	path = file_path
	_load()


func entries(class_id: StringName) -> Array:
	return _tables.get(String(class_id), [])


## Позиция, которую займёт счёт (0 — первое место), или -1, если в топ не попадает.
func rank_for(class_id: StringName, score: int) -> int:
	var list := entries(class_id)
	for i in list.size():
		if score > int(list[i]["score"]):
			return i
	return list.size() if list.size() < SIZE else -1


## Добавляет запись и сохраняет файл. Возвращает её место (0..9) или -1.
func add(class_id: StringName, entry: Dictionary) -> int:
	var rank := rank_for(class_id, int(entry["score"]))
	if rank < 0:
		return -1
	var list: Array = entries(class_id).duplicate()
	list.insert(rank, entry)
	if list.size() > SIZE:
		list.resize(SIZE)
	_tables[String(class_id)] = list
	_save()
	return rank


func _load() -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_tables = parsed


func _save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Leaderboard: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(_tables, "\t"))
