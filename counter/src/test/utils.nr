use crate::Counter;
use aztec::{
    protocol::{address::AztecAddress},
    test::helpers::test_environment::TestEnvironment,
};

pub unconstrained fn deploy_counter_contract() -> (TestEnvironment, AztecAddress) {
    let mut env = TestEnvironment::new();
    let owner = env.create_contract_account();
    let initializer_call_interface = Counter::interface().initialize(0, owner);
    let counter_contract_address = env.deploy("@counter_contract/Counter").with_private_initializer(owner, initializer_call_interface);
    (env, counter_contract_address)
}

pub unconstrained fn get_private_counter(env: &mut TestEnvironment, contract_address: AztecAddress, account: AztecAddress) -> u128 {
    let value = env.execute_utility(Counter::at(contract_address).get_private_counter(account));
    value
}

pub unconstrained fn get_public_counter(env: &mut TestEnvironment, contract_address: AztecAddress, account: AztecAddress) -> u128 {
    env.view_public(Counter::at(contract_address).get_public_counter(account))
}

pub unconstrained fn increment_public_counter(env: &mut TestEnvironment, user: AztecAddress, counter_contract_address: AztecAddress) -> u128 {
    env.call_public(user, Counter::at(counter_contract_address).increment_public());
    get_public_counter(env, counter_contract_address, user)
}

pub unconstrained fn decrement_public_counter(env: &mut TestEnvironment, user: AztecAddress, counter_contract_address: AztecAddress) -> u128 {
    env.call_public(user, Counter::at(counter_contract_address).decrement_public());
    get_public_counter(env, counter_contract_address, user)
}

pub unconstrained fn increment_counter(env: &mut TestEnvironment, user: AztecAddress, counter_contract_address: AztecAddress) -> u128 {
    let increment_call_private = Counter::at(counter_contract_address).increment_private();
    env.call_private(
        // who is calling
        user,
        // what is the calldata (fn and inputs)
        increment_call_private
    );
    let counter_value = get_private_counter(env, counter_contract_address, user);
    counter_value
}