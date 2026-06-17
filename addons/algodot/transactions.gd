# transactions.gd
# Algorand transaction builder for Godot 4 GDScript.
# Ported from transactions.py (MicroPython for Algorand).
#
# Supports: pay, axfer (opt-in / transfer / close), appl, atomic groups.
# Depends on: sha512.gd, msgpack.gd, ed25519.gd, algo_account.gd

class_name AlgoTx

# ── Address helpers ───────────────────────────────────────────────────────────

static func address_to_pubkey(address: String) -> PackedByteArray:
	return AlgoAccount.address_to_pubkey(address)

# ── Transaction parameter fetch (HTTP, async) ─────────────────────────────────
# In Godot use HTTPRequest node for actual network calls.
# This static helper builds the params dict from an already-fetched JSON dict.

static func params_from_json(data: Dictionary) -> Dictionary:
	var gh_b64: String = data.get("genesis-hash", "")
	var gh: PackedByteArray = Marshalls.base64_to_raw(gh_b64) if gh_b64 != "" else PackedByteArray()
	gh.resize(32)  # ensure exactly 32 bytes
	return {
		"fee":     data.get("fee", 1000),
		"min_fee": data.get("min-fee", 1000),
		"fv":      data.get("last-round", 0),
		"lv":      data.get("last-round", 0) + 1000,
		"gen":     data.get("genesis-id", ""),
		"gh":      gh,
	}

static func _base_fee(params: Dictionary, fee_override = null) -> int:
	if fee_override != null:
		return fee_override
	return maxi(params.get("min_fee", 1000), params.get("fee", 1000))

# ── Transaction builders ──────────────────────────────────────────────────────

static func make_payment(sender_pk: PackedByteArray, receiver_address: String,
		amount_microalgo: int, params: Dictionary,
		note = null, fee_override = null) -> Dictionary:
	var tx: Dictionary = {
		"amt":  amount_microalgo,
		"fee":  _base_fee(params, fee_override),
		"fv":   params["fv"],
		"gen":  params["gen"],
		"gh":   params["gh"],
		"lv":   params["lv"],
		"rcv":  address_to_pubkey(receiver_address),
		"snd":  sender_pk,
		"type": "pay",
	}
	if note != null:
		tx["note"] = note if note is PackedByteArray else note.to_utf8_buffer()
	return tx

static func make_asset_optin(sender_pk: PackedByteArray,
		asset_id: int, params: Dictionary) -> Dictionary:
	return {
		"aamt": 0,
		"arcv": sender_pk,
		"fee":  _base_fee(params),
		"fv":   params["fv"],
		"gen":  params["gen"],
		"gh":   params["gh"],
		"lv":   params["lv"],
		"snd":  sender_pk,
		"type": "axfer",
		"xaid": asset_id,
	}

static func make_asset_transfer(sender_pk: PackedByteArray, receiver_address: String,
		asset_id: int, amount: int, params: Dictionary,
		note = null, fee_override = null, close_remainder_to: String = "") -> Dictionary:
	var tx: Dictionary = {
		"aamt": amount,
		"arcv": address_to_pubkey(receiver_address),
		"fee":  _base_fee(params, fee_override),
		"fv":   params["fv"],
		"gen":  params["gen"],
		"gh":   params["gh"],
		"lv":   params["lv"],
		"snd":  sender_pk,
		"type": "axfer",
		"xaid": asset_id,
	}
	if close_remainder_to != "":
		tx["aclose"] = address_to_pubkey(close_remainder_to)
	if note != null:
		tx["note"] = note if note is PackedByteArray else note.to_utf8_buffer()
	return tx

