use crate::{test::utils::{self}, Counter};
use aztec::{
    oracle::logging::debug_log_format,
    protocol::{traits::ToField},
};

#[test]
unconstrained fn test_decrement_counter() {
    let (mut env, counter_contract_address) = utils::deploy_counter_contract();

    let user = env.create_light_account();

    // check the counter is initially 0
    let counter_value_initial = utils::get_private_counter(&mut env, counter_contract_address, user);
    assert(counter_value_initial == 0, "counter value not zero");
    debug_log_format("counter value innit {0}", [counter_value_initial.to_field()]);

    // have to increment before can decrement
    let counter_value_before = utils::increment_counter(&mut env, user, counter_contract_address);
    assert(counter_value_before == 1, "counter value not 1");

    // now decrement
    let decrement_call_private = Counter::at(counter_contract_address).decrement_private();
    env.call_private(
        // who is calling
        user,
        // what is the calldata (fn and inputs)
        decrement_call_private
    );
    // get the new value 
    let counter_value = utils::get_private_counter(&mut env, counter_contract_address, user);
    debug_log_format("counter for owner {0}", [counter_value.to_field()]);
    assert(counter_value == (counter_value_before -1), "increment failed");
    assert(counter_value == 0, "counter != 0");
}