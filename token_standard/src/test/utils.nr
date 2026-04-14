use crate::Token;
use aztec::{
    note::{constants::MAX_NOTES_PER_PAGE, note_viewer_options::NoteViewerOptions},
    protocol::{address::AztecAddress, traits::Packable},
    state_vars::{OwnedStateVariable, PrivateSet},
    test::helpers::test_environment::TestEnvironment,
};
use std::ops::WrappingSub;
use uint_note::UintNote;

pub global mint_amount: u128 = 10_000 as u128;

pub unconstrained fn setup(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();

    let (owner, recipient) = if with_account_contracts {
        let owner = env.create_contract_account();
        let recipient = env.create_contract_account();
        (owner, recipient)
    } else {
        let owner = env.create_light_account();
        let recipient = env.create_light_account();
        (owner, recipient)
    };

    let initializer_call_interface = Token::interface().constructor(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        owner,
    );
    let token_contract_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        initializer_call_interface,
    );

    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn setup_and_mint_to_public(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient) = setup(with_account_contracts);
    env.call_public(owner, Token::at(token_contract_address).mint_to_public(owner, mint_amount));
    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn setup_and_mint_to_private(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let (env, token_contract_address, owner, recipient) = setup(with_account_contracts);
    mint_to_private(env, token_contract_address, owner, mint_amount, owner);
    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn mint_to_private(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
    caller: AztecAddress,
) {
    env.call_private(caller, Token::at(token_contract_address).mint_to_private(recipient, amount));
}

pub unconstrained fn check_public_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
    address_amount: u128,
) {
    let amount: u128 = get_public_balance(env, token_contract_address, address);
    assert(amount == address_amount, "Public balance is not correct");
}

pub unconstrained fn get_public_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
) -> u128 {
    let amount = env.view_public(Token::at(token_contract_address).balance_of_public(address));
    amount
}

pub unconstrained fn check_total_supply(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    expected_total_supply: u128,
) {
    let total_supply: u128 = get_total_supply(env, token_contract_address);
    assert(total_supply == expected_total_supply, "Total supply is not correct");
}

pub unconstrained fn get_total_supply(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
) -> u128 {
    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    total_supply
}

pub unconstrained fn check_private_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
    address_amount: u128,
) {
    let balance_of_private = get_private_balance(env, token_contract_address, address);
    assert(balance_of_private == address_amount, "Private balance is not correct");
}

pub unconstrained fn get_private_balance(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    address: AztecAddress,
) -> u128 {
    let amt = env.execute_utility(Token::at(token_contract_address).balance_of_private(address));
    amt
}

// Unlike `get_private_balance` which calls the contract's `balance_of_private` function and returns
// a single summed u128, this function queries the PXE's note database to retrieve the individual
// notes that make up an account's private balance. This is useful for tests that need to verify how
// a balance is composed after operations like recursive transfers
// (e.g., "owner should have 2 notes: one worth 1000 and one worth 1").
//
// Why is this so complicated? Private notes in Aztec don't live on-chain - they live in the PXE
// (Private eXecution Environment), the client-side component that stores and manages private state.
// The contract only defines the storage layout (which slots correspond to which state variables),
// but the actual note data is held in the PXE's database. To query individual notes from a test,
// we need to:
// 1. Create a utility context scoped to the token contract (so we know which storage layout to use)
// 2. Look up the storage slot for the private_balances map from that layout
// 3. Reconstruct the PrivateSet at that slot for the specific account
// 4. Call view_notes to query the PXE for the individual notes at that slot
pub unconstrained fn get_private_balance_notes(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    account: AztecAddress,
    offset: u32,
) -> BoundedVec<UintNote, MAX_NOTES_PER_PAGE> {
    // `utility_context_at` creates an unconstrained execution context scoped to the token contract.
    // This is a test-only helper - in the TXE (Test eXecution Environment), it gives us the
    // ability to query the PXE's note database using the token contract's storage layout.
    // The closure receives a `context` that knows which contract's storage slots to reference.
    let notes = env.utility_context_at(token_contract_address, |context| {
        // NoteViewerOptions configures how we query notes from the PXE.
        // The type parameters tell it what kind of note to expect (UintNote) and its packed size.
        // `set_offset(offset)` allows pagination -- if there are more notes than MAX_NOTES_PER_PAGE,
        // we can call this function again with a higher offset to get the next page.
        let options =
            NoteViewerOptions::<UintNote, <UintNote as Packable>::N>::new().set_offset(offset);

        // Every storage variable in an Aztec contract is assigned a specific slot at compile time.
        // `Token::storage_layout()` gives us the compile-time map of slot assignments.
        // Here we grab the slot for `private_balances`, which is a Map<AztecAddress, BalancesMap>.
        // The PXE indexes notes by these slots, so we need the correct slot to query the right notes.
        let private_balances_slot = Token::storage_layout().private_balances.slot;

        // Now we reconstruct the PrivateSet for a specific account. Inside the contract,
        // `self.storage.private_balances.at(account)` does this automatically. But since we're
        // outside the contract in a test context, we have to manually build it:
        // - `context`: the utility context scoped to the token contract
        // - `private_balances_slot`: the base slot of the private_balances map
        // - `account`: the map key (which account's notes we want to query)
        // OwnedStateVariable derives the final storage slot by hashing the base slot with the
        // account address -- the same derivation that Map.at() does inside the contract.
        // This final slot is what the PXE uses to index this account's notes.
        let set: PrivateSet<UintNote, _> =
            OwnedStateVariable::new(context, private_balances_slot, account);

        // Finally, query the PXE for the actual notes at this derived slot. This returns each
        // individual UintNote (each with its own `.value`), rather than summing them into a
        // single balance. This is what makes this function different from `get_private_balance` --
        // we can inspect the note structure itself (how many notes exist, what each one is worth).
        let notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> = set.view_notes(options);
        notes
    });

    notes
}

// While authwits authorize a contract to perform an action, spending private notes still requires
// knowledge of the note secrets. For private tokens, the note owner must be involved in the
// transaction -- they cannot simply give another user an authwit and have that user spend the notes
// independently. We deploy a caller contract so that msg_sender in the target differs from the
// caller, which is the condition that triggers authwit validation. We can't use another account for
// this, since different scopes are enforced by TXE.
pub unconstrained fn setup_and_mint_to_private_with_caller() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient) =
        setup_and_mint_to_private(/* with_account_contracts */ true);
    let caller = env.deploy("@caller_contract/CallerContract").without_initializer();
    (env, token_contract_address, owner, recipient, caller)
}

pub unconstrained fn setup_and_mint_to_public_with_caller() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient) =
        setup_and_mint_to_public(/* with_account_contracts */ true);
    let caller = env.deploy("@caller_contract/CallerContract").without_initializer();
    (env, token_contract_address, owner, recipient, caller)
}

/// @notice Returns the u128 maximum value
pub unconstrained fn max_u128() -> u128 {
    (0 as u128).wrapping_sub(1)
}
