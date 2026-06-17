# sha512.gd
# SHA-512 for Godot 4 GDScript — ported from sha512.py (MicroPython/Algorand)
#
# GDScript int is 64-bit signed; SHA-512 uses 64-bit unsigned arithmetic.
# Adaptation: _ushr() replaces >> for logical (unsigned) right shifts.
# Addition naturally wraps to lower 64 bits in GDScript (correct behavior).

class_name SHA512

# === Instance state ===
var _h: Array       # 8 × int64 hash words
var _buf: PackedByteArray
var _msg_len: int   # total bytes fed so far

func _init(iv: Array = []) -> void:
	if iv.size() == 8:
		_h = iv.duplicate()
	else:
		_h = _default_iv()
	_buf = PackedByteArray()
	_msg_len = 0

# ── SHA-512 initial hash values ──────────────────────────────────────────────
static func _default_iv() -> Array:
	return [
		7640891576956012808,   # 0x6a09e667f3bcc908
		-4942790177534073029,  # 0xbb67ae8584caa73b
		4354685564936845355,   # 0x3c6ef372fe94f82b
		-6534734903238641935,  # 0xa54ff53a5f1d36f1
		5840696475078001361,   # 0x510e527fade682d1
		-7276294671716946913,  # 0x9b05688c2b3e6c1f
		2270897969802886507,   # 0x1f83d9abfb41bd6b
		6620516959819538809,   # 0x5be0cd19137e2179
	]

# SHA-512/256 IV — used for Algorand address checksum
static func _sha512_256_iv() -> Array:
	return [
		2463787394917988140,   # 0x22312194FC2BF72C
		-6965556091613846334,  # 0x9F555FA3C84C64C2
		2563595384472711505,   # 0x2393B86B6F53B151
		-7622211418569250115,  # 0x963877195940EABD
		-7626776825740460061,  # 0x96283EE2A88EFFE3
		-4729309413028513390,  # 0xBE5E1E2553863992
		3098927326965381290,   # 0x2B0199FC2C85B8AA
		1060366662362279074,   # 0x0EB72DDC81C52CA2
	]

# ── SHA-512 round constants (80 values) ──────────────────────────────────────
static var _K: Array = []

static func _init_K() -> void:
	if not _K.is_empty():
		return
	_K = [
		4794697086780616226, 8158064640168781261, -5349999486874862801, -1606136188198331460,
		4131703408338449720, 6480981068601479193, -7908458776815382629, -6116909921290321640,
		-2880145864133508542, 1334009975649890238, 2608012711638119052, 6128411473006802146,
		8268148722764581231, -9160688886553864527, -7215885187991268811, -4495734319001033068,
		-1973867731355612462, -1171420211273849373, 1135362057144423861, 2597628984639134821,
		3308224258029322869, 5365058923640841347, 6679025012923562964, 8573033837759648693,
		-7476448914759557205, -6327057829258317296, -5763719355590565569, -4658551843659510044,
		-4116276920077217854, -3051310485924567259, 489312712824947311, 1452737877330783856,
		2861767655752347644, 3322285676063803686, 5560940570517711597, 5996557281743188959,
		7280758554555802590, 8532644243296465576, -9096487096722542874, -7894198246740708037,
		-6719396339535248540, -6333637450476146687, -4446306890439682159, -4076793802049405392,
		-3345356375505022440, -2983346525034927856, -860691631967231958, 1182934255886127544,
		1847814050463011016, 2177327727835720531, 2830643537854262169, 3796741975233480872,
		4115178125766777443, 5681478168544905931, 6601373596472566643, 7507060721942968483,
		8399075790359081724, 8693463985226723168, -8878714635349349518, -8302665154208450068,
		-8016688836872298968, -6606660893046293015, -4685533653050689259, -4147400797238176981,
		-3880063495543823972, -3348786107499101689, -1523767162380948706, -757361751448694408,
		500013540394364858, 748580250866718886, 1242879168328830382, 1977374033974150939,
		2944078676154940804, 3659926193048069267, 4368137639120453308, 4836135668995329356,
		5532061633213252278, 6448918945643986474, 6902733635092675308, 7801388544844847127,
	]

# ── Bit-level helpers ─────────────────────────────────────────────────────────

# Logical (unsigned) right shift — GDScript >> is arithmetic (sign-extending)
static func _ushr(x: int, n: int) -> int:
	if n >= 64:
		return 0
	if n == 0:
		return x
	var r: int = x >> n
	if x < 0:
		# Arithmetic shift filled top n bits with 1; clear them
		r = r & ((1 << (64 - n)) - 1)
	return r

