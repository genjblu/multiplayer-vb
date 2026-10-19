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