static func make_app_call(sender_pk: PackedByteArray, app_id: int,
		params: Dictionary, app_args: Array = [], accounts: Array = [],
		foreign_apps: Array = [], foreign_assets: Array = [],
		on_complete: int = 0, note = null, fee_override = null) -> Dictionary:
	var tx: Dictionary = {
		"apid": app_id,
		"fee":  _base_fee(params, fee_override),
		"fv":   params["fv"],
		"gen":  params["gen"],
		"gh":   params["gh"],
		"lv":   params["lv"],
		"snd":  sender_pk,
		"type": "appl",
	}
	if on_complete != 0:
		tx["apan"] = on_complete
	if not app_args.is_empty():
		var packed_args: Array = []
		for a in app_args:
			packed_args.append(a if a is PackedByteArray else PackedByteArray(a))
		tx["apaa"] = packed_args
	if not accounts.is_empty():
		tx["apat"] = accounts.map(func(a): return address_to_pubkey(a))
	if not foreign_apps.is_empty():
		tx["apfa"] = foreign_apps.duplicate()
	if not foreign_assets.is_empty():
		tx["apas"] = foreign_assets.duplicate()
	if note != null:
		tx["note"] = note if note is PackedByteArray else note.to_utf8_buffer()
	return tx

# ── Atomic group ──────────────────────────────────────────────────────────────

static func assign_group_id(tx_list: Array) -> PackedByteArray:
	if tx_list.size() > 16:
		push_error("AlgoTx: max 16 transactions per group")
		return PackedByteArray()

	# Encode each transaction with "TX" prefix
	var encoded: Array = []
	for tx in tx_list:
		var enc: PackedByteArray = "TX".to_utf8_buffer()
		enc.append_array(MsgPack.pack(tx))
		encoded.append(enc)

	# Build a msgpack array of bin-encoded transactions
	var n: int = encoded.size()
	var arr: PackedByteArray
	if n <= 15:
		arr = PackedByteArray([0x90 | n])
	else:
		arr = PackedByteArray([0xdc, (n >> 8) & 0xFF, n & 0xFF])
	for tb in encoded:
		arr.append_array(MsgPack._pack_bytes(tb))

	var tg_data: PackedByteArray = "TG".to_utf8_buffer()
	tg_data.append_array(arr)
	var group_id: PackedByteArray = SHA512.sha512_256(tg_data)

	for tx in tx_list:
		tx["grp"] = group_id
	return group_id

# ── Signing ───────────────────────────────────────────────────────────────────

static func sign_tx(tx_fields: Dictionary,
		private_key: PackedByteArray, public_key: PackedByteArray) -> PackedByteArray:
	var tx_bytes: PackedByteArray = "TX".to_utf8_buffer()
	tx_bytes.append_array(MsgPack.pack(tx_fields))
	var ed := Ed25519.new()
	var sig: PackedByteArray = ed.signature(tx_bytes, private_key, public_key)
	return MsgPack.pack({"sig": sig, "txn": tx_fields})

static func sign_group(tx_list: Array,
		private_key: PackedByteArray, public_key: PackedByteArray) -> Array:
	var signed: Array = []
	var ed := Ed25519.new()
	for i in range(tx_list.size()):
		print("  Signing %d/%d..." % [i + 1, tx_list.size()])
		var tx_bytes: PackedByteArray = "TX".to_utf8_buffer()
		tx_bytes.append_array(MsgPack.pack(tx_list[i]))
		var sig: PackedByteArray = ed.signature(tx_bytes, private_key, public_key)
		signed.append(MsgPack.pack({"sig": sig, "txn": tx_list[i]}))
	return signed

# ── Submit / confirm (use HTTPRequest node; helpers below build the request) ──

# Build the raw bytes to POST to /v2/transactions
static func build_submit_body(signed_list) -> PackedByteArray:
	if signed_list is PackedByteArray:
		return signed_list
	var body: PackedByteArray = PackedByteArray()
	for s in signed_list:
		body.append_array(s)
	return body

# Algorand node URL helpers
static func algod_url(network: String = "mainnet") -> String:
	return "https://%s-api.algonode.cloud/v2" % network

static func params_url(network: String = "mainnet") -> String:
	return algod_url(network) + "/transactions/params"

static func submit_url(network: String = "mainnet") -> String:
	return algod_url(network) + "/transactions"

static func pending_url(txid: String, network: String = "mainnet") -> String:
	return algod_url(network) + "/transactions/pending/" + txid
