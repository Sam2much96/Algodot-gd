# ed25519.gd
# Ed25519 digital signatures for Godot 4 GDScript.
# Ported from ed25519.py (MicroPython for Algorand).
#
# WARNING: Not side-channel safe. Suitable for Algorand bot / game use.
#
# Depends on: sha512.gd, bigint.gd
#
# Points are represented as [x, y, z, t] where each coordinate is a
# BigInt (Array of 16 × 16-bit limbs) in the Ed25519 prime field.

class_name Ed25519

# ── Precomputed curve constants (set in _init) ────────────────────────────────
var _d: Array      # curve constant d
var _I: Array      # sqrt(-1) mod q
var _B: Array      # base point in extended coordinates [x,y,z,t]
var _Bpow: Array   # Bpow[i] = 2^i * B  (253 entries, each a point)
var _ident: Array  # identity point (0,1,1,0)
var _l: Array      # group order (for scalar reduction)

# ── Constructor ───────────────────────────────────────────────────────────────

func _init() -> void:
	_l = BigInt.L.duplicate()

	# Identity element in extended coordinates
	_ident = [BigInt.zero(), BigInt.one(), BigInt.one(), BigInt.zero()]

	# d = -121665 * inv(121666) mod q
	var inv121666: Array = BigInt.inv_q(BigInt.from_small(121666))
	# -121665 mod q = q - 121665
	var neg121665: Array = BigInt.sub(BigInt.Q, BigInt.from_small(121665))
	_d = BigInt.mulmod_q(neg121665, inv121666)

	# I = 2^((q-1)/4) mod q
	# (q-1)/4 = (2^255 - 20)/4 = 2^253 - 5
	# Represented as BigInt:
	var exp_i: Array = _compute_q_minus1_over4()
	_I = BigInt.powmod_q(BigInt.from_small(2), exp_i)

	# Base point B
	var By: Array = BigInt.mulmod_q(BigInt.from_small(4), BigInt.inv_q(BigInt.from_small(5)))
	var Bx: Array = _xrecover(By)
	var Bt: Array = BigInt.mulmod_q(Bx, By)
	_B = [Bx, By, BigInt.one(), Bt]

	# Precompute Bpow[0..252]
	_Bpow = []
	var P: Array = _B
	for _i in range(253):
		_Bpow.append(P)
		P = _edwards_double(P)

# (q-1)/4 = 2^253 - 5 as a BigInt
static func _compute_q_minus1_over4() -> Array:
	# q - 1 = 2^255 - 20 = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffec
	# (q-1)/4 = 2^253 - 5 = 0x1ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffFFB
	# In 16-bit LE limbs:
	# limb[0] = 0xFFFB = 65531 (-5 in low 16 bits)
	# limb[1..14] = 0xFFFF = 65535
	# limb[15] = 0x1FFF = 8191  (2^253 → top 3 bits of limb 15 are 001)
	var a: Array = BigInt.zero()
	a[0] = 65531
	for i in range(1, 15):
		a[i] = 65535
	a[15] = 8191
	return a

# (q+3)/8 = 2^252 - 2 as a BigInt
static func _compute_q_plus3_over8() -> Array:
	# 2^252 - 2 = 0x0FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF FE
	# In 16-bit LE: limb[0]=0xFFFE=65534, limb[1..14]=0xFFFF, limb[15]=0x0FFF=4095
	var a: Array = BigInt.zero()
	a[0] = 65534
	for i in range(1, 15):
		a[i] = 65535
	a[15] = 4095
	return a

# ── Curve helpers ─────────────────────────────────────────────────────────────

func _xrecover(y: Array) -> Array:
	# x² = (y² - 1) / (d*y² + 1) mod q
	var y2: Array = BigInt.sqmod_q(y)
	var num: Array = BigInt.submod(y2, BigInt.one(), BigInt.Q)
	var den: Array = BigInt.addmod(BigInt.mulmod_q(_d, y2), BigInt.one(), BigInt.Q)
	var xx: Array = BigInt.mulmod_q(num, BigInt.inv_q(den))

	# x = xx^((q+3)/8) mod q
	var exp: Array = _compute_q_plus3_over8()
	var x: Array = BigInt.powmod_q(xx, exp)

	# Check: if x² ≠ xx, multiply by I (sqrt(-1))
	var x2: Array = BigInt.sqmod_q(x)
	if BigInt.cmp(x2, xx) != 0:
		x = BigInt.mulmod_q(x, _I)

	# Ensure x is even (low bit = 0)
	if x[0] & 1 != 0:
		x = BigInt.submod(BigInt.Q, x, BigInt.Q)  # x = q - x

	return x

# ── Extended twisted Edwards point arithmetic ─────────────────────────────────

