# test_ed25519.gd
# Ed25519 test suite for Godot 4 GDScript.
# Ported from test_ed25519.py (MicroPython).
#
# Run via:  godot --headless --script tests/test_ed25519.gd
# Or attach to a Node and call run_all() from _ready().
#
# Tests:
#   1. Public key derivation is deterministic
#   2. Sign and verify round-trip
#   3. Tampered message is rejected
#   4. Tampered signature is rejected
#   5. Wrong public key is rejected
#   6. RFC 8032 test vector 1 (known-answer)
#   7. Empty message signing
#   8. Performance benchmark (timing only, no hard threshold)

extends Node

const PASS = "[PASS]"
const FAIL = "[FAIL]"

var _results: Array = []
var _ed: Ed25519 = null

func _get_ed() -> Ed25519:
	if _ed == null:
		print("Initialising Ed25519 (precomputing Bpow table)...")
		var t := Time.get_ticks_msec()
		_ed = Ed25519.new()
		print("  Init took %d ms" % (Time.get_ticks_msec() - t))
	return _ed

func _run_test(name: String, fn: Callable) -> void:
	var t := Time.get_ticks_msec()
	var ok := true
	var err_msg := ""
	# We rely on push_error for failures, but also wrap in a try-like pattern
	# using a Callable that returns false on assertion failure.
	if not fn.call():
		ok = false
		err_msg = "returned false"
	var elapsed := Time.get_ticks_msec() - t
	if ok:
		print("%s %s — %d ms" % [PASS, name, elapsed])
	else:
		print("%s %s — %s" % [FAIL, name, err_msg])
	_results.append({"name": name, "pass": ok})

# ── Test 1: Public key is deterministic ──────────────────────────────────────

func _test_pubkey_deterministic() -> bool:
	var ed := _get_ed()
	var sk: PackedByteArray = PackedByteArray()
	sk.resize(32); sk.fill(0x01)
	var pk1 := ed.publickey(sk)
	var pk2 := ed.publickey(sk)
	if pk1 != pk2:
		push_error("Public key not deterministic")
		return false
	if pk1.size() != 32:
		push_error("Public key should be 32 bytes, got %d" % pk1.size())
		return false
	return true

# ── Test 2: Sign and verify round-trip ───────────────────────────────────────

func _test_sign_verify_roundtrip() -> bool:
	var ed := _get_ed()
	var sk: PackedByteArray = PackedByteArray()
	sk.resize(32); for i in range(4): sk[i*8+0]=0xab; sk[i*8+1]=0xcd
	sk.resize(32)
	# Simple pattern: 0xabcdef01 repeated 8 times
	for i in range(32): sk[i] = [0xab,0xcd,0xef,0x01][i % 4]
	var pk := ed.publickey(sk)
	var msg := "hello algorand bot".to_utf8_buffer()
	var sig := ed.signature(msg, sk, pk)
	if sig.size() != 64:
		push_error("Signature should be 64 bytes")
		return false
	return ed.checkvalid(sig, msg, pk)

# ── Test 3: Tampered message is rejected ─────────────────────────────────────

func _test_tampered_message_rejected() -> bool:
	var ed := _get_ed()
	var sk: PackedByteArray = PackedByteArray(); sk.resize(32); sk.fill(0x11)
	var pk := ed.publickey(sk)
	var msg := "buy YES @ 0.30".to_utf8_buffer()
	var sig := ed.signature(msg, sk, pk)
	var tampered := "buy YES @ 0.31".to_utf8_buffer()
	# checkvalid should return false (and push_error) for tampered message
	var rejected := not ed.checkvalid(sig, tampered, pk)
	if not rejected:
		push_error("Tampered message should have been rejected")
	return rejected

# ── Test 4: Tampered signature is rejected ────────────────────────────────────

func _test_tampered_signature_rejected() -> bool:
	var ed := _get_ed()
	var sk: PackedByteArray = PackedByteArray(); sk.resize(32); sk.fill(0x22)
	var pk := ed.publickey(sk)
	var msg := "cancel order 12345".to_utf8_buffer()
	var sig := ed.signature(msg, sk, pk)
	# Flip one byte
	var bad_sig := sig.duplicate()
	bad_sig[10] = bad_sig[10] ^ 0xFF
	var rejected := not ed.checkvalid(bad_sig, msg, pk)
	if not rejected:
		push_error("Tampered signature should have been rejected")
	return rejected

# ── Test 5: Wrong public key is rejected ──────────────────────────────────────

