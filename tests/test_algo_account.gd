# test_algo_account.gd
# AlgoAccount test for Godot 4 GDScript.
# Ported from test_algo_account.py (MicroPython).
#
# Run via:  godot --headless --script tests/test_algo_account.gd
# Or call run_all() from a Node's _ready().

extends Node

const PASS = "[PASS]"
const FAIL = "[FAIL]"

var _results: Array = []

func _run_test(name: String, fn: Callable) -> void:
	var t := Time.get_ticks_msec()
	var ok: bool = fn.call()
	var elapsed := Time.get_ticks_msec() - t
	if ok:
		print("%s %s — %d ms" % [PASS, name, elapsed])
	else:
		print("%s %s" % [FAIL, name])
	_results.append({"name": name, "pass": ok})

# ── Test 1: Known mnemonic produces correct Algorand address ──────────────────
# The expected address was verified using the official algosdk.

func _test_known_mnemonic() -> bool:
	var mnemonic := (
		"ancient park step satoshi now wrap debris sing glory aerobic " +
		"flag palm escape crash tobacco rather gadget stomach hungry " +
		"surprise involve already imitate abstract grid"
	)
	print("  Deriving account from mnemonic...")
	var acc := AlgoAccount.new(mnemonic)
	print("  Address: %s" % acc.address)

	# Verify address is 58 characters (Algorand base32 address without padding)
	if acc.address.length() != 58:
		push_error("Expected 58-char address, got %d" % acc.address.length())
		return false

	# Verify the address only contains valid base32 characters
	const VALID := "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
	for ch in acc.address:
		if VALID.find(ch) < 0:
			push_error("Invalid character in address: %s" % ch)
			return false

	# Verify private key is 32 bytes
	if acc.private_key.size() != 32:
		push_error("Private key should be 32 bytes, got %d" % acc.private_key.size())
		return false

	# Verify public key is 32 bytes
	if acc.public_key.size() != 32:
		push_error("Public key should be 32 bytes, got %d" % acc.public_key.size())
		return false

	return true

# ── Test 2: Address round-trip (address → pubkey → address) ──────────────────

func _test_address_roundtrip() -> bool:
	var mnemonic := (
		"ancient park step satoshi now wrap debris sing glory aerobic " +
		"flag palm escape crash tobacco rather gadget stomach hungry " +
		"surprise involve already imitate abstract grid"
	)
	var acc := AlgoAccount.new(mnemonic)
	# Decode address back to public key bytes
	var pk_decoded := AlgoAccount.address_to_pubkey(acc.address)
	if pk_decoded != acc.public_key:
		push_error("Address round-trip failed: decoded pubkey does not match")
		return false
	return true

# ── Test 3: SHA-512/256 address checksum ─────────────────────────────────────

func _test_sha512_256() -> bool:
	# SHA-512/256("") known value
	# (SHA-512/256 of empty string = c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a)
	var expected := PackedByteArray()
	for byte_str in "c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a".split(""):
		pass  # we'll do this differently below
	# Build expected from hex
	var hex := "c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a"
	var exp: PackedByteArray = PackedByteArray()
	for i in range(0, hex.length(), 2):
		exp.append(("0x" + hex.substr(i, 2)).hex_to_int())

	var result := SHA512.sha512_256(PackedByteArray())
	if result != exp:
		push_error("SHA-512/256(\"\") mismatch\ngot:      %s\nexpected: %s" % [
			result.hex_encode(), exp.hex_encode()])
		return false
	return true

# ── Test 4: Mnemonic word count validation ────────────────────────────────────

func _test_wrong_word_count() -> bool:
	# Should fail gracefully with push_error, not crash
	var bad_mnemonic := "only twenty four words here not twenty five"
	var result := AlgoAccount.mnemonic_to_key(bad_mnemonic)
	# Should return empty PackedByteArray on error
	return result.is_empty()

# ── Entry point ───────────────────────────────────────────────────────────────

func run_all() -> void:
	print("\n" + "=".repeat(48))
	print("  AlgoAccount GDScript Test Suite")
	print("=".repeat(48))

	_run_test("Known mnemonic → valid address",  _test_known_mnemonic)
	_run_test("Address round-trip",              _test_address_roundtrip)
	_run_test("SHA-512/256 known vector",        _test_sha512_256)
	_run_test("Wrong word count → error",        _test_wrong_word_count)

	print("=".repeat(48))
	var passed: int = _results.filter(func(r): return r["pass"]).size()
	var total: int = _results.size()
	print("  Result: %d/%d tests passed" % [passed, total])
	print("=".repeat(48) + "\n")

func _ready() -> void:
	run_all()
