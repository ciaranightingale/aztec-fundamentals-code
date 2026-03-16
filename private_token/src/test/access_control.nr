use crate::test::utils;
use crate::Token;
use aztec::protocol::traits::ToField;

#[test]
unconstrained fn access_control() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, owner, new_admin) =
        utils::setup(/* with_account_contracts */ false);

    let token = Token::at(token_contract_address);

    // Set a new admin
    env.call_public(owner, token.set_admin(new_admin));
    assert_eq(env.view_public(token.get_admin()), new_admin.to_field());
}

#[test(should_fail_with = "caller is not admin")]
unconstrained fn set_admin_requires_admin_caller() {
    // Setup without account contracts. We are not using authwits here, so dummy accounts are enough
    let (env, token_contract_address, _, other) = utils::setup(/* with_account_contracts */ false);

    let token = Token::at(token_contract_address);

    env.call_public(other, token.set_admin(other));
}