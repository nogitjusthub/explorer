class_name Job
extends RefCounted
## Задача для JobScheduler: выполняется порциями, пока не вернёт true из step().

var cancelled := false
var priority := 0.0


## Делает работу до дедлайна (Time.get_ticks_usec()). true — задача завершена.
func step(_deadline_usec: int) -> bool:
	return true


## Вызывается один раз после завершения (не вызывается для отменённых задач).
func on_done() -> void:
	pass
