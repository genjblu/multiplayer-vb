class_name SoundFX
extends RefCounted

static var _hit_normal: AudioStreamWAV = null
static var _hit_headshot: AudioStreamWAV = null
static var _footstep: AudioStreamWAV = null
static var _land: AudioStreamWAV = null
static var _gun_pistol: AudioStreamWAV = null
static var _gun_assault: AudioStreamWAV = null
static var _gun_shotgun: AudioStreamWAV = null
static var _gun_sniper: AudioStream = null
static var _double_jump: AudioStreamWAV = null
static var _mantle: AudioStreamWAV = null
static var _punch_swing: AudioStreamWAV = null
static var _punch_hit: AudioStreamWAV = null
static var _punch_heavy_hit: AudioStreamWAV = null
static var _punch_block: AudioStreamWAV = null
static var _dodge: AudioStreamWAV = null
static var _car_engine_loop: AudioStreamWAV = null
static var _car_crash: AudioStreamWAV = null
static var _car_explosion: AudioStreamWAV = null
static var _car_skid: AudioStreamWAV = null
static var _car_boost: AudioStreamWAV = null
static var _car_cannon: AudioStreamWAV = null
static var _web_shoot: AudioStreamWAV = null
static var _web_zip: AudioStreamWAV = null
static var _web_hit: AudioStreamWAV = null
static var _spider_sense: AudioStreamWAV = null
static var _super_jump: AudioStreamWAV = null
static var _web_throw: AudioStreamWAV = null

static func get_web_shoot() -> AudioStream:
	if _web_shoot == null:
		_web_shoot = _generate_web_shoot()
	return _web_shoot

static func get_web_zip() -> AudioStream:
	if _web_zip == null:
		_web_zip = _generate_web_zip()
	return _web_zip

static func get_web_hit() -> AudioStream:
	if _web_hit == null:
		_web_hit = _generate_web_hit()
	return _web_hit

static func get_spider_sense() -> AudioStream:
	if _spider_sense == null:
		_spider_sense = _generate_spider_sense()
	return _spider_sense

static func get_super_jump() -> AudioStream:
	if _super_jump == null:
		_super_jump = _generate_super_jump()
	return _super_jump

static func get_web_throw() -> AudioStream:
	if _web_throw == null:
		_web_throw = _generate_web_throw()
	return _web_throw

static func get_car_cannon() -> AudioStream:
	if _car_cannon == null:
		_car_cannon = _generate_car_cannon()
	return _car_cannon

static func _generate_car_cannon() -> AudioStreamWAV:
	return _create_wav(22050, 0.22, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 22.0)
		var punch: float = sin(t * TAU * (160.0 * exp(-t * 16.0))) * 0.75
		var blast: float = (randf() * 2.0 - 1.0) * exp(-t * 36.0) * 0.65
		return (punch + blast) * env
	)

static func get_car_engine_loop() -> AudioStream:
	if _car_engine_loop == null:
		_car_engine_loop = _generate_car_engine_loop()
	return _car_engine_loop

static func get_car_crash() -> AudioStream:
	if _car_crash == null:
		_car_crash = _generate_car_crash()
	return _car_crash

static func get_car_explosion() -> AudioStream:
	if _car_explosion == null:
		_car_explosion = _generate_car_explosion()
	return _car_explosion

static func get_car_skid() -> AudioStream:
	if _car_skid == null:
		_car_skid = _generate_car_skid()
	return _car_skid

static func get_car_boost() -> AudioStream:
	if _car_boost == null:
		_car_boost = _generate_car_boost()
	return _car_boost

static func get_hitmarker(is_headshot: bool) -> AudioStream:
	if is_headshot:
		if _hit_headshot == null:
			_hit_headshot = _generate_hit_headshot()
		return _hit_headshot
	else:
		if _hit_normal == null:
			_hit_normal = _generate_hit_normal()
		return _hit_normal

static func get_footstep() -> AudioStream:
	if _footstep == null:
		_footstep = _generate_footstep()
	return _footstep

static func get_jump_land() -> AudioStream:
	if _land == null:
		_land = _generate_jump_land()
	return _land