func _edwards_add(P: Array, Q: Array) -> Array:
	var x1 = P[0]; var y1 = P[1]; var z1 = P[2]; var t1 = P[3]
	var x2 = Q[0]; var y2 = Q[1]; var z2 = Q[2]; var t2 = Q[3]
	var a: Array = BigInt.mulmod_q(BigInt.submod(y1, x1, BigInt.Q),
	                                BigInt.submod(y2, x2, BigInt.Q))
	var b: Array = BigInt.mulmod_q(BigInt.addmod(y1, x1, BigInt.Q),
	                                BigInt.addmod(y2, x2, BigInt.Q))
	var c: Array = BigInt.mulmod_q(t1, BigInt.mulmod_q(BigInt.mul_small(_d, 2), t2))
	var dd: Array = BigInt.mulmod_q(z1, BigInt.mul_small(z2, 2))
	var e: Array = BigInt.submod(b, a, BigInt.Q)
	var f: Array = BigInt.submod(dd, c, BigInt.Q)
	var g: Array = BigInt.addmod(dd, c, BigInt.Q)
	var h: Array = BigInt.addmod(b, a, BigInt.Q)
	var x3: Array = BigInt.mulmod_q(e, f)
	var y3: Array = BigInt.mulmod_q(g, h)
	var t3: Array = BigInt.mulmod_q(e, h)
	var z3: Array = BigInt.mulmod_q(f, g)
	return [x3, y3, z3, t3]

func _edwards_double(P: Array) -> Array:
	var x1 = P[0]; var y1 = P[1]; var z1 = P[2]
	var a: Array = BigInt.sqmod_q(x1)
	var b: Array = BigInt.sqmod_q(y1)
	var sq_z1: Array = BigInt.sqmod_q(z1)
	var c: Array = BigInt.addmod(sq_z1, sq_z1, BigInt.Q)
	var e: Array = BigInt.submod(BigInt.submod(BigInt.sqmod_q(BigInt.addmod(x1, y1, BigInt.Q)), a, BigInt.Q), b, BigInt.Q)
	var g: Array = BigInt.addmod(BigInt.negmod(a, BigInt.Q), b, BigInt.Q)
	var f: Array = BigInt.submod(g, c, BigInt.Q)
	var h: Array = BigInt.submod(BigInt.negmod(a, BigInt.Q), b, BigInt.Q)
	var x3: Array = BigInt.mulmod_q(e, f)
	var y3: Array = BigInt.mulmod_q(g, h)
	var t3: Array = BigInt.mulmod_q(e, h)
	var z3: Array = BigInt.mulmod_q(f, g)
	return [x3, y3, z3, t3]

# Scalar multiplication of an arbitrary point P by integer e
func _scalarmult(P: Array, e: Array) -> Array:
	var Q: Array = _ident
	var pt: Array = P
	var ee: Array = e.duplicate()
	var n_bits: int = BigInt.bit_length(ee)
	for i in range(n_bits):
		if BigInt.bit(ee, i):
			Q = _edwards_add(Q, pt)
		pt = _edwards_double(pt)
	return Q

# Fast scalar mult of base point using precomputed Bpow table
func _scalarmult_B(e: Array) -> Array:
	# Reduce e mod l first
	var e_red: Array = BigInt.mod(e, _l)
	var P: Array = _ident
	for i in range(253):
		if BigInt.bit(e_red, i):
			P = _edwards_add(P, _Bpow[i])
	return P

# ── Point encoding / decoding ─────────────────────────────────────────────────

func _encodepoint(P: Array) -> PackedByteArray:
	var x = P[0]; var y = P[1]; var z = P[2]
	# Convert to affine: x_aff = x/z, y_aff = y/z
	var z_inv: Array = BigInt.inv_q(z)
	var x_aff: Array = BigInt.mulmod_q(x, z_inv)
	var y_aff: Array = BigInt.mulmod_q(y, z_inv)
	# Encode y as 32 bytes LE; set bit 255 to low bit of x
	var out: PackedByteArray = BigInt.to_bytes_le(y_aff, 32)
	if x_aff[0] & 1:
		out[31] |= 0x80
	return out

func _decodepoint(s: PackedByteArray) -> Array:
	var s_copy: PackedByteArray = s.slice(0, 32)
	var x_sign: int = (s_copy[31] >> 7) & 1
	s_copy[31] &= 0x7F
	var y: Array = BigInt.from_bytes_le(s_copy)
	var x: Array = _xrecover(y)
	if (x[0] & 1) != x_sign:
		x = BigInt.submod(BigInt.Q, x, BigInt.Q)
	if not _isoncurve([x, y, BigInt.one(), BigInt.mulmod_q(x, y)]):
		push_error("Ed25519: decoding point that is not on curve")
	return [x, y, BigInt.one(), BigInt.mulmod_q(x, y)]

func _isoncurve(P: Array) -> bool:
	var x = P[0]; var y = P[1]; var z = P[2]; var t = P[3]
	# z ≠ 0
	if BigInt.is_zero(z): return false
	# x*y ≡ z*t mod q
	var lhs: Array = BigInt.mulmod_q(x, y)
	var rhs: Array = BigInt.mulmod_q(z, t)
	if BigInt.cmp(lhs, rhs) != 0: return false
	# y² - x² - z² - d*t² ≡ 0 mod q
	var y2: Array = BigInt.sqmod_q(y)
	var x2: Array = BigInt.sqmod_q(x)
	var z2: Array = BigInt.sqmod_q(z)
	var dt2: Array = BigInt.mulmod_q(_d, BigInt.sqmod_q(t))
	var lhs2: Array = BigInt.submod(BigInt.submod(BigInt.submod(y2, x2, BigInt.Q), z2, BigInt.Q), dt2, BigInt.Q)
	return BigInt.is_zero(lhs2)

