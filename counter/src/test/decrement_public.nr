use crate::{test::utils::{self}, Counter};

#[test]
unconstrained fn test_decrement_public() {
    let (mut env, counter_contract_address) = utils::deploy_counter_contract();

    let user = env.create_light_account();

    // increment first so there is something to decrement
    let counter_after_increment = utils::increment_public_counter(&mut env, user, counter_contract_address);
    assert(counter_after_increment == 1, "counter should be 1 after increment");

    let counter_after_decrement = utils::decrement_public_counter(&mut env, user, counter_contract_address);
    assert(counter_after_decrement == 0, "counter should be back to 0 after decrement");
}