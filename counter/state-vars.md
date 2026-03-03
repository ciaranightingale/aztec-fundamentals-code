# Storage Script — Counter Contract
## Read aloud while typing. Audience only sees the screen.

---

## TYPE: `#[storage]`

"The first thing I need to do is mark this struct with the `#[storage]` attribute.
This is a macro from aztec-nr that does two things: it assigns a unique storage
slot to every field in the struct automatically — so I don't have to track slot
numbers manually — and it wires up `self.storage` inside every function so I can
access these fields by name. Every Aztec contract has exactly one struct with
this attribute."

---

## TYPE: `struct Storage<Context> {`

"Notice this struct is generic over `Context`. This is important to understand
before we look at any of the fields.

When a state variable is accessed, it behaves differently depending on where
it's being called from. In a private function it's operating inside a ZK circuit —
it can produce note commitments and nullifiers but it can't read raw blockchain state.
In a public function it's running on the AVM — it can read and write plain storage
directly. In an unconstrained utility function it's running off-chain in the PXE —
it can decrypt notes from local storage without producing any proof.

The `Context` type parameter carries that information into the state variable.
If you look at the aztec-nr source, `PrivateSet` for example has separate `impl`
blocks for `&mut PrivateContext` and for `UtilityContext` — entirely different
methods are available depending on which context is injected. You never construct
the context yourself, aztec-nr injects the right one based on which function
the state variable is being used in."

---

## TYPE: `counters: ` — PAUSE before writing the type

"Now for the actual field. This is a private counter, so we can't use a
`PublicMutable<u128>` or anything like that. Here's why.

Public state is simple: the value lives directly in a key-value store on the AVM
and anyone can read it. So `PublicMutable<u128>` genuinely just stores a `u128`.

Private state works completely differently. The value is never stored on-chain
in plaintext — it lives inside an encrypted note, off-chain, known only to the
recipient. What IS on-chain is the note's commitment: a hash of the note's
contents. When you spend a note you emit its nullifier to prevent double-spending.
This is the note/nullifier/commitment model you already know.

So a private state variable can't be `PrivateMutable<u128>` in the same way.
It has to work with notes. And to work with notes it needs to know what a note
looks like — what fields it has, how to hash them into a commitment, how to
derive a nullifier from them. That's what a note type is: a Noir struct that
implements those operations.

This means every private state variable has two type parameters:
the context we just discussed, and the note type.

The fundamental primitive in aztec-nr is `PrivateSet<Note, Context>`.
A `PrivateSet` holds three things internally: the context, a storage slot,
and an owner address. Calling `insert` on it takes a note, hashes it into a
commitment, and emits that commitment to the note hash tree. Calling `pop_notes`
fetches notes that are already in the tree and immediately nullifies them —
that's how you spend. Calling `get_notes` reads notes without nullifying.
And in an unconstrained context, `view_notes` decrypts notes from local PXE
storage without producing any proof at all. The note type you give it tells
the set exactly what struct to deserialize, how to verify hashes, everything.

So if we were writing this contract from scratch we could use
`PrivateSet<UintNote, Context>` directly. But for a counter we need balance
arithmetic on top of that. Enter `BalanceSet`."

---

## TYPE: `Owned<BalanceSet<Context>, Context>`

"Let me explain this inside-out.

`UintNote` is the note type that `BalanceSet` uses under the hood. It's a note
struct with a single field: `value: u128`. Its `compute_note_hash` implementation
takes the owner address, storage slot, and a randomness field — hashes them together
with poseidon2 to form a partial commitment, then hashes that with the actual value.
The randomness means two notes with the same value produce different commitments,
so they're indistinguishable on-chain. Its `compute_nullifier` derives a secret key
from the owner's nullifier key and hashes it with the note hash — so only the owner
can produce the nullifier.

`BalanceSet<Context>` is a wrapper around `PrivateSet<UintNote, Context>` that gives
us balance-oriented methods instead of raw note operations. `add(amount)` inserts a
new `UintNote` with that value. `try_sub(target, max_notes)` uses a greedy algorithm
— it sorts notes descending by value, pops them one by one until it reaches the
target amount, and returns how much was actually subtracted. If you need more notes
than fit in one circuit call, the contract handles that recursively — which we'll
see in the transfer functions later. `balance_of` is unconstrained and sums all
unspent notes from the PXE's local decrypted note store. `BalanceSet` also
implements a trait called `OwnedStateVariable`, which is what makes the next
wrapper work.

`Owned<BalanceSet<Context>, Context>` is the outermost wrapper and it solves
a problem specific to private state: keying by owner. In public state you'd use
`Map<AztecAddress, PublicMutable<u128>>` and each address gets its own slot.
For private state, `Owned` plays that role. It holds the storage slot but no
owner. When you call `.at(owner_address)` inside a function, it constructs a
fresh `BalanceSet` initialised with that specific owner address baked in —
because `BalanceSet` implements `OwnedStateVariable`, which is just the interface
saying 'I can be constructed given a context, a storage slot, and an owner'.
Every note in that `BalanceSet` will be tagged with that owner, and the nullifier
derivation will require that owner's key. So you cannot produce a nullifier for
someone else's notes.

So the full chain is: `Owned` is the key-by-address wrapper, `BalanceSet` is the
balance-arithmetic wrapper, `PrivateSet<UintNote>` is the raw note set primitive,
and `UintNote` is the actual note struct whose hash and nullifier implement the
privacy guarantees."

---

## After closing the struct

"One line of storage, but there's a lot happening. The rest of the contract is
just calling into this through `self.storage.counters.at(owner)` — everything
else — adding a note, nullifying notes, reading the balance — is handled by
`BalanceSet` and `PrivateSet` and the protocol underneath."
