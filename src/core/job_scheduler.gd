class_name JobScheduler
extends Node
## Очередь фоновых задач (генерация, мешинг) с бюджетом времени на кадр.
## Веб-сборка однопоточная, поэтому вся тяжёлая работа идёт здесь порциями.
## Меньший priority выполняется раньше.

var budget_usec: int = 4000
var last_frame_usec: int = 0       ## сколько задачи заняли в прошлом кадре
var max_frame_usec: int = 0        ## максимум за время жизни (для бенчмарка)

var _jobs: Array[Job] = []


func _ready() -> void:
	if OS.has_feature("web"):
		budget_usec = 6000


func enqueue(job: Job, priority: float) -> void:
	job.priority = priority
	var i := _jobs.bsearch_custom(job, func(a: Job, b: Job) -> bool: return a.priority < b.priority, false)
	_jobs.insert(i, job)


func pending() -> int:
	return _jobs.size()


## Пересортировка после изменения приоритетов.
func resort() -> void:
	_jobs.sort_custom(func(a: Job, b: Job) -> bool: return a.priority < b.priority)


## Выполняет все задачи без ограничения времени (загрузочный экран, тесты).
func run_all() -> void:
	while not _jobs.is_empty():
		_run_front(Time.get_ticks_usec() + 3_600_000_000)


func _process(_delta: float) -> void:
	var start := Time.get_ticks_usec()
	var deadline := start + budget_usec
	while not _jobs.is_empty() and Time.get_ticks_usec() < deadline:
		_run_front(deadline)
	last_frame_usec = Time.get_ticks_usec() - start
	max_frame_usec = maxi(max_frame_usec, last_frame_usec)


func _run_front(deadline: int) -> void:
	var job := _jobs[0]
	if job.cancelled:
		_jobs.pop_front()
		return
	if job.step(deadline):
		_jobs.erase(job)   # on_done предыдущих задач мог вставить новые перед этой
		job.on_done()
