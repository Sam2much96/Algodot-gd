# Algodot

Algorand SDK for Godot 4 GDScript. Lets you create accounts, build and sign transactions, and interact with the Algorand blockchain entirely in GDScript — no native plugins or external HTTP libraries required.

Ported from a MicroPython Algorand implementation.

---

## Installation

1. Copy the `addons/algodot/` folder into your Godot project.
2. Copy `wordlist.txt` into your project root (required by `AlgoAccount`).
3. Open **Project → Project Settings → Plugins** and enable **Algodot**.

All classes (`AlgoAccount`, `AlgoTx`, `AlgoABI`, `Ed25519`, `SHA512`, `MsgPack`) are registered globally via `class_name` and are available everywhere in your project without any `preload`.

---

## Classes

### `AlgoAccount`

Derives an Algorand keypair and address from a 25-word mnemonic.

```gdscript
var acc := AlgoAccount.new("word1 word2 ... word25")
print(acc.address)      # XHNOEHX54EF...
print(acc.public_key)   # PackedByteArray (32 bytes)
print(acc.private_key)  # PackedByteArray (32 bytes, the seed)
```

**Properties**

| Property | Type | Description |
|---|---|---|
| `private_key` | `PackedByteArray` | 32-byte Ed25519 seed |
| `public_key` | `PackedByteArray` | 32-byte Ed25519 public key |
| `address` | `String` | Base32 Algorand address (58 characters, no padding) |

**Static methods**

```gdscript
# Convert a 25-word mnemonic to a 32-byte private key seed.
AlgoAccount.mnemonic_to_key(mnemonic: String) -> PackedByteArray

# Encode a 32-byte public key as an Algorand address string.
AlgoAccount.public_key_to_address(pk_bytes: PackedByteArray) -> String

# Decode an Algorand address string back to a 32-byte public key.
AlgoAccount.address_to_pubkey(address: String) -> PackedByteArray
```

`wordlist.txt` must be present at `res://wordlist.txt` or `user://wordlist.txt`. It is the standard BIP-39 English word list (2048 words, one per line). Algorand mnemonics use a 25-word variant of this scheme with an LSB-first 11-bit packing convention.

---

### `AlgoTx`

Builds, groups, and signs Algorand transactions. All methods are static — no instance needed.

#### Fetch transaction parameters

The network returns a JSON object from `/v2/transactions/params`. Pass it to `params_from_json` to get a params dict that all the builders below expect.

```gdscript
# Parse the JSON dict returned by GET /v2/transactions/params
AlgoTx.params_from_json(data: Dictionary) -> Dictionary
# Returns: { "fee", "min_fee", "fv", "lv", "gen", "gh" }
```

#### Build transactions

```gdscript
# ALGO payment
AlgoTx.make_payment(
    sender_pk: PackedByteArray,     # 32-byte public key of sender
    receiver_address: String,       # Algorand address of receiver
    amount_microalgo: int,          # amount in microALGO (1 ALGO = 1_000_000)
    params: Dictionary,             # from params_from_json()
    note = null,                    # optional String or PackedByteArray
    fee_override = null             # optional int to override fee
) -> Dictionary

# ASA opt-in (sends 0 of the asset to yourself)
AlgoTx.make_asset_optin(
    sender_pk: PackedByteArray,
    asset_id: int,
    params: Dictionary
) -> Dictionary

# ASA transfer
AlgoTx.make_asset_transfer(
    sender_pk: PackedByteArray,
    receiver_address: String,
    asset_id: int,
    amount: int,
    params: Dictionary,
    note = null,
    fee_override = null,
    close_remainder_to: String = ""  # optional close-out address
) -> Dictionary

# Application call (NoOp by default; set on_complete for other operations)
AlgoTx.make_app_call(
    sender_pk: PackedByteArray,
    app_id: int,
    params: Dictionary,
    app_args: Array = [],            # Array of PackedByteArray
    accounts: Array = [],            # Array of address Strings
    foreign_apps: Array = [],        # Array of int app IDs
    foreign_assets: Array = [],      # Array of int asset IDs
    on_complete: int = 0,            # 0=NoOp 1=OptIn 2=CloseOut 3=ClearState 4=UpdateApp 5=DeleteApp
    note = null,
    fee_override = null
) -> Dictionary
```

#### Atomic groups

```gdscript
# Assign the same group ID to all transactions in the list (mutates them in place).
# Returns the 32-byte group ID. Maximum 16 transactions per group.
AlgoTx.assign_group_id(tx_list: Array) -> PackedByteArray
```

