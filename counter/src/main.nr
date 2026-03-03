// Import the aztec macro which transforms our module into an Aztec contract
pub mod test;
use aztec::macros::aztec;

// Apply the #[aztec] attribute to generate all the boilerplate code for our contract
#[aztec]
pub contract Counter {
    // Import the macros we need: external marks functions callable from outside,
    // initializer marks the constructor, and storage marks our storage struct
    use aztec::{
        macros::{functions::{external, initializer, view}, storage::storage},
        // MessageDelivery controls how note delivery happens (onchain constrained vs unconstrained)
        messages::message_delivery::MessageDelivery,
        // debug_log_format lets us log messages during execution for debugging
        oracle::logging::debug_log_format,
        // AztecAddress is the type for addresses on Aztec, ToField lets us convert types to Field
        protocol::{address::AztecAddress, traits::ToField},
        // Owned is a wrapper that maps an owner address to a state variable
        state_vars::{Map, Owned, PublicMutable},
    };
    // BalanceSet is a specialized collection for managing balances using encrypted notes
    use balance_set::BalanceSet;

    // Define the contract's persistent storage layout
    #[storage]
    struct Storage<Context> {
        // Each owner address maps to their own BalanceSet, which tracks their counter value as a balance
        counters: Owned<BalanceSet<Context>, Context>,
        public_counters: Map<AztecAddress, PublicMutable<u128, Context>, Context>
    }

    // This function runs once when the contract is deployed - it sets up the initial state
    #[initializer]
    // Mark as a private function so it executes on the client side with zero-knowledge proofs
    #[external("private")]
    fn initialize(headstart: u64, owner: AztecAddress) {
        // Add the headstart value to the owner's counter balance
        // .at(owner) selects the owner's BalanceSet, .add() creates a new note with the value
        // .deliver(ONCHAIN_CONSTRAINED) ensures the note is delivered onchain with a proof that it's valid
        self.storage.counters.at(owner).add(headstart as u128).deliver(
            MessageDelivery.ONCHAIN_CONSTRAINED,
        );
    }

    // A private function that increments the counter for a given owner
    #[external("private")]
    fn increment_private(owner: AztecAddress) {
        assert(self.msg_sender() == owner, "Unauthorized");
        // Log the owner's address for debugging purposes
        debug_log_format("Incrementing counter for owner {0}", [owner.to_field()]);
        // Add 1 to the owner's counter and deliver the note onchain with constrained delivery
        self.storage.counters.at(owner).add(1).deliver(MessageDelivery.ONCHAIN_CONSTRAINED);
    }

    #[external("public")]
    fn increment_public(owner: AztecAddress) {
        assert(self.msg_sender() == owner, "Unauthorized");
        debug_log_format("Incrementing counter for owner {0}", [owner.to_field()]);
        self.storage.public_counters.at(owner).write(self.storage.public_counters.at(owner).read() + 1);
    }

    #[external("public")]
    fn decrement_public(owner: AztecAddress) {
        assert(self.msg_sender() == owner, "Unauthorized");
        self.storage.public_counters.at(owner).write(self.storage.public_counters.at(owner).read() - 1);
    }

    #[external("private")]
    fn decrement_private(owner: AztecAddress) {
        assert(self.msg_sender() == owner, "Unauthorized");
        debug_log_format("Decrementing counter for owner {0}", [owner.to_field()]);
        self.storage.counters.at(owner).sub(1).deliver(MessageDelivery.ONCHAIN_CONSTRAINED);
    }

    #[external("public")]
    #[view]
    fn get_public_counter(owner: AztecAddress) -> pub u128 {
        self.storage.public_counters.at(owner).read()
    }

    // A utility function that reads state without generating a proof - used for querying PXE state
    #[external("utility")]
    unconstrained fn get_counter(owner: AztecAddress) -> pub u128 {
        // Read and return the current balance (counter value) for the given owner
        self.storage.counters.at(owner).balance_of()
    }
}