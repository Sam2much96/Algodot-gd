# bigint.gd
# Arbitrary-precision non-negative integer arithmetic for Godot 4 GDScript.
# Used exclusively by ed25519.gd for 255-bit field/scalar arithmetic.
#
# Representation: Array of int, each in [0, 65535] (16-bit limbs), LE order.
#   N  = 16 limbs = 256 bits  (field elements, scalars)
#   N2 = 32 limbs = 512 bits  (products before reduction)
#
# Why 16-bit limbs? Multiplying two 16-bit values gives at most 65535² ≈ 4.3 GB
# which fits comfortably in GDScript's signed int64.  32-bit limbs would overflow.

class_name BigInt

const N  = 16   # limbs for a 256-bit value
const N2 = 32   # limbs for a 512-bit value
const MASK = 0xFFFF

# ── Field prime q = 2^255 - 19 ────────────────────────────────────────────────
# 16-bit LE limbs: [0xFFED, 0xFFFF×14, 0x7FFF]
static var Q: Array = [
	65517, 65535, 65535, 65535, 65535, 65535, 65535, 65535,
	65535, 65535, 65535, 65535, 65535, 65535, 65535, 32767,
]

# ── Group order l = 2^252 + 27742317777372353535851937790883648493 ─────────────
static var L: Array = [
	54253, 23797, 25370, 22546, 40150, 41719, 63966, 5342,
	0, 0, 0, 0, 0, 0, 0, 4096,
]

# ─────────────────────────────────────────────────────────────────────────────
# Constructors / converters
# ─────────────────────────────────────────────────────────────────────────────

static func zero(n: int = N) -> Array:
	var a: Array = []; a.resize(n)
	for i in range(n): a[i] = 0
	return a

static func one(n: int = N) -> Array:
	var a: Array = zero(n); a[0] = 1; return a

# From a small non-negative GDScript int (fits in a few limbs)
static func from_small(v: int, n: int = N) -> Array:
	var a: Array = zero(n)
	var i: int = 0
	while v > 0 and i < n:
		a[i] = v & MASK
		v = v >> 16
		i += 1
	return a

# From big-endian bytes (like Python's int.from_bytes with 'big')
static func from_bytes_be(b: PackedByteArray, n: int = N) -> Array:
	var a: Array = zero(n)
	var byte_len: int = b.size()
	for bi in range(byte_len):
		var limb_idx: int = (byte_len - 1 - bi) >> 1   # which 16-bit limb
		var shift: int = ((byte_len - 1 - bi) & 1) * 8  # 0 or 8
		if limb_idx < n:
			a[limb_idx] |= b[bi] << shift
	return a

# From little-endian bytes
static func from_bytes_le(b: PackedByteArray, n: int = N) -> Array:
	var a: Array = zero(n)
	var byte_len: int = b.size()
	for bi in range(byte_len):
		var limb_idx: int = bi >> 1
		var shift: int = (bi & 1) * 8
		if limb_idx < n:
			a[limb_idx] |= b[bi] << shift
	return a

# To little-endian bytes (fixed length)
static func to_bytes_le(a: Array, n_bytes: int = 32) -> PackedByteArray:
	var out := PackedByteArray(); out.resize(n_bytes)
	for i in range(n_bytes):
		var limb_idx: int = i >> 1
		var shift: int = (i & 1) * 8
		var v: int = 0
		if limb_idx < a.size():
			v = (a[limb_idx] >> shift) & 0xFF
		out[i] = v
	return out

# Hex string (big-endian, for debugging)
static func to_hex(a: Array) -> String:
	var s: String = ""
	for i in range(a.size() - 1, -1, -1):
		s += "%04x" % a[i]
	return s

# ─────────────────────────────────────────────────────────────────────────────
# Comparison / predicate
# ─────────────────────────────────────────────────────────────────────────────

static func cmp(a: Array, b: Array) -> int:
	var n: int = maxi(a.size(), b.size())
	for i in range(n - 1, -1, -1):
		var ai: int = a[i] if i < a.size() else 0
		var bi: int = b[i] if i < b.size() else 0
		if ai > bi: return 1
		if ai < bi: return -1
	return 0

static func is_zero(a: Array) -> bool:
	for v in a:
		if v != 0: return false
	return true

# Get bit i (0 = LSB)
static func bit(a: Array, i: int) -> int:
	var limb_idx: int = i >> 4   # i / 16
	var bit_idx: int  = i & 15   # i % 16
	if limb_idx >= a.size(): return 0
	return (a[limb_idx] >> bit_idx) & 1

# Bit length (position of highest set bit + 1)
static func bit_length(a: Array) -> int:
	for i in range(a.size() - 1, -1, -1):
		if a[i] != 0:
			var v: int = a[i]
			var bits: int = 0
			while v > 0:
				v >>= 1
				bits += 1
			return i * 16 + bits
	return 0