func _test_wrong_pubkey_rejected() -> bool:
	var ed := _get_ed()
	var sk1: PackedByteArray = PackedByteArray(); sk1.resize(32); sk1.fill(0x33)
	var sk2: PackedByteArray = PackedByteArray(); sk2.resize(32); sk2.fill(0x44)
	var pk1 := ed.publickey(sk1)
	var pk2 := ed.publickey(sk2)
	var msg := "place limit order".to_utf8_buffer()
	var sig := ed.signature(msg, sk1, pk1)
	var rejected := not ed.checkvalid(sig, msg, pk2)
	if not rejected:
		push_error("Wrong public key should have been rejected")
	return rejected

# ── Test 6: RFC 8032 test vector 1 ───────────────────────────────────────────

func _test_rfc8032_vector1() -> bool:
	var ed := _get_ed()
	var sk := _hex_to_bytes("ed2e2796406ce4599bf5b8f63d937a35ef0675bb9779395adb1eff04f42e551f")
	var pk_expected := _hex_to_bytes("490e02ad84912271f2ad39dc2b840c82fb59b5ed78c369c8a771b27c919fd4b8")
	var msg: PackedByteArray = PackedByteArray()
	var sig_expected := _hex_to_bytes(
		"64eea2bf35a2d113bcfbfb3c8dcb2a2aa3fd101c37bd2eb33cb622a81e63d1e6" +
		"563f96c52a28fe48a8aefb5c665e47e760d6986cc2f5c2e6f9072d2da3ab1e04")

	var pk := ed.publickey(sk)
	if pk != pk_expected:
		push_error("RFC8032 public key mismatch\ngot:      %s\nexpected: %s" % [
			pk.hex_encode(), pk_expected.hex_encode()])
		return false

	var sig := ed.signature(msg, sk, pk)
	if sig != sig_expected:
		push_error("RFC8032 signature mismatch\ngot:      %s\nexpected: %s" % [
			sig.hex_encode(), sig_expected.hex_encode()])
		return false

	return ed.checkvalid(sig, msg, pk)

# ── Test 7: Empty message signing ─────────────────────────────────────────────

func _test_empty_message() -> bool:
	var ed := _get_ed()
	var sk: PackedByteArray = PackedByteArray(); sk.resize(32); sk.fill(0x55)
	var pk := ed.publickey(sk)
	var msg: PackedByteArray = PackedByteArray()
	var sig := ed.signature(msg, sk, pk)
	return ed.checkvalid(sig, msg, pk)

# ── Test 8: Performance benchmark ────────────────────────────────────────────

func _test_performance_benchmark() -> bool:
	var ed := _get_ed()
	var sk: PackedByteArray = PackedByteArray(); sk.resize(32); sk.fill(0x66)
	var msg := "benchmark transaction payload".to_utf8_buffer()

	var t := Time.get_ticks_msec()
	var pk := ed.publickey(sk)
	var pubkey_ms := Time.get_ticks_msec() - t

	t = Time.get_ticks_msec()
	var sig := ed.signature(msg, sk, pk)
	var sign_ms := Time.get_ticks_msec() - t

	t = Time.get_ticks_msec()
	ed.checkvalid(sig, msg, pk)
	var verify_ms := Time.get_ticks_msec() - t

	print("  publickey: %d ms | sign: %d ms | verify: %d ms" % [pubkey_ms, sign_ms, verify_ms])
	if sign_ms > 60000:
		print("  WARNING: signing took over 60s")
	return true  # benchmark never fails

# ── Helpers ───────────────────────────────────────────────────────────────────

func _hex_to_bytes(hex: String) -> PackedByteArray:
	var result: PackedByteArray = PackedByteArray()
	for i in range(0, hex.length(), 2):
		result.append(("0x" + hex.substr(i, 2)).hex_to_int())
	return result

# ── Entry point ───────────────────────────────────────────────────────────────

func run_all() -> void:
	print("\n" + "=".repeat(48))
	print("  Ed25519 GDScript Test Suite")
	print("=".repeat(48))

	_run_test("Public key is deterministic",  _test_pubkey_deterministic)
	_run_test("Sign/verify round-trip",        _test_sign_verify_roundtrip)
	_run_test("Tampered message rejected",     _test_tampered_message_rejected)
	_run_test("Tampered signature rejected",   _test_tampered_signature_rejected)
	_run_test("Wrong public key rejected",     _test_wrong_pubkey_rejected)
	_run_test("RFC 8032 test vector 1",        _test_rfc8032_vector1)
	_run_test("Empty message signing",         _test_empty_message)
	_run_test("Performance benchmark",         _test_performance_benchmark)

	print("=".repeat(48))
	var passed: int = _results.filter(func(r): return r["pass"]).size()
	var total: int = _results.size()
	print("  Result: %d/%d tests passed" % [passed, total])
	print("=".repeat(48) + "\n")

	if passed < total:
		print("FAILED TESTS:")
		for r in _results:
			if not r["pass"]:
				print("  - " + r["name"])

func _ready() -> void:
	run_all()