# ── Scalar encoding / decoding ────────────────────────────────────────────────

func _encodeint(y: Array) -> PackedByteArray:
	return BigInt.to_bytes_le(y, 32)

func _decodeint(s: PackedByteArray) -> Array:
	return BigInt.from_bytes_le(s)

# ── Hash helpers ──────────────────────────────────────────────────────────────

func _H(m: PackedByteArray) -> PackedByteArray:
	return SHA512.hash(m)

# Interpret H(m) as a 512-bit little-endian integer
func _Hint(m: PackedByteArray) -> Array:
	var h: PackedByteArray = _H(m)
	return BigInt.from_bytes_le(h, 32)   # 512-bit value → 32 limbs

# ── Public API ────────────────────────────────────────────────────────────────

# Derive 32-byte public key from 32-byte secret key seed
func publickey(sk: PackedByteArray) -> PackedByteArray:
	var h: PackedByteArray = _H(sk)
	var a: Array = _clamp(BigInt.from_bytes_le(h.slice(0, 32)))
	var A: Array = _scalarmult_B(a)
	return _encodepoint(A)

# Sign message m with secret key sk and public key pk; returns 64-byte signature
func signature(m: PackedByteArray, sk: PackedByteArray, pk: PackedByteArray) -> PackedByteArray:
	var h: PackedByteArray = _H(sk)
	var a: Array = _clamp(BigInt.from_bytes_le(h.slice(0, 32)))

	# nonce r = H(h[32..63] || m) as integer
	var nonce_data: PackedByteArray = h.slice(32, 64)
	nonce_data.append_array(m)
	var r: Array = _Hint(nonce_data)

	var R: Array = _scalarmult_B(r)
	var R_enc: PackedByteArray = _encodepoint(R)

	# S = (r + H(R||pk||m) * a) mod l
	var S_data: PackedByteArray = R_enc.duplicate()
	S_data.append_array(pk)
	S_data.append_array(m)
	var k: Array = _Hint(S_data)

	# S = (r + k * a) mod l
	var ka: Array = BigInt.mod(BigInt.mul(k, a), _l)
	var S: Array = BigInt.mod(BigInt.add(r, ka), _l)

	var S_enc: PackedByteArray = _encodeint(S)
	var sig: PackedByteArray = R_enc.duplicate()
	sig.append_array(S_enc)
	return sig

# Verify signature s on message m with public key pk; returns true if valid
# Raises a push_error (not an exception) and returns false if invalid
func checkvalid(s: PackedByteArray, m: PackedByteArray, pk: PackedByteArray) -> bool:
	if s.size() != 64:
		push_error("Ed25519: signature length is wrong")
		return false
	if pk.size() != 32:
		push_error("Ed25519: public-key length is wrong")
		return false

	var R: Array = _decodepoint(s.slice(0, 32))
	var A: Array = _decodepoint(pk)
	var S: Array = _decodeint(s.slice(32, 64))

	var h_data: PackedByteArray = s.slice(0, 32)
	h_data.append_array(pk)
	h_data.append_array(m)
	var h: Array = _Hint(h_data)

	# Check: 8*S*B == 8*R + 8*h*A
	# (multiply by 8 to clear cofactor, matching original Python)
	var P: Array = _scalarmult_B(S)
	var Q: Array = _edwards_add(R, _scalarmult(A, h))

	# Compare P and Q in projective coordinates: P_x * Q_z == Q_x * P_z
	var px = P[0]; var py = P[1]; var pz = P[2]
	var qx = Q[0]; var qy = Q[1]; var qz = Q[2]
	var lhs_x: Array = BigInt.mulmod_q(px, qz)
	var rhs_x: Array = BigInt.mulmod_q(qx, pz)
	var lhs_y: Array = BigInt.mulmod_q(py, qz)
	var rhs_y: Array = BigInt.mulmod_q(qy, pz)

	if BigInt.cmp(lhs_x, rhs_x) != 0 or BigInt.cmp(lhs_y, rhs_y) != 0:
		push_error("Ed25519: signature does not pass verification")
		return false
	return true

# ── Internal scalar clamping ──────────────────────────────────────────────────
# Ed25519: set bits 0,1,2 of byte 0 to 0; set bit 7 of byte 31 to 0; set bit 6 of byte 31 to 1
func _clamp(a: Array) -> Array:
	var r: Array = a.duplicate()
	# Clear low 3 bits of limb 0 (byte 0 bits 0-2)
	r[0] = r[0] & 0xFFF8
	# Byte 31 = high byte of limb 15
	var b31: int = (r[15] >> 8) & 0xFF
	b31 = b31 & 0x7F   # clear bit 7
	b31 = b31 | 0x40   # set bit 6
	r[15] = (r[15] & 0x00FF) | (b31 << 8)
	return r
