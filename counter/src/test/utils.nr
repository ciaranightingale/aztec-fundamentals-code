use crate::Counter;
use aztec::{
    note::{constants::MAX_NOTES_PER_PAGE, note_viewer_options::NoteViewerOptions},
    oracle::random::random,
    protocol::{address::AztecAddress, traits::Packable},
    state_vars::{OwnedStateVariable, PrivateSet},
    test::helpers::test_environment::TestEnvironment,
};
use uint_note::UintNote;

pub fn deploy_counter_contract() -> AztecAddress {
    let mut env = TestEnvironment::new();
    let owner = env.create_contract_account();
    let initializer_call_interface = Counter::interface().initialize(0, owner);
    let counter_contract_address = env.deploy("@counter_contracr/Counter").with_public_initializer(owner, initializer_call_interface);
    counter_contract_address
}