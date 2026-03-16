use crate::{test::utils, Token};
use aztec::{oracle::random::random, protocol::traits::Deserialize};
use uint_note::PartialUintNote;

/// Internal orchestration means that the calls to `prepare_private_balance_increase`
/// and `finalize_transfer_to_private` are done by the TOKEN contract itself.
/// In this test's case this is done by the `Token::transfer_to_private(...)` function called
/// in `utils::setup_mint_and_transfer_to_private`.
#[test]
unconstrained fn transfer_to_private_internal_orchestration() {
    // The transfer to private is done in `utils::setup_and_mint_to_private` and for this reason
    // in this test we just call it and check the outcome.
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, user, _, amount) =
        utils::setup_and_mint_to_private(/* with_account_contracts */ false);

    // User's private balance should be equal to the amount
    utils::check_private_balance(env, token_contract_address, user, amount);
}