# 64-bit right rotation (treats x as unsigned 64-bit)
static func _rotr64(x: int, n: int) -> int:
	return _ushr(x, n) | ((x & ((1 << n) - 1)) << (64 - n))

# ── Core compression ──────────────────────────────────────────────────────────

func _process_block(offset: int) -> void:
	_init_K()
	# Unpack 16 big-endian uint64 words from _buf[offset..offset+128)
	var w: Array = []
	for i in range(16):
		var val: int = 0
		var base: int = offset + i * 8
		for j in range(8):
			val = (val << 8) | _buf[base + j]
		w.append(val)
	# Message schedule expansion
	for i in range(16, 80):
		var wi15: int = w[i - 15]
		var wi2: int  = w[i - 2]
		var s0: int = _rotr64(wi15, 1) ^ _rotr64(wi15, 8) ^ _ushr(wi15, 7)
		var s1: int = _rotr64(wi2, 19) ^ _rotr64(wi2, 61) ^ _ushr(wi2, 6)
		w.append(w[i - 16] + s0 + w[i - 7] + s1)

	var a: int = _h[0]; var b: int = _h[1]
	var c: int = _h[2]; var d: int = _h[3]
	var e: int = _h[4]; var f: int = _h[5]
	var g: int = _h[6]; var hh: int = _h[7]

	for i in range(80):
		var S1: int    = _rotr64(e, 14) ^ _rotr64(e, 18) ^ _rotr64(e, 41)
		var ch: int    = (e & f) ^ (~e & g)
		var temp1: int = hh + S1 + ch + _K[i] + w[i]
		var S0: int    = _rotr64(a, 28) ^ _rotr64(a, 34) ^ _rotr64(a, 39)
		var maj: int   = (a & b) ^ (a & c) ^ (b & c)
		var temp2: int = S0 + maj
		hh = g;  g = f;  f = e;  e = d + temp1
		d  = c;  c = b;  b = a;  a = temp1 + temp2

	_h[0] += a; _h[1] += b; _h[2] += c; _h[3] += d
	_h[4] += e; _h[5] += f; _h[6] += g; _h[7] += hh

# ── Public API ────────────────────────────────────────────────────────────────

func update(data: PackedByteArray) -> SHA512:
	_msg_len += data.size()
	_buf.append_array(data)
	var processed: int = 0
	while _buf.size() - processed >= 128:
		_process_block(processed)
		processed += 128
	if processed > 0:
		_buf = _buf.slice(processed)
	return self

func digest() -> PackedByteArray:
	# Snapshot state so digest() is non-destructive
	var h_save: Array = _h.duplicate()
	var buf_save: PackedByteArray = _buf.duplicate()
	var len_save: int = _msg_len

	# Padding: append 0x80, zero-pad to 112 mod 128, then 16-byte bit count
	var msg_bits: int = _msg_len * 8
	_buf.append(0x80)
	while _buf.size() % 128 != 112:
		_buf.append(0)
	for _i in range(8):  # upper 64 bits of bit count (always 0 for our use)
		_buf.append(0)
	# Lower 64 bits, big-endian
	_buf.append(_ushr(msg_bits, 56) & 0xFF)
	_buf.append(_ushr(msg_bits, 48) & 0xFF)
	_buf.append(_ushr(msg_bits, 40) & 0xFF)
	_buf.append(_ushr(msg_bits, 32) & 0xFF)
	_buf.append(_ushr(msg_bits, 24) & 0xFF)
	_buf.append(_ushr(msg_bits, 16) & 0xFF)
	_buf.append(_ushr(msg_bits, 8)  & 0xFF)
	_buf.append(msg_bits & 0xFF)

	var processed: int = 0
	while processed < _buf.size():
		_process_block(processed)
		processed += 128

	# Serialize hash words big-endian
	var result := PackedByteArray()
	result.resize(64)
	for i in range(8):
		var val: int = _h[i]
		for j in range(7, -1, -1):
			result[i * 8 + j] = val & 0xFF
			val = _ushr(val, 8)

	# Restore state
	_h = h_save
	_buf = buf_save
	_msg_len = len_save
	return result

# ── Static convenience ────────────────────────────────────────────────────────

# Hash data and return first n_bytes of digest (default: full 64 bytes)
static func hash(data: PackedByteArray, n_bytes: int = 64, iv: Array = []) -> PackedByteArray:
	var h := SHA512.new(iv)
	h.update(data)
	return h.digest().slice(0, n_bytes)

# SHA-512/256: SHA-512 with Algorand's IV, first 32 bytes of output
static func sha512_256(data: PackedByteArray) -> PackedByteArray:
	return SHA512.hash(data, 32, _sha512_256_iv())