static func get_double_jump() -> AudioStream:
	if _double_jump == null:
		_double_jump = _generate_double_jump()
	return _double_jump

static func get_mantle() -> AudioStream:
	if _mantle == null:
		_mantle = _generate_mantle()
	return _mantle

static func get_gunshot(weapon_type: int) -> AudioStream:
	match weapon_type:
		0: # PISTOL
			if _gun_pistol == null:
				_gun_pistol = _generate_pistol_shot()
			return _gun_pistol
		1: # ASSAULT
			if _gun_assault == null:
				_gun_assault = _generate_assault_shot()
			return _gun_assault
		2: # SHOTGUN
			if _gun_shotgun == null:
				_gun_shotgun = _generate_shotgun_shot()
			return _gun_shotgun
		3: # SNIPER
			if _gun_sniper == null:
				if ResourceLoader.exists("res://Sounds/awp_shoot.mp3"):
					_gun_sniper = load("res://Sounds/awp_shoot.mp3") as AudioStream
				if _gun_sniper == null:
					_gun_sniper = _generate_shotgun_shot()
			return _gun_sniper
		_:
			if _gun_assault == null:
				_gun_assault = _generate_assault_shot()
			return _gun_assault

static func _create_wav(rate: int, duration: float, generator: Callable) -> AudioStreamWAV:
	var n: int = int(rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / float(rate)
		var s_val: float = clampf(generator.call(t, duration), -1.0, 1.0)
		var sample: int = clampi(int(s_val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav

# Хитмаркер в тело: короткий звонкий щелчок
static func _generate_hit_normal() -> AudioStreamWAV:
	return _create_wav(22050, 0.05, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 80.0)
		var tone: float = sin(t * TAU * 1750.0) * 0.7
		var click: float = (randf() * 2.0 - 1.0) * exp(-t * 200.0) * 0.3
		return (tone + click) * env
	)

# Хитмаркер в голову: чистый двухтональный звонкий колокольчик (headshot chime)
static func _generate_hit_headshot() -> AudioStreamWAV:
	return _create_wav(22050, 0.12, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 35.0)
		var f1: float = sin(t * TAU * 2400.0) * 0.55
		var f2: float = sin(t * TAU * 3600.0) * 0.45
		return (f1 + f2) * env
	)

# Шаг: глухой низкочастотный тук с лёгким шорохом
static func _generate_footstep() -> AudioStreamWAV:
	return _create_wav(22050, 0.08, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 45.0)
		var pitch: float = 120.0 * (1.0 - t * 4.0)
		var thud: float = sin(t * TAU * maxf(pitch, 50.0)) * 0.75
		var crunch: float = (randf() * 2.0 - 1.0) * 0.25
		return (thud + crunch) * env
	)

# Приземление после прыжка: более плотный и низкий удар о землю
static func _generate_jump_land() -> AudioStreamWAV:
	return _create_wav(22050, 0.14, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 25.0)
		var thud: float = sin(t * TAU * 85.0) * 0.8
		var noise: float = (randf() * 2.0 - 1.0) * exp(-t * 40.0) * 0.2
		return (thud + noise) * env
	)

# Пистолет: резкий сухой хлопок
static func _generate_pistol_shot() -> AudioStreamWAV:
	return _create_wav(22050, 0.14, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 32.0)
		var snap: float = (randf() * 2.0 - 1.0) * exp(-t * 90.0) * 0.6
		var body: float = sin(t * TAU * (380.0 * exp(-t * 25.0))) * 0.4
		return (snap + body) * env
	)

# Автомат: плотный хлёсткий выстрел с басовым ударом
static func _generate_assault_shot() -> AudioStreamWAV:
	return _create_wav(22050, 0.18, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 24.0)
		var crack: float = (randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.65
		var punch: float = sin(t * TAU * (220.0 * exp(-t * 18.0))) * 0.45
		return (crack + punch) * env
	)

# Дробовик: массивный взрывной грохот дроби
static func _generate_shotgun_shot() -> AudioStreamWAV:
	return _create_wav(22050, 0.28, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 16.0)
		var blast: float = (randf() * 2.0 - 1.0) * exp(-t * 30.0) * 0.7
		var rumble: float = sin(t * TAU * (110.0 * exp(-t * 12.0))) * 0.5
		return (blast + rumble) * env
	)

