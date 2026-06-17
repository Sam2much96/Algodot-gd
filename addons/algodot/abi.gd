# abi.gd
# ARC-4 ABI encoder for Alpha Market on Godot 4 GDScript.
# Ported from abi.py (MicroPython for Algorand).
#
# Method selectors are the first 4 bytes of SHA-512/256(method_signature).
# Depends on: sha512.gd, algo_account.gd

class_name AlgoABI

# ── Hard-coded method selectors ───────────────────────────────────────────────
# market_app methods:
#   create_escrow(uint64,uint64,uint64,uint64)uint64  → 0x82d0106d
#   delete_escrow(uint64,address)void                 → 0x5525ce00
#   split_shares()void                               → 0xf4d43c47
#   merge_shares()void                               → 0x501e7c5c
#   claim()void                                      → 0xf1577726
# matcher_app methods:
#   propose_a_match(uint64,uint64,uint64,address,address,address,uint64)void → 0x63aa835d

static var SEL_CREATE_ESCROW:   PackedByteArray = PackedByteArray([0x82, 0xd0, 0x10, 0x6d])
static var SEL_DELETE_ESCROW:   PackedByteArray = PackedByteArray([0x55, 0x25, 0xce, 0x00])
static var SEL_SPLIT_SHARES:    PackedByteArray = PackedByteArray([0xf4, 0xd4, 0x3c, 0x47])
static var SEL_MERGE_SHARES:    PackedByteArray = PackedByteArray([0x50, 0x1e, 0x7c, 0x5c])
static var SEL_CLAIM:           PackedByteArray = PackedByteArray([0xf1, 0x57, 0x77, 0x26])
static var SEL_PROPOSE_A_MATCH: PackedByteArray = PackedByteArray([0x63, 0xaa, 0x83, 0x5d])

# ── ABI type encoders ─────────────────────────────────────────────────────────

static func uint64(n: int) -> PackedByteArray:
	return PackedByteArray([
		(n >> 56) & 0xFF, (n >> 48) & 0xFF,
		(n >> 40) & 0xFF, (n >> 32) & 0xFF,
		(n >> 24) & 0xFF, (n >> 16) & 0xFF,
		(n >> 8)  & 0xFF,  n & 0xFF,
	])

static func address_arg(pk_bytes: PackedByteArray) -> PackedByteArray:
	if pk_bytes.size() != 32:
		push_error("AlgoABI: address must be 32 bytes, got %d" % pk_bytes.size())
	return pk_bytes

# ── ABI call builders ─────────────────────────────────────────────────────────

static func call_create_escrow(price: int, quantity: int,
		slippage: int, position: int) -> PackedByteArray:
	var r: PackedByteArray = SEL_CREATE_ESCROW.duplicate()
	r.append_array(uint64(price))
	r.append_array(uint64(quantity))
	r.append_array(uint64(slippage))
	r.append_array(uint64(position))
	return r

static func call_delete_escrow(escrow_app_id: int,
		algo_receiver_pk: PackedByteArray) -> PackedByteArray:
	var r: PackedByteArray = SEL_DELETE_ESCROW.duplicate()
	r.append_array(uint64(escrow_app_id))
	r.append_array(address_arg(algo_receiver_pk))
	return r

static func call_split_shares() -> PackedByteArray:
	return SEL_SPLIT_SHARES.duplicate()

static func call_merge_shares() -> PackedByteArray:
	return SEL_MERGE_SHARES.duplicate()

static func call_claim() -> PackedByteArray:
	return SEL_CLAIM.duplicate()

static func call_propose_a_match(market_app_id: int, maker_escrow_app_id: int,
		quantity_matched: int, taker_pk: PackedByteArray,
		maker_pk: PackedByteArray, fee_pk: PackedByteArray,
		taker_app_created_index_offset: int) -> PackedByteArray:
	var r: PackedByteArray = SEL_PROPOSE_A_MATCH.duplicate()
	r.append_array(uint64(market_app_id))
	r.append_array(uint64(maker_escrow_app_id))
	r.append_array(uint64(quantity_matched))
	r.append_array(address_arg(taker_pk))
	r.append_array(address_arg(maker_pk))
	r.append_array(address_arg(fee_pk))
	r.append_array(uint64(taker_app_created_index_offset))
	return r

# ── Fee calculation ───────────────────────────────────────────────────────────
# fee = floor(quantity * price / 1_000_000 * fee_base / 1_000_000)

static func calculate_fee(quantity: int, price: int, fee_base: int) -> int:
	return int(quantity * price / 1_000_000 * fee_base / 1_000_000)

# ── App address derivation ────────────────────────────────────────────────────
# getApplicationAddress(appId) = SHA-512/256("appID" || uint64_be(appId))

static func app_address(app_id: int) -> PackedByteArray:
	var data: PackedByteArray = "appID".to_utf8_buffer()
	data.append_array(uint64(app_id))
	return SHA512.sha512_256(data)

static func app_address_str(app_id: int) -> String:
	return AlgoAccount.public_key_to_address(app_address(app_id))