#### Signing

```gdscript
# Sign a single transaction. Returns a msgpack-encoded signed transaction blob.
AlgoTx.sign_tx(
    tx_fields: Dictionary,
    private_key: PackedByteArray,   # 32-byte seed
    public_key: PackedByteArray     # 32-byte public key
) -> PackedByteArray

# Sign all transactions in a group. Returns an Array of PackedByteArray blobs.
AlgoTx.sign_group(
    tx_list: Array,
    private_key: PackedByteArray,
    public_key: PackedByteArray
) -> Array
```

#### Submitting (use with HTTPRequest node)

```gdscript
# Concatenate signed blobs into the raw body for POST /v2/transactions
AlgoTx.build_submit_body(signed_list) -> PackedByteArray

# URL helpers
AlgoTx.algod_url(network: String = "mainnet") -> String
AlgoTx.params_url(network: String = "mainnet") -> String   # GET this for params
AlgoTx.submit_url(network: String = "mainnet") -> String   # POST signed tx here
AlgoTx.pending_url(txid: String, network: String = "mainnet") -> String
```

`network` can be `"mainnet"` or `"testnet"`. URLs point to the free public [AlgoNode](https://algonode.io) API.

**Full send example**

```gdscript
var acc := AlgoAccount.new("your twenty five word mnemonic goes here ...")

func _ready() -> void:
    $HTTPRequest.request_completed.connect(_on_params)
    $HTTPRequest.request(AlgoTx.params_url("testnet"))

func _on_params(_result, _code, _headers, body: PackedByteArray) -> void:
    var params := AlgoTx.params_from_json(JSON.parse_string(body.get_string_from_utf8()))
    var tx := AlgoTx.make_payment(acc.public_key, "RECEIVER_ADDRESS", 1_000_000, params)
    var signed := AlgoTx.sign_tx(tx, acc.private_key, acc.public_key)
    var headers := ["Content-Type: application/x-binary"]
    $HTTPRequest.request_completed.connect(_on_submit)
    $HTTPRequest.request_raw(AlgoTx.submit_url("testnet"), headers, HTTPClient.METHOD_POST, signed)

func _on_submit(_result, _code, _headers, body: PackedByteArray) -> void:
    print(JSON.parse_string(body.get_string_from_utf8()))
```

---

### `AlgoABI`

ARC-4 ABI encoder for Alpha Market smart contracts. All methods are static.

#### Type encoders

```gdscript
# Encode a non-negative integer as 8 big-endian bytes (ABI uint64).
AlgoABI.uint64(n: int) -> PackedByteArray

# Validate and return a 32-byte public key for use as an ABI address argument.
AlgoABI.address_arg(pk_bytes: PackedByteArray) -> PackedByteArray
```

#### App address derivation

```gdscript
# Returns the 32-byte public key of an application's escrow address.
AlgoABI.app_address(app_id: int) -> PackedByteArray

# Returns the Algorand address string of an application's escrow address.
AlgoABI.app_address_str(app_id: int) -> String
```

#### Fee calculation

```gdscript
# Calculates trading fee: floor(quantity * price / 1_000_000 * fee_base / 1_000_000)
AlgoABI.calculate_fee(quantity: int, price: int, fee_base: int) -> int
```

#### Alpha Market call builders

Each returns a `PackedByteArray` ready to be used as an element of `app_args` in `AlgoTx.make_app_call()`.

```gdscript
AlgoABI.call_create_escrow(price: int, quantity: int, slippage: int, position: int) -> PackedByteArray
AlgoABI.call_delete_escrow(escrow_app_id: int, algo_receiver_pk: PackedByteArray) -> PackedByteArray
AlgoABI.call_split_shares() -> PackedByteArray
AlgoABI.call_merge_shares() -> PackedByteArray
AlgoABI.call_claim() -> PackedByteArray
AlgoABI.call_propose_a_match(
    market_app_id: int,
    maker_escrow_app_id: int,
    quantity_matched: int,
    taker_pk: PackedByteArray,
    maker_pk: PackedByteArray,
    fee_pk: PackedByteArray,
    taker_app_created_index_offset: int
) -> PackedByteArray
```

---

### `Ed25519`

Ed25519 digital signatures. Must be instantiated (constructor precomputes the base-point table).

```gdscript
var ed := Ed25519.new()   # ~250 ms first time; reuse the instance

# Derive a 32-byte public key from a 32-byte secret key seed.
ed.publickey(sk: PackedByteArray) -> PackedByteArray

# Sign a message. Returns a 64-byte signature.
ed.signature(m: PackedByteArray, sk: PackedByteArray, pk: PackedByteArray) -> PackedByteArray

# Verify a signature. Returns true if valid, false (+ push_error) if not.
ed.checkvalid(s: PackedByteArray, m: PackedByteArray, pk: PackedByteArray) -> bool
```

`AlgoAccount` and `AlgoTx` use `Ed25519` internally — you only need to use it directly if you're doing custom signing outside those classes.

> **Note:** This implementation is not side-channel safe. It is suitable for game bots and scripts but not for high-security production wallets.

**Typical performance on desktop** (measured during test run):
- `publickey`: ~100 ms
- `signature`: ~100 ms
- `checkvalid`: ~600 ms

---

### `SHA512`

SHA-512 and SHA-512/256. Can be used as a one-shot static call or incrementally via an instance.

```gdscript
# One-shot: hash data and return n_bytes of output (default 64).
SHA512.hash(data: PackedByteArray, n_bytes: int = 64, iv: Array = []) -> PackedByteArray

# SHA-512/256 with Algorand's IV — used for address checksums and group IDs.
SHA512.sha512_256(data: PackedByteArray) -> PackedByteArray

# Incremental (streaming) usage:
var h := SHA512.new()
h.update(chunk1)
h.update(chunk2)
var digest: PackedByteArray = h.digest()   # non-destructive; can call again
```

---

### `MsgPack`

Minimal MessagePack encoder covering the subset Algorand transactions require. Decoding is not implemented.

```gdscript
MsgPack.pack(v) -> PackedByteArray
```

Supported types:

| GDScript type | MessagePack encoding |
|---|---|
| `null` | nil |
| `bool` | true / false |
| `int` (≥ 0) | positive fixint / uint8 / uint16 / uint32 / uint64 |
| `PackedByteArray` | bin8 / bin16 |
| `String` | fixstr / str8 / str16 |
| `Dictionary` | fixmap / map16 (keys sorted, null values omitted) |
| `Array` | fixarray / array16 |

Negative integers and floats are not supported (not needed by Algorand).

---

### `BigInt` (internal)

Arbitrary-precision non-negative integer arithmetic used internally by `Ed25519`. Represents numbers as arrays of 16-bit little-endian limbs. Not intended for direct use outside of `Ed25519`.

---

## Running the tests

Three test scripts are in `tests/`. Each extends `Node` and runs automatically when the node enters the scene tree.

**From a `.tscn` scene (Godot editor):**

1. Create a new scene with a `Node` as root.
2. Attach a test script (`test_algo_account.gd`, `test_transactions.gd`, or `test_ed25519.gd`) to it.
3. Press **F5**. Results appear in the **Output** panel.

You can add all three as child nodes in the same scene to run them all at once.

**From the terminal (headless):**

```bash
# Run from the project root
~/Godot_v4.5.1-stable_linux.x86_64 --headless --script tests/test_algo_account.gd
~/Godot_v4.5.1-stable_linux.x86_64 --headless --script tests/test_transactions.gd
~/Godot_v4.5.1-stable_linux.x86_64 --headless --script tests/test_ed25519.gd
```

> Note: headless `--script` mode requires the project to have been imported at least once. Run `godot --headless --import` if you see "class not found" errors.

**Expected results:** 20/20 tests pass across all three suites.

---

## File structure

```
addons/algodot/
  algo_account.gd   # AlgoAccount — mnemonic → keypair + address
  transactions.gd   # AlgoTx     — build, group, sign, submit transactions
  abi.gd            # AlgoABI    — ARC-4 ABI encoder for Alpha Market
  ed25519.gd        # Ed25519    — digital signatures
  sha512.gd         # SHA512     — SHA-512 and SHA-512/256
  msgpack.gd        # MsgPack    — MessagePack encoder
  bigint.gd         # BigInt     — internal big-integer arithmetic
  plugin.cfg        # plugin manifest (enables Algodot in Project Settings)
  plugin.gd         # EditorPlugin entry point

tests/
  test_algo_account.gd    # 4 tests: mnemonic derivation, address round-trip, SHA-512/256
  test_transactions.gd    # 8 tests: payment, opt-in, transfer, app call, msgpack, group ID, ABI
  test_ed25519.gd         # 8 tests: determinism, sign/verify, rejection, RFC 8032 vector

wordlist.txt        # BIP-39 English word list (required by AlgoAccount)
```
