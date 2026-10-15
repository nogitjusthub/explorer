extends TestCase
## Состояние забега (GDD §2, §6, §7): HP, топливо, трюм с вытеснением, счёт и бонус.


func _run(slots: int = 10) -> RunState:
	var cls := (load("res://data/vehicles/rover.tres") as VehicleClass).duplicate() as VehicleClass
	cls.cargo_slots = slots
	var rs := RunState.new(cls, BalanceRules.new())
	rs.invulnerable = 0.0
	return rs


func _kind(id: StringName) -> PickupKind:
	return load("res://data/pickups/%s.tres" % id)


func test_damage_and_death() -> void:
	var rs := _run()
	assert_false(rs.damage(40, &"fall"))
	assert_eq(rs.hp, 60)
	assert_true(rs.damage(80, &"fall"), "died")
	assert_eq(rs.hp, 0)
	assert_eq(rs.ended_cause, &"fall")
	assert_false(rs.damage(10, &"fall"), "no damage after the end")


func test_invulnerable_after_drop() -> void:
	var rs := RunState.new(load("res://data/vehicles/rover.tres"), BalanceRules.new())
	assert_false(rs.damage(50, &"fall"))
	assert_eq(rs.hp, 100, "no damage during drop invulnerability")
	rs.tick(3.1)
	rs.damage(50, &"fall")
	assert_eq(rs.hp, 50)


func test_fuel_burn_and_empty() -> void:
	var rs := _run()
	var became_empty := false
	for _i in 60 * 60 * 7:        # 7 минут полного газа при расходе 15 ед./мин и баке 100
		became_empty = rs.burn_fuel(1.0 / 60.0, 1.0) or became_empty
	assert_true(became_empty)
	assert_eq(rs.fuel, 0.0)
	rs.add_fuel(500.0)
	assert_eq(rs.fuel, 100.0, "refuel capped by the tank")


func test_cargo_displaces_cheapest_for_more_valuable() -> void:
	var rs := _run(3)
	for _i in 3:
		assert_true(rs.offer_cargo(_kind(&"crystal")).accepted)
	# Образец (50) на полный трюм кристаллов (по 10): вытесняется один кристалл.
	var offer := rs.offer_cargo(_kind(&"sample"))
	assert_true(offer.accepted)
	assert_eq(offer.displaced.size(), 1)
	assert_eq(rs.cargo_value(), 70)
	# Кристалл (10) на трюм дороже себя — отказ.
	assert_false(rs.offer_cargo(_kind(&"crystal")).accepted)
	# Ядро (400, 2 слота) вытесняет два самых дешёвых.
	offer = rs.offer_cargo(_kind(&"core"))
	assert_true(offer.accepted)
	assert_eq(offer.displaced.size(), 2)
	assert_eq(rs.cargo_slots_used(), 3)
	assert_eq(rs.cargo_value(), 450)


func test_ship_emergency_and_score() -> void:
	var rs := _run()
	rs.offer_cargo(_kind(&"core"))
	assert_eq(rs.ship_cargo(), 400)
	assert_eq(rs.score(), 400)
	assert_eq(rs.cargo_value(), 0)
	assert_eq(rs.ship_cargo(), 0)
	assert_eq(rs.shipments, 1, "empty hold is not a shipment")
	rs.offer_cargo(_kind(&"sample"))
	rs.fuel = 10.0
	rs.hp = 60
	# Аварийный: 50 × 0,5 − 500 = −475; привёз 20 топлива и 10 запчастей (+10 HP).
	assert_eq(rs.emergency_ship(20.0, 10), -475)
	assert_near(rs.fuel, 30.0, 1e-4)
	assert_eq(rs.hp, 70)
	assert_eq(rs.score(), 0, "score never below zero")
	# Второй вызов вдвое дороже; запчасти не чинят выше максимума.
	assert_eq(rs.emergency_ship(0.0, 30), -1000)
	assert_eq(rs.hp, 100)


func test_no_shipping_after_the_end() -> void:
	var rs := _run()
	rs.offer_cargo(_kind(&"core"))
	rs.end(&"fall")
	var shipped := []
	rs.score_changed.connect(func(s: int) -> void: shipped.append(s))
	assert_eq(rs.ship_cargo(), 0, "the shuttle menu left open after death gives nothing")
	assert_eq(rs.emergency_ship(20.0, 10), 0, "no emergency exchange after the end")
	assert_eq(rs.banked, 0)
	assert_eq(rs.shipments, 0)
	assert_eq(rs.emergency_calls, 0)
	assert_eq(rs.final_score, 0)
	assert_eq(shipped.size(), 0, "no score updates after the end")


func test_evacuation_bonus_and_lost_cargo_on_death() -> void:
	var rs := _run()
	rs.offer_cargo(_kind(&"core"))
	rs.hp = 50
	rs.fuel = 20.0
	rs.evacuate()
	assert_eq(rs.ended_cause, RunState.CAUSE_EVACUATED)
	assert_eq(rs.final_score, 400 + 50 * 3 + 20 * 2)
	var dead := _run()
	dead.offer_cargo(_kind(&"core"))
	dead.end(&"drowned")
	assert_eq(dead.final_score, 0, "cargo is lost on death")


func test_leaderboard_ranks_and_persists() -> void:
	var path := "user://test_leaderboard_%d.json" % Time.get_ticks_usec()
	var board := Leaderboard.new(path)
	for i in 12:
		board.add({"name": "T%02d" % i, "score": i * 100, "time": 60.0, "shipments": 1, "cause": "evacuated"})
	var list := board.entries()
	assert_eq(list.size(), Leaderboard.SIZE, "top 10 only")
	assert_eq(int(list[0]["score"]), 1100, "sorted by score")
	assert_eq(board.rank_for(50), -1, "too low for the table")
	assert_eq(board.rank_for(5000), 0)
	var reloaded := Leaderboard.new(path)
	assert_eq(reloaded.entries().size(), Leaderboard.SIZE, "saved to disk")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
