// Import the aztec macro which transforms our module into an Aztec contract
mod test;
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
        state_vars::{Map, Owned, PrivateMutable, PublicMutable},
    };
    // UintNote is a simple note storing a u128 value
    use uint_note::UintNote;

    // Define the contract's persistent storage layout
    #[storage]
    struct Storage<Context> {
        // Each owner address maps to their own PrivateMutable, which holds exactly one note with their counter value
        counters: Owned<PrivateMutable<UintNote, Context>, Context>,
        public_counters: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
    }

    // This function runs once when the contract is deployed - it sets up the initial state
    #[initializer]
    // Mark as a private function so it executes on the client side with zero-knowledge proofs
    #[external("private")]
    fn initialize(headstart: u64, owner: AztecAddress) {
        // Create the first note for the owner with the headstart value
        self.storage.counters.at(owner).initialize(UintNote { value: headstart as u128 }).deliver(
            MessageDelivery.ONCHAIN_CONSTRAINED,
        );
    }

    // A private function that increments the counter for msg_sender
    #[external("private")]
    fn increment_private() {
        // Log the owner's address for debugging purposes
        debug_log_format("Incrementing counter for owner {0}", [self.msg_sender().to_field()]);
        // If not yet initialized, create the first note with value 1; otherwise nullify the current note and replace it with value + 1
        self.storage.counters.at(self.msg_sender()).initialize_or_replace(|opt_note| {
            UintNote { value: opt_note.unwrap_or(UintNote { value: 0 }).value + 1 }
        }).deliver(MessageDelivery.ONCHAIN_CONSTRAINED);
    }

    #[external("private")]
    fn decrement_private() {
        debug_log_format("Decrementing counter for owner {0}", [self.msg_sender().to_field()]);
        // If not yet initialized, treat current value as 0 (underflow will panic); otherwise nullify and replace with value - 1
        self.storage.counters.at(self.msg_sender()).initialize_or_replace(|opt_note| {
            UintNote { value: opt_note.unwrap_or(UintNote { value: 0 }).value - 1 }
        }).deliver(MessageDelivery.ONCHAIN_CONSTRAINED);
    }

    #[external("public")]
    fn increment_public() {
        debug_log_format("Incrementing counter for owner {0}", [self.msg_sender().to_field()]);
        self.storage.public_counters.at(self.msg_sender()).write(self.storage.public_counters.at(self.msg_sender()).read() + 1);
    }

    #[external("public")]
    fn decrement_public() {
        self.storage.public_counters.at(self.msg_sender()).write(self.storage.public_counters.at(self.msg_sender()).read() - 1);
    }

    #[external("public")]
    #[view]
    fn get_public_counter(owner: AztecAddress) -> pub u128 {
        self.storage.public_counters.at(owner).read()
    }

    // A utility function that reads state without generating a proof - used for querying PXE state
    #[external("utility")]
    unconstrained fn get_private_counter(owner: AztecAddress) -> pub u128 {
        // Check if initialized first - if not, return 0 (no note exists yet)
        let counter = self.storage.counters.at(owner);
        if counter.is_initialized() {
            counter.view_note().value
        } else {
            0
        }
    }
}