# algo_account.gd
# Algorand account derivation from a 25-word mnemonic.
# Ported from algo_account.py (MicroPython for Algorand).
#
# Depends on: sha512.gd, ed25519.gd, bigint.gd
# Requires: res://wordlist.txt  (BIP-39 word list, one word per line)

class_name AlgoAccount

var private_key: PackedByteArray   # 32-byte seed
var public_key: PackedByteArray    # 32-byte public key
var address: String                # Algorand base32 address (no checksum padding)

func _init(mnemonic: String) -> void:
	private_key = mnemonic_to_key(mnemonic)
	var ed := Ed25519.new()
	public_key = ed.publickey(private_key)
	address = public_key_to_address(public_key)

func _to_string() -> String:
	return "AlgoAccount(address=%s)" % address

# ── Mnemonic → 32-byte private key seed ──────────────────────────────────────
# Algorand's LSB-first 11-bit packing scheme (algosdk convention)

static func mnemonic_to_key(mnemonic: String) -> PackedByteArray:
	var words: PackedStringArray = mnemonic.strip_edges().split(" ", false)
	if words.size() != 25:
		push_error("AlgoAccount: expected 25 words, got %d" % words.size())
		return PackedByteArray()

	# Resolve word indices (first 24 words; 25th is checksum)
	var nums: Array = []
	for i in range(24):
		var idx: int = _word_index(words[i])
		if idx < 0:
			push_error("AlgoAccount: unknown mnemonic word: %s" % words[i])
			return PackedByteArray()
		nums.append(idx)

	# LSB-first 11-bit unpacking
	var buf: int = 0
	var num_bits: int = 0
	var result: PackedByteArray = PackedByteArray()
	for n in nums:
		buf |= n << num_bits
		num_bits += 11
		while num_bits >= 8:
			result.append(buf & 0xFF)
			buf >>= 8
			num_bits -= 8

	return result.slice(0, 32)

# Find the 0-based index of a word in wordlist.txt
static func _word_index(target: String) -> int:
	var paths: PackedStringArray = ["res://wordlist.txt", "user://wordlist.txt"]
	for path in paths:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var idx: int = 0
		while not f.eof_reached():
			var line: String = f.get_line().strip_edges()
			if line == target:
				f.close()
				return idx
			if line != "":
				idx += 1
		f.close()
		push_error("AlgoAccount: word not found in wordlist: %s" % target)
		return -1
	push_error("AlgoAccount: wordlist.txt not found at res:// or user://")
	return -1

# ── Public key → Algorand address ─────────────────────────────────────────────

static func public_key_to_address(pk_bytes: PackedByteArray) -> String:
	# checksum = last 4 bytes of SHA-512/256(pk_bytes)
	var checksum: PackedByteArray = SHA512.sha512_256(pk_bytes).slice(28, 32)
	return _b32encode(pk_bytes + checksum)

# Base32 encode (no padding, Algorand style)
static func _b32encode(data: PackedByteArray) -> String:
	const ALPHA: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
	var bits: int = 0
	var bit_count: int = 0
	var result: String = ""
	for byte in data:
		bits = (bits << 8) | byte
		bit_count += 8
		while bit_count >= 5:
			bit_count -= 5
			result += ALPHA[(bits >> bit_count) & 0x1F]
	if bit_count > 0:
		result += ALPHA[(bits << (5 - bit_count)) & 0x1F]
	return result

# ── Decode address back to 32-byte public key ─────────────────────────────────

static func address_to_pubkey(address: String) -> PackedByteArray:
	const ALPHA: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
	var bits: int = 0
	var bit_count: int = 0
	var result: PackedByteArray = PackedByteArray()
	for ch in address:
		var idx: int = ALPHA.find(ch)
		if idx < 0:
			push_error("AlgoAccount: invalid base32 character: %s" % ch)
			return PackedByteArray()
		bits = (bits << 5) | idx
		bit_count += 5
		if bit_count >= 8:
			bit_count -= 8
			result.append((bits >> bit_count) & 0xFF)
	return result.slice(0, 32)