# ─────────────────────────────────────────────────────────────────────────────
# Basic arithmetic (no reduction)
# ─────────────────────────────────────────────────────────────────────────────

# Add two same-size arrays; result may have one extra carry limb
static func add(a: Array, b: Array) -> Array:
	var n: int = maxi(a.size(), b.size())
	var result: Array = zero(n + 1)
	var carry: int = 0
	for i in range(n):
		var ai: int = a[i] if i < a.size() else 0
		var bi: int = b[i] if i < b.size() else 0
		var s: int = ai + bi + carry
		result[i] = s & MASK
		carry = s >> 16
	result[n] = carry
	return result

# Subtract b from a (assumes a >= b); result has same size as a
static func sub(a: Array, b: Array) -> Array:
	var n: int = a.size()
	var result: Array = zero(n)
	var borrow: int = 0
	for i in range(n):
		var bi: int = b[i] if i < b.size() else 0
		var d: int = a[i] - bi - borrow
		if d < 0:
			d += 65536
			borrow = 1
		else:
			borrow = 0
		result[i] = d
	return result

# Multiply two N-limb numbers; result has 2N limbs
static func mul(a: Array, b: Array) -> Array:
	var na: int = a.size()
	var nb: int = b.size()
	var result: Array = zero(na + nb)
	for i in range(na):
		if a[i] == 0:
			continue
		var carry: int = 0
		for j in range(nb):
			var cur: int = result[i + j] + a[i] * b[j] + carry
			result[i + j] = cur & MASK
			carry = cur >> 16
		# Propagate carry
		var k: int = i + nb
		while carry > 0:
			var cur: int = result[k] + carry
			result[k] = cur & MASK
			carry = cur >> 16
			k += 1
	return result

# Multiply by a small integer s (fits in a limb or few)
static func mul_small(a: Array, s: int) -> Array:
	var n: int = a.size()
	var result: Array = zero(n + 2)
	var carry: int = 0
	for i in range(n):
		var cur: int = a[i] * s + carry
		result[i] = cur & MASK
		carry = cur >> 16
	var i: int = n
	while carry > 0:
		result[i] = carry & MASK
		carry >>= 16
		i += 1
	return result

# Logical right shift by 1 bit
static func shr1(a: Array) -> Array:
	var n: int = a.size()
	var result: Array = zero(n)
	var carry: int = 0
	for i in range(n - 1, -1, -1):
		result[i] = (carry << 15) | (a[i] >> 1)
		carry = a[i] & 1
	return result

# Left shift by 1 bit
static func shl1(a: Array) -> Array:
	var n: int = a.size()
	var result: Array = zero(n + 1)
	var carry: int = 0
	for i in range(n):
		var v: int = (a[i] << 1) | carry
		result[i] = v & MASK
		carry = v >> 16
	result[n] = carry
	return result

# ─────────────────────────────────────────────────────────────────────────────
# Modular arithmetic (general)
# ─────────────────────────────────────────────────────────────────────────────

# General mod: a mod m (binary long division)
# a can be any size; m is N limbs; result is N limbs
static func mod(a: Array, m: Array) -> Array:
	if cmp(a, m) < 0:
		# Already reduced; pad/trim to N limbs
		var r: Array = zero(N)
		for i in range(mini(a.size(), N)):
			r[i] = a[i]
		return r

	var n_bits: int = bit_length(a)
	var r: Array = zero(N + 2)   # accumulator (slightly larger than m)

	for i in range(n_bits - 1, -1, -1):
		# r = r * 2 + bit(a, i)
		r = shl1(r)
		r[0] |= bit(a, i)
		# Trim r to N+2 limbs (it can grow by at most 1 bit each iteration)
		if r.size() > N + 2:
			r = r.slice(0, N + 2)
		if cmp(r, m) >= 0:
			r = sub(r, m)

	var result: Array = zero(N)
	for i in range(N):
		result[i] = r[i] if i < r.size() else 0
	return result

# a + b mod m
static func addmod(a: Array, b: Array, m: Array) -> Array:
	var s: Array = add(a, b)
	if cmp(s, m) >= 0:
		s = sub(s, m)
	# Trim to N limbs
	var result: Array = zero(N)
	for i in range(N):
		result[i] = s[i] if i < s.size() else 0
	return result

# a - b mod m  (assumes 0 <= a, b < m)
static func submod(a: Array, b: Array, m: Array) -> Array:
	if cmp(a, b) >= 0:
		return sub(a, b)
	# a < b: result = m - (b - a)
	return sub(m, sub(b, a))

# (-a) mod m
static func negmod(a: Array, m: Array) -> Array:
	if is_zero(a):
		return zero(N)
	return sub(m, a)

# ─────────────────────────────────────────────────────────────────────────────
# Fast reduction modulo q = 2^255 - 19
#
# For a 512-bit product P (32 limbs of 16-bit):
#   P = P_lo + P_hi * 2^256
#   2^256 ≡ 38 mod q   (since 2^255 ≡ 19 mod q)
#   P ≡ P_lo + 38 * P_hi (mod q)
# Two passes are sufficient; one conditional subtract at the end.
# ─────────────────────────────────────────────────────────────────────────────