# Двойной прыжок (jump kit): реактивный импульсный выхлоп
static func _generate_double_jump() -> AudioStreamWAV:
	return _create_wav(22050, 0.16, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 22.0)
		var whoosh: float = (randf() * 2.0 - 1.0) * exp(-t * 15.0) * 0.65
		var low_jet: float = sin(t * TAU * (130.0 * (1.0 + t * 2.5))) * 0.35
		return (whoosh + low_jet) * env
	)

# Карабкание (мантл): шорох захвата за уступ
static func _generate_mantle() -> AudioStreamWAV:
	return _create_wav(22050, 0.15, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 24.0)
		var rustle: float = (randf() * 2.0 - 1.0) * exp(-t * 25.0) * 0.45
		var thud: float = sin(t * TAU * 115.0) * 0.5
		return (rustle + thud) * env
	)

static func get_punch_swing() -> AudioStream:
	if _punch_swing == null:
		_punch_swing = _generate_punch_swing()
	return _punch_swing

static func get_punch_hit(is_heavy: bool = false) -> AudioStream:
	if is_heavy:
		if _punch_heavy_hit == null:
			_punch_heavy_hit = _generate_punch_heavy_hit()
		return _punch_heavy_hit
	else:
		if _punch_hit == null:
			_punch_hit = _generate_punch_hit()
		return _punch_hit

static func get_punch_block() -> AudioStream:
	if _punch_block == null:
		_punch_block = _generate_punch_block()
	return _punch_block

static func get_dodge() -> AudioStream:
	if _dodge == null:
		_dodge = _generate_dodge()
	return _dodge

static func _generate_punch_swing() -> AudioStreamWAV:
	return _create_wav(22050, 0.12, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var whoosh: float = (randf() * 2.0 - 1.0) * env * 0.6
		var pitch: float = 240.0 * (1.0 - t / dur)
		var tone: float = sin(t * TAU * pitch) * 0.4 * env
		return whoosh + tone
	)

static func _generate_punch_hit() -> AudioStreamWAV:
	return _create_wav(22050, 0.16, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 28.0)
		var slap: float = (randf() * 2.0 - 1.0) * exp(-t * 50.0) * 0.7
		var thud: float = sin(t * TAU * 95.0) * 0.65
		return (slap + thud) * env
	)

static func _generate_punch_heavy_hit() -> AudioStreamWAV:
	return _create_wav(22050, 0.25, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 16.0)
		var crack: float = (randf() * 2.0 - 1.0) * exp(-t * 40.0) * 0.8
		var bass: float = sin(t * TAU * (70.0 * exp(-t * 8.0))) * 0.85
		return (crack + bass) * env
	)

static func _generate_punch_block() -> AudioStreamWAV:
	return _create_wav(22050, 0.14, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 32.0)
		var clank: float = sin(t * TAU * 190.0) * 0.65
		var noise: float = (randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.4
		return (clank + noise) * env
	)

static func _generate_dodge() -> AudioStreamWAV:
	return _create_wav(22050, 0.18, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var air: float = (randf() * 2.0 - 1.0) * env * 0.7
		var sweep: float = sin(t * TAU * (140.0 + 80.0 * sin(t / dur * PI))) * 0.35 * env
		return air + sweep
	)

static func _generate_car_engine_loop() -> AudioStreamWAV:
	var wav := _create_wav(22050, 0.5, func(t: float, dur: float) -> float:
		var rpm_freq: float = 55.0
		var cyl1: float = sin(t * TAU * rpm_freq) * 0.45
		var cyl2: float = sin(t * TAU * (rpm_freq * 2.0)) * 0.3
		var pulse: float = sin(t * TAU * (rpm_freq * 0.5)) * 0.2
		var rumble: float = (randf() * 2.0 - 1.0) * 0.15
		return (cyl1 + cyl2 + pulse + rumble) * 0.8
	)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(22050 * 0.5)
	return wav

