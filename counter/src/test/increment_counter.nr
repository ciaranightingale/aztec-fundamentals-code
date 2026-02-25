use crate::{test::utils::{self}, Counter};

#[test]
unconstrained fn test_increment_counter() {
    let counter_contract_address = utils::deploy_counter_contract();
    // let transfer_amount = (1000 as u128);
    // let transfer_private_from_call_interface = Token::at(token_contract_address)
    //     .transfer_private_to_private(owner, recipient, transfer_amount, 1);
    // authwit_cheatcodes::add_private_authwit_from_call(
    //     env,
    //     owner,
    //     auth_account,
    //     transfer_private_from_call_interface,
    // );
    // // Transfer tokens via proxy
    // env.call_private(
    //     owner,
    //     transfer_private_from_call_interface
    // );
    // // Check balances
    // utils::check_private_balance(
    //     env,
    //     token_contract_address,
    //     owner,
    //     mint_amount - transfer_amount,
    // );
}