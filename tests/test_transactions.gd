# test_transactions.gd
# Transaction builder tests for Godot 4 GDScript.
# Ported from test_transactions.py (MicroPython).
#
# Run via:  godot --headless --script tests/test_transactions.gd
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

# Shared dummy params matching test_transactions.py
func _dummy_params() -> Dictionary:
	var gh := PackedByteArray(); gh.resize(32)
	return {
		"fee":     1000,
		"min_fee": 1000,
		"fv":      1,
		"lv":      1001,
		"gen":     "mainnet-v1.0",
		"gh":      gh,
	}

# ── Test 1: Build a payment transaction ───────────────────────────────────────

func _test_make_payment() -> bool:
	var params := _dummy_params()
	var sender_pk: PackedByteArray = PackedByteArray(); sender_pk.resize(32)
	var tx := AlgoTx.make_payment(
		sender_pk,
		"HLJFMLLHQVALDRNXS2PVGUYTQWRSTFIX6BQ2D2T5EEO4TSOCEHCSWH3TRSE",
		957_000, params)

	if tx.get("type") != "pay":
		push_error("Expected type=pay, got %s" % tx.get("type"))
		return false
	if tx.get("amt") != 957_000:
		push_error("Expected amt=957000, got %d" % tx.get("amt"))
		return false
	if tx.get("fee") != 1000:
		push_error("Expected fee=1000, got %d" % tx.get("fee"))
		return false
	if tx.get("rcv", PackedByteArray()).size() != 32:
		push_error("Expected rcv to be 32 bytes")
		return false
	return true

# ── Test 2: Build an asset opt-in ────────────────────────────────────────────

func _test_make_asset_optin() -> bool:
	var params := _dummy_params()
	var sender_pk: PackedByteArray = PackedByteArray(); sender_pk.resize(32)
	var tx := AlgoTx.make_asset_optin(sender_pk, 31566704, params)

	if tx.get("type") != "axfer":
		push_error("Expected type=axfer")
		return false
	if tx.get("xaid") != 31566704:
		push_error("Expected xaid=31566704")
		return false
	if tx.get("aamt") != 0:
		push_error("Opt-in amount should be 0")
		return false
	return true

# ── Test 3: Build an asset transfer ──────────────────────────────────────────

func _test_make_asset_transfer() -> bool:
	var params := _dummy_params()
	var sender_pk: PackedByteArray = PackedByteArray(); sender_pk.resize(32)
	var tx := AlgoTx.make_asset_transfer(
		sender_pk,
		"HLJFMLLHQVALDRNXS2PVGUYTQWRSTFIX6BQ2D2T5EEO4TSOCEHCSWH3TRSE",
		31566704, 1_000_000, params)

	if tx.get("type") != "axfer":
		push_error("Expected type=axfer")
		return false
	if tx.get("aamt") != 1_000_000:
		push_error("Expected aamt=1000000")
		return false
	return true

# ── Test 4: Build an app call ─────────────────────────────────────────────────

func _test_make_app_call() -> bool:
	var params := _dummy_params()
	var sender_pk: PackedByteArray = PackedByteArray(); sender_pk.resize(32)
	var tx := AlgoTx.make_app_call(sender_pk, 123456, params,
		[PackedByteArray([0x01, 0x02])], [], [], [], 0)

	if tx.get("type") != "appl":
		push_error("Expected type=appl")
		return false
	if tx.get("apid") != 123456:
		push_error("Expected apid=123456")
		return false
	return true

# ── Test 5: MsgPack round-trip ────────────────────────────────────────────────

func _test_msgpack_payment() -> bool:
	var params := _dummy_params()
	var sender_pk: PackedByteArray = PackedByteArray(); sender_pk.resize(32)
	var tx := AlgoTx.make_payment(sender_pk,
		"HLJFMLLHQVALDRNXS2PVGUYTQWRSTFIX6BQ2D2T5EEO4TSOCEHCSWH3TRSE",
		957_000, params)

	var encoded: PackedByteArray = MsgPack.pack(tx)
	if encoded.size() == 0:
		push_error("MsgPack encoding of payment returned empty bytes")
		return false

	# "TX" prefix + encoded must be non-empty
	var tx_bytes: PackedByteArray = "TX".to_utf8_buffer()
	tx_bytes.append_array(encoded)
	if tx_bytes.size() < 5:
		push_error("TX-prefixed bytes too short")
		return false
	return true

# ── Test 6: Group ID assignment ───────────────────────────────────────────────

func _test_assign_group_id() -> bool:
	var params := _dummy_params()
	var sender_pk: PackedByteArray = PackedByteArray(); sender_pk.resize(32)
	var tx1 := AlgoTx.make_payment(sender_pk,
		"HLJFMLLHQVALDRNXS2PVGUYTQWRSTFIX6BQ2D2T5EEO4TSOCEHCSWH3TRSE",
		1000, params)
	var tx2 := AlgoTx.make_payment(sender_pk,
		"HLJFMLLHQVALDRNXS2PVGUYTQWRSTFIX6BQ2D2T5EEO4TSOCEHCSWH3TRSE",
		2000, params)

	var group_id := AlgoTx.assign_group_id([tx1, tx2])

	if group_id.size() != 32:
		push_error("Group ID should be 32 bytes, got %d" % group_id.size())
		return false
	if not tx1.has("grp") or tx1["grp"].size() != 32:
		push_error("tx1 should have a 32-byte grp field")
		return false
	if tx1["grp"] != tx2["grp"]:
		push_error("Both txns in group should have the same group ID")
		return false
	return true

# ── Test 7: ABI uint64 encoding ───────────────────────────────────────────────

func _test_abi_uint64() -> bool:
	var enc := AlgoABI.uint64(0x0102030405060708)
	var expected := PackedByteArray([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
	if enc != expected:
		push_error("uint64 encoding wrong: %s" % enc.hex_encode())
		return false
	return true

# ── Test 8: App address ───────────────────────────────────────────────────────

func _test_app_address() -> bool:
	var pk := AlgoABI.app_address(1)
	if pk.size() != 32:
		push_error("app_address should return 32 bytes")
		return false
	var addr := AlgoABI.app_address_str(1)
	if addr.length() != 58:
		push_error("app_address_str should return 58-char string")
		return false
	return true

# ── Entry point ───────────────────────────────────────────────────────────────

func run_all() -> void:
	print("\n" + "=".repeat(48))
	print("  Algorand Transaction GDScript Test Suite")
	print("=".repeat(48))

	_run_test("make_payment",        _test_make_payment)
	_run_test("make_asset_optin",    _test_make_asset_optin)
	_run_test("make_asset_transfer", _test_make_asset_transfer)
	_run_test("make_app_call",       _test_make_app_call)
	_run_test("MsgPack payment",     _test_msgpack_payment)
	_run_test("Group ID assignment", _test_assign_group_id)
	_run_test("ABI uint64 encoding", _test_abi_uint64)
	_run_test("App address",         _test_app_address)

	print("=".repeat(48))
	var passed: int = _results.filter(func(r): return r["pass"]).size()
	var total: int = _results.size()
	print("  Result: %d/%d tests passed" % [passed, total])
	print("=".repeat(48) + "\n")

func _ready() -> void:
	run_all()
