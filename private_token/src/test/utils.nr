use crate::Token;
use caller_contract::CallerContract;
use aztec::{
    note::{constants::MAX_NOTES_PER_PAGE, note_viewer_options::NoteViewerOptions},
    oracle::random::random,
    protocol::{address::AztecAddress, traits::Packable},
    state_vars::{OwnedStateVariable, PrivateSet},
    test::helpers::test_environment::TestEnvironment,
};
use aztec::test::helpers::authwit as authwit_cheatcodes;
use std::ops::WrappingSub;
use std::test::OracleMock;
use uint_note::UintNote;

pub global mint_amount: u128 = 10_000 as u128;

pub unconstrained fn setup_with_initial_supply(
    with_account_contracts: bool,
    initial_supply: u128,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    // Setup env, generate keys
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

    let token_contract_address =
        deploy_token_with_initial_supply(&mut env, owner, initial_supply, owner);

    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn deploy_token_with_initial_supply(
    env: &mut TestEnvironment,
    owner: AztecAddress,
    initial_supply: u128,
    to: AztecAddress,
) -> AztecAddress {
    // Deploy token contract
    let initializer_call_interface = Token::interface().constructor(
        "TestToken0000000000000000000000",
        "TT00000000000000000000000000000",
        18,
        initial_supply,
        to,
    );
    let token_contract_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        initializer_call_interface,
    );

    token_contract_address
}

pub unconstrained fn setup_and_mint_to_public_without_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    let (env, token_contract_address, owner, recipient) =
        setup_with_initial_supply(with_account_contracts, mint_amount);

    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn setup_and_mint_to_public_with_account_contracts(
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient) =
        setup_and_mint_to_public_without_minter(true);
    // Deploy a CallerContract so tests can trigger authwit by routing calls through it
    let auth_account = env.deploy("@caller_contract/CallerContract").without_initializer();
    (env, token_contract_address, owner, recipient, auth_account)
}

pub unconstrained fn setup_and_mint_to_private_without_minter(
    with_account_contracts: bool,
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress) {
    // Setup
    let (env, token_contract_address, owner, recipient) =
        setup_with_initial_supply(with_account_contracts, mint_amount);

    env.call_private(
        owner,
        Token::at(token_contract_address).transfer_public_to_private(owner, owner, mint_amount, 0),
    );

    (env, token_contract_address, owner, recipient)
}

pub unconstrained fn setup_and_mint_to_private_with_account_contracts(
) -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let (mut env, token_contract_address, owner, recipient) =
        setup_and_mint_to_private_without_minter(true);
    // Deploy a CallerContract so tests can trigger authwit by routing calls through it
    // (msg_sender = CallerContract != owner, which triggers the authwit check)
    let auth_account = env.deploy("@caller_contract/CallerContract").without_initializer();
    (env, token_contract_address, owner, recipient, auth_account)
}

/// @notice Transfers tokens from public balance to a new private note.
/// Mocks getRandomField to ensure each call creates a distinct note commitment.
pub unconstrained fn transfer_to_private(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    from: AztecAddress,
    to: AztecAddress,
    amount: u128,
) {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);
    env.call_private(
        from,
        Token::at(token_contract_address).transfer_public_to_private(from, to, amount, 0),
    );
}

pub unconstrained fn transfer_in_private(
    env: TestEnvironment,
    from: AztecAddress,
    token_contract_address: AztecAddress,
    recipient: AztecAddress,
    amount: u128,
) {
    let note_randomness = random();
    let _ = OracleMock::mock("getRandomField").returns(note_randomness);

    env.call_private(
        from,
        Token::at(token_contract_address).transfer_private_to_private(from, recipient, amount, 0),
    );
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
    let amt = env.simulate_utility(Token::at(token_contract_address).balance_of_private(address));
    amt
}

pub unconstrained fn get_private_balance_notes(
    env: TestEnvironment,
    token_contract_address: AztecAddress,
    account: AztecAddress,
    offset: u32,
) -> BoundedVec<UintNote, MAX_NOTES_PER_PAGE> {
    let notes = env.utility_context_at(token_contract_address, |context| {
        let options =
            NoteViewerOptions::<UintNote, <UintNote as Packable>::N>::new().set_offset(offset);
        let private_balances_slot = Token::storage_layout().private_balances.slot;
        let set: PrivateSet<UintNote, _> =
            OwnedStateVariable::new(context, private_balances_slot, account);
        let notes: BoundedVec<UintNote, MAX_NOTES_PER_PAGE> = set.view_notes(options);
        notes
    });

    notes
}

/// @notice Sets private authwit for the `transfer_private_to_public` method. `caller` is also the recipient.
pub unconstrained fn authorize_transfer_private_to_public(
    env: TestEnvironment,
    token: AztecAddress,
    caller: AztecAddress,
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) {
    let transfer_private_to_public_call_interface =
        Token::at(token).transfer_private_to_public(from, caller, amount, nonce);
    authwit_cheatcodes::add_private_authwit_from_call(
        env,
        from,
        caller,
        transfer_private_to_public_call_interface,
    );
}

/// @notice Sets public authwit for the `transfer_public_to_public` method. `caller` is also the recipient.
pub unconstrained fn authorize_transfer_public_to_public(
    env: TestEnvironment,
    token: AztecAddress,
    caller: AztecAddress,
    from: AztecAddress,
    amount: u128,
    nonce: Field,
) {
    let transfer_public_to_public_call_interface =
        Token::at(token).transfer_public_to_public(from, caller, amount, nonce);
    authwit_cheatcodes::add_public_authwit_from_call(
        env,
        from,
        caller,
        transfer_public_to_public_call_interface,
    );
}

/// @notice Returns the u128 maximum value
pub unconstrained fn max_u128() -> u128 {
    (0 as u128).wrapping_sub(1)
}