static func _generate_car_crash() -> AudioStreamWAV:
	return _create_wav(22050, 0.45, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 9.0)
		var metal: float = sin(t * TAU * (180.0 * exp(-t * 12.0))) * 0.6
		var crunch: float = (randf() * 2.0 - 1.0) * exp(-t * 22.0) * 0.85
		var clatter: float = sin(t * TAU * 360.0) * exp(-t * 30.0) * 0.4
		return (metal + crunch + clatter) * env
	)

static func _generate_car_explosion() -> AudioStreamWAV:
	return _create_wav(22050, 1.2, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 3.5)
		var sub: float = sin(t * TAU * (55.0 * exp(-t * 4.0))) * 0.9
		var boom: float = (randf() * 2.0 - 1.0) * exp(-t * 6.0) * 0.8
		var flame: float = (randf() * 2.0 - 1.0) * exp(-t * 2.0) * 0.35
		return (sub + boom + flame) * env
	)

static func _generate_car_skid() -> AudioStreamWAV:
	return _create_wav(22050, 0.35, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var screech: float = sin(t * TAU * (750.0 + sin(t * 120.0) * 150.0)) * 0.5
		var tire_rub: float = (randf() * 2.0 - 1.0) * 0.6
		return (screech + tire_rub) * env * 0.7
	)

static func _generate_car_boost() -> AudioStreamWAV:
	return _create_wav(22050, 0.4, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var jet: float = (randf() * 2.0 - 1.0) * env * 0.65
		var spool: float = sin(t * TAU * (300.0 + (t / dur) * 600.0)) * 0.4 * env
		return jet + spool
	)

static func _generate_web_shoot() -> AudioStreamWAV:
	# Знаменитый звук "THWIP!": резкий щелчок картриджа + свист выпуска нити
	return _create_wav(22050, 0.18, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 26.0)
		var snap: float = sin(t * TAU * (1200.0 * exp(-t * 35.0))) * 0.8
		var hiss: float = (randf() * 2.0 - 1.0) * exp(-t * 18.0) * 0.55
		var whistle: float = sin(t * TAU * (850.0 + t * 400.0)) * 0.3 * exp(-t * 15.0)
		return (snap + hiss + whistle) * env
	)

static func _generate_web_zip() -> AudioStreamWAV:
	# Свист стремительного полета на натянутой струне
	return _create_wav(22050, 0.32, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var tension: float = sin(t * TAU * (450.0 + (t / dur) * 350.0)) * 0.5
		var rush: float = (randf() * 2.0 - 1.0) * 0.65 * env
		return (tension + rush) * env
	)

static func _generate_web_hit() -> AudioStreamWAV:
	# Плотный липкий удар паутины о поверхность/врага
	return _create_wav(22050, 0.15, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 32.0)
		var thud: float = sin(t * TAU * (140.0 * exp(-t * 20.0))) * 0.7
		var splat: float = (randf() * 2.0 - 1.0) * exp(-t * 40.0) * 0.6
		return (thud + splat) * env
	)

static func _generate_spider_sense() -> AudioStreamWAV:
	# Высокочастотное покалывающее чутье опасности
	return _create_wav(22050, 0.28, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var shimmer: float = sin(t * TAU * 1850.0) * sin(t * TAU * 36.0) * 0.65
		var sub_harm: float = sin(t * TAU * 925.0) * 0.35
		return (shimmer + sub_harm) * env
	)

static func _generate_super_jump() -> AudioStreamWAV:
	# Мощный упругий толчок ногами
	return _create_wav(22050, 0.35, func(t: float, dur: float) -> float:
		var env: float = exp(-t * 10.0)
		var whoosh: float = sin(t * TAU * (90.0 + t * 240.0)) * 0.75 * env
		var pop: float = (randf() * 2.0 - 1.0) * exp(-t * 28.0) * 0.5
		return (whoosh + pop) * env
	)

static func _generate_web_throw() -> AudioStreamWAV:
	# Раскручивание предмета на паутине
	return _create_wav(22050, 0.45, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var spin: float = sin(t * TAU * (120.0 + sin(t * TAU * 4.0) * 80.0)) * 0.7
		var air: float = (randf() * 2.0 - 1.0) * 0.4 * env
		return (spin + air) * env
	)

