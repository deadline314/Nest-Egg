extends MeleeModule
## Negative control: restore ONLY pre-a5dd106c feedback coordinates on the current module.
## Damage, hurtboxes, timing, sound, knockback and input remain current.

func hit_pass() -> void:
	var def := attack
	var knock: Array = def["knockback"]
	var heavy := int(def["stagger"]) >= 3
	var landed_now := false
	# 武器打到的點：揮擊方向上、攻擊距離約四分之三處；每個目標的回饋放在自己受擊範圍內最靠近這一點的位置（NE-268）。
	for target_hurtbox in targets(def):
		var id := target_hurtbox.health.get_instance_id() if target_hurtbox.health != null else target_hurtbox.get_instance_id()
		if hit_ids.has(id):
			continue
		var info := DamageInfo.create(_damage_now(def), Combat.Team.PLAYER, &"melee", Vector2(swing_facing * float(knock[0]), float(knock[1])))
		info.stagger = int(def["stagger"])
		info.impact = float(def["impact"])
		info.attacker = weakref(host)
		info.freeze_attacker = not feedback_done and hit_ids.is_empty()
		info.origin = host.global_position
		var result := target_hurtbox.receive(info)
		if result != Hurtbox.Result.IGNORED:
			hit_ids[id] = true
		if result == Hurtbox.Result.DAMAGED:
			landed = true
			landed_now = true
			EventBus.hit_confirmed.emit(target_hurtbox.global_position, target_hurtbox.health.is_dead)
			EventBus.hit_marker.emit(&"kill" if target_hurtbox.health.is_dead else (&"weak" if info.weak_hit else &"hit"))
			if info.weak_hit or int(def["stagger"]) >= 3:
				EventBus.damage_number.emit(target_hurtbox.global_position + Vector2(0, -24), info.amount, &"weak" if info.weak_hit else &"crit", target_hurtbox.health.get_instance_id())
			MeleeFx.hit(target_hurtbox.center(), direction(def), color_of(def), StringName(str(def["impact_fx"])), heavy)
			HitFeedback.play(target_hurtbox.material_id(), target_hurtbox.global_position, Vector2(-host.facing, -0.2), Palette.CYAN, {"weak": info.weak_hit})
	if landed_now and not feedback_done:
		feedback_done = true
		InputBindings.vibrate(0.25, 0.45 if heavy else 0.2, 0.1)
		# 延後到物理步驟之後：頓幀會停用自己，不能在自己的物理處理中途做。被打到的敵人在 Enemy 裡依受擊層級自己凍結。
		# 頓幀一招只有一次（多段、多目標都不疊加）。
		var ctx := {"targets": [host], "dir": host.aim_dir, "origin": host.global_position}
		if float(def["hitstop"]) > 0.0:
			ctx["freeze"] = float(def["hitstop"])
		Feel.play.call_deferred(StringName(str(def["event"])), ctx)
	if landed_now and not _window_sound_done:
		# 命中聲分層（MeleeFx 的回饋層之一）：低頻的悶擊在下、高頻的切割或撞擊在上；多段攻擊每一段各響一次。
		_window_sound_done = true
		for layer in MeleeMove.hit_layers(def):
			Sfx.play_named(layer, -3.0 if not heavy else 0.0)

