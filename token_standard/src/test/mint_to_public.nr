use crate::{test::utils, Token};

#[test]
unconstrained fn test_mint_to_public() {
    let (mut env, token_contract_address, owner, _) = utils::setup(false);

    let mint_amount: u128 = 10_000;
    env.call_public(owner, Token::at(token_contract_address).mint_to_public(owner, mint_amount));

    utils::check_public_balance(env, token_contract_address, owner, mint_amount);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == mint_amount);
}

#[test(should_fail_with = "Contract execution has reverted: Assertion failed: caller is not minter 'self.storage.minter.read().eq(self.msg_sender())'")]
unconstrained fn test_mint_to_public_failure_non_minter() {
    let (mut env, token_contract_address, owner, recipient) = utils::setup(false);

    let mint_amount: u128 = 10_000;
    let mint_to_public_call_interface =
        Token::at(token_contract_address).mint_to_public(owner, mint_amount);

    // As non-minter
    env.call_public(recipient, mint_to_public_call_interface);
}

#[test(should_fail_with = "Contract execution has reverted: Assertion failed: attempt to add with overflow 'self.storage.public_balances.at(to).read() + amount'")]
unconstrained fn test_mint_to_public_failure_overflow_total_supply() {
    let (mut env, token_contract_address, owner, _) = utils::setup(false);

    let max_u128 = utils::max_u128();
    let mint_to_public_call_interface =
        Token::at(token_contract_address).mint_to_public(owner, max_u128);

    env.call_public(owner, mint_to_public_call_interface);
    utils::check_public_balance(env, token_contract_address, owner, max_u128);

    let total_supply = env.view_public(Token::at(token_contract_address).total_supply());
    assert(total_supply == max_u128);

    // Overflow total supply
    env.call_public(owner, Token::at(token_contract_address).mint_to_public(owner, 1 as u128));
}