static func _reduce_once(p: Array) -> Array:
	# p has up to 32 limbs.  Split at limb 16 (bit 256).
	# result = p[0..15] + 38 * p[16..]
	var p_lo: Array = zero(N + 1)  # extra limb for overflow
	for i in range(N):
		p_lo[i] = p[i] if i < p.size() else 0

	# 38 * p_hi
	var carry: int = 0
	for i in range(N):
		var ph: int = p[N + i] if N + i < p.size() else 0
		var cur: int = p_lo[i] + ph * 38 + carry
		p_lo[i] = cur & MASK
		carry = cur >> 16
	p_lo[N] = carry
	return p_lo

# Full reduction mod q for a value up to 512 bits
static func mod_q(p: Array) -> Array:
	# Pass 1: fold high limbs: P_lo + 38 * P_hi  (2^256 ≡ 38 mod q)
	var r: Array = _reduce_once(p)
	# r[N] holds the overflow carry from pass 1 (≤ 39 in practice)
	var extra: int = r[N] if r.size() > N else 0
	# Pass 2: add extra * 38 into r[0..N-1] with carry propagation
	var s: Array = zero(N)
	for i in range(N):
		s[i] = r[i]
	var carry: int = extra * 38
	for i in range(N):
		var cur: int = s[i] + carry
		s[i] = cur & MASK
		carry = cur >> 16
		if carry == 0:
			break
	# If carry is still non-zero it represents carry * 2^256 ≡ carry * 38
	if carry > 0:
		carry *= 38
		for i in range(N):
			var cur: int = s[i] + carry
			s[i] = cur & MASK
			carry = cur >> 16
			if carry == 0:
				break
	# Conditional subtract to bring into [0, q)
	if cmp(s, Q) >= 0:
		s = sub(s, Q)
	return s

# Multiply mod q: compute a*b mod q efficiently
static func mulmod_q(a: Array, b: Array) -> Array:
	var p: Array = mul(a, b)   # 32 limbs
	return mod_q(p)

# Square mod q
static func sqmod_q(a: Array) -> Array:
	return mulmod_q(a, a)

# ─────────────────────────────────────────────────────────────────────────────
# Modular exponentiation
# ─────────────────────────────────────────────────────────────────────────────

# base^exp mod q  (exp is an N-limb BigInt)
static func powmod_q(base_in: Array, exp: Array) -> Array:
	var result: Array = one(N)
	var b: Array = mod_q(base_in)
	var e: Array = exp.duplicate()
	var n_bits: int = bit_length(e)
	for i in range(n_bits):
		if bit(e, i) == 1:
			result = mulmod_q(result, b)
		b = sqmod_q(b)
	return result

# General base^exp mod m  (used for scalar mod l)
static func powmod(base_in: Array, exp: Array, m: Array) -> Array:
	var result: Array = one(N)
	var b: Array = mod(base_in, m)
	var e: Array = exp.duplicate()
	var n_bits: int = bit_length(e)
	for i in range(n_bits):
		if bit(e, i) == 1:
			result = mod(mul(result, b), m)
		b = mod(mul(b, b), m)
	return result

# ─────────────────────────────────────────────────────────────────────────────
# Field inverse: z^-1 mod q
# Uses the same addition chain as the Python Ed25519 implementation:
#   z^(q-2) mod q  via Fermat's little theorem.
# ─────────────────────────────────────────────────────────────────────────────

# z^(2^p) mod q
static func _pow2_q(z: Array, p: int) -> Array:
	var x: Array = z
	for _i in range(p):
		x = sqmod_q(x)
	return x

static func inv_q(z: Array) -> Array:
	var z2: Array     = sqmod_q(z)
	var z9: Array     = mulmod_q(_pow2_q(z2, 2), z)
	var z11: Array    = mulmod_q(z9, z2)
	var z2_5_0: Array = mulmod_q(sqmod_q(z11), z9)
	var z2_10_0: Array = mulmod_q(_pow2_q(z2_5_0, 5),  z2_5_0)
	var z2_20_0: Array = mulmod_q(_pow2_q(z2_10_0, 10), z2_10_0)
	var z2_40_0: Array = mulmod_q(_pow2_q(z2_20_0, 20), z2_20_0)
	var z2_50_0: Array = mulmod_q(_pow2_q(z2_40_0, 10), z2_10_0)
	var z2_100_0: Array = mulmod_q(_pow2_q(z2_50_0, 50), z2_50_0)
	var z2_200_0: Array = mulmod_q(_pow2_q(z2_100_0, 100), z2_100_0)
	var z2_250_0: Array = mulmod_q(_pow2_q(z2_200_0, 50), z2_50_0)
	return mulmod_q(_pow2_q(z2_250_0, 5), z11)
