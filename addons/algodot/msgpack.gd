# msgpack.gd
# Minimal MessagePack encoder for Godot 4 GDScript.
# Ported from msgpack.py (MicroPython for Algorand).
#
# Supports exactly the subset Algorand transactions require:
#   - positive integers
#   - bytes (PackedByteArray) → bin8 / bin16
#   - strings                 → fixstr / str8 / str16
#   - dicts (sorted keys, null values skipped) → fixmap / map16
#   - arrays / PackedByteArrays of ints        → fixarray / array16
#   - booleans

class_name MsgPack

# ── Public API ────────────────────────────────────────────────────────────────

static func pack(v) -> PackedByteArray:
	if v == null:
		return PackedByteArray([0xc0])               # nil
	elif typeof(v) == TYPE_BOOL:
		return PackedByteArray([0xc3 if v else 0xc2])
	elif typeof(v) == TYPE_INT:
		return _pack_int(v)
	elif typeof(v) == TYPE_PACKED_BYTE_ARRAY:
		return _pack_bytes(v)
	elif typeof(v) == TYPE_STRING:
		return _pack_str(v)
	elif typeof(v) == TYPE_DICTIONARY:
		return _pack_map(v)
	elif typeof(v) == TYPE_ARRAY:
		return _pack_array(v)
	else:
		push_error("MsgPack.pack: unsupported type %d" % typeof(v))
		return PackedByteArray()

# ── Integer ───────────────────────────────────────────────────────────────────

static func _pack_int(n: int) -> PackedByteArray:
	if n < 0:
		push_error("MsgPack: negative ints not supported")
		return PackedByteArray()
	if n <= 0x7f:
		return PackedByteArray([n])
	elif n <= 0xff:
		return PackedByteArray([0xcc, n])
	elif n <= 0xffff:
		return PackedByteArray([0xcd, (n >> 8) & 0xFF, n & 0xFF])
	elif n <= 0xffffffff:
		return PackedByteArray([0xce,
			(n >> 24) & 0xFF, (n >> 16) & 0xFF,
			(n >> 8)  & 0xFF,  n & 0xFF])
	else:
		return PackedByteArray([0xcf,
			(n >> 56) & 0xFF, (n >> 48) & 0xFF,
			(n >> 40) & 0xFF, (n >> 32) & 0xFF,
			(n >> 24) & 0xFF, (n >> 16) & 0xFF,
			(n >> 8)  & 0xFF,  n & 0xFF])

# ── Bytes (bin) ───────────────────────────────────────────────────────────────

static func _pack_bytes(b: PackedByteArray) -> PackedByteArray:
	var n: int = b.size()
	var header: PackedByteArray
	if n <= 0xff:
		header = PackedByteArray([0xc4, n])
	elif n <= 0xffff:
		header = PackedByteArray([0xc5, (n >> 8) & 0xFF, n & 0xFF])
	else:
		push_error("MsgPack: bytes too long")
		return PackedByteArray()
	header.append_array(b)
	return header

# ── String ────────────────────────────────────────────────────────────────────

static func _pack_str(s: String) -> PackedByteArray:
	var b: PackedByteArray = s.to_utf8_buffer()
	var n: int = b.size()
	var header: PackedByteArray
	if n <= 31:
		header = PackedByteArray([0xa0 | n])
	elif n <= 0xff:
		header = PackedByteArray([0xd9, n])
	elif n <= 0xffff:
		header = PackedByteArray([0xda, (n >> 8) & 0xFF, n & 0xFF])
	else:
		push_error("MsgPack: string too long")
		return PackedByteArray()
	header.append_array(b)
	return header

# ── Map (dict with sorted string keys, null values omitted) ───────────────────

static func _pack_map(d: Dictionary) -> PackedByteArray:
	# Collect non-null pairs and sort by key
	var pairs: Array = []
	for k in d.keys():
		if d[k] != null:
			pairs.append([k, d[k]])
	pairs.sort_custom(func(a, b): return a[0] < b[0])

	var n: int = pairs.size()
	var result: PackedByteArray
	if n <= 15:
		result = PackedByteArray([0x80 | n])
	elif n <= 0xffff:
		result = PackedByteArray([0xde, (n >> 8) & 0xFF, n & 0xFF])
	else:
		push_error("MsgPack: map too large")
		return PackedByteArray()

	for pair in pairs:
		result.append_array(_pack_str(pair[0]))
		result.append_array(pack(pair[1]))
	return result

# ── Array ─────────────────────────────────────────────────────────────────────

static func _pack_array(arr: Array) -> PackedByteArray:
	var n: int = arr.size()
	var result: PackedByteArray
	if n <= 15:
		result = PackedByteArray([0x90 | n])
	elif n <= 0xffff:
		result = PackedByteArray([0xdc, (n >> 8) & 0xFF, n & 0xFF])
	else:
		push_error("MsgPack: array too large")
		return PackedByteArray()
	for item in arr:
		result.append_array(pack(item))
	return result
