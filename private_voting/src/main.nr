// Import the aztec macro which transforms our module into an Aztec contract
use aztec::macros::aztec;

// Apply the #[aztec] attribute to generate all the boilerplate for an Aztec contract
#[aztec]
pub contract PrivateVoting {
    // Import macros: external for callable functions, initializer for constructor,
    // only_self restricts a function to only be callable by the contract itself, storage for state
    use aztec::macros::{functions::{external, initializer, only_self}, storage::storage};
    // AztecAddress for addresses; Deserialize/Serialize for encoding structs; ToField for type conversion
    use aztec::protocol::{address::AztecAddress, traits::{Deserialize, Serialize, ToField}};
    // Map is a key-value store; Owned maps owners to state vars; PublicImmutable is write-once public storage;
    // PublicMutable is read-write public storage; SingleUseClaim ensures something can only be claimed once
    use aztec::state_vars::{Map, Owned, PublicImmutable, PublicMutable, SingleUseClaim};

    // Define a custom struct to represent an election identifier
    // Derive Serialize and Deserialize so it can be stored in and read from contract storage
    #[derive(Serialize, Deserialize)]
    pub struct ElectionId {
        id: Field,
    }

    // Constructor for creating a new ElectionId
    impl ElectionId {
        pub fn new(id: Field) -> Self {
            Self { id }
        }
    }

    // Implement ToField so ElectionId can be used as a Map key
    impl ToField for ElectionId {
        fn to_field(self) -> Field {
            self.id
        }
    }

    // Define the contract's storage layout
    #[storage]
    struct Storage<Context> {
        // The admin address stored publicly - admin can start and end elections
        admin: PublicMutable<AztecAddress, Context>,
        // Nested map: election => candidate => vote count (all public since tallies are public)
        tally: Map<ElectionId, Map<Field, PublicMutable<Field, Context>, Context>, Context>,
        // Maps each election to whether voting has ended (true = ended)
        vote_ended: Map<ElectionId, PublicMutable<bool, Context>, Context>,
        // Maps each election to the block number it became active (immutable once set)
        active_at_block: Map<ElectionId, PublicImmutable<u32, Context>, Context>,
        // Maps election => voter => a single-use claim that ensures each voter can only vote once
        // Owned means each voter gets their own SingleUseClaim scoped to their address
        vote_claims: Map<ElectionId, Owned<SingleUseClaim<Context>, Context>, Context>,
    }

    // The constructor - runs once at deployment. Public because admin is stored in public state
    #[external("public")]
    #[initializer]
    fn constructor(admin: AztecAddress) {
        // Write the admin address to public storage
        self.storage.admin.write(admin);
    }

    // Cast a vote - this is PRIVATE so nobody can see who voted for which candidate
    #[external("private")]
    fn cast_vote(election_id: ElectionId, candidate: Field) {
        // Claim the voter's single-use claim for this election
        // This will fail if the voter has already voted, preventing double-voting
        // Because this is private, nobody can link the voter's identity to their vote
        self.storage.vote_claims.at(election_id).at(self.msg_sender()).claim();
        // Enqueue a public function call to actually update the tally
        // We need to go from private to public because the tally is stored in public state
        // enqueue_self schedules a call to our own add_to_tally_public function
        self.enqueue_self.add_to_tally_public(election_id, candidate);
    }

    // Internal public function that updates the vote tally - only callable by this contract itself
    #[external("public")]
    #[only_self] // Restricts this function so only the contract can call it (via enqueue_self)
    fn add_to_tally_public(election_id: ElectionId, candidate: Field) {
        // Check that the election has started by verifying the current block is at or past the start block
        assert(self.storage.active_at_block.at(election_id).read() <= self.context.block_number());
        // Check that the election hasn't ended yet
        assert(self.storage.vote_ended.at(election_id).read() == false, "Vote has ended");
        // Read the current tally for this candidate and add 1
        let new_tally = self.storage.tally.at(election_id).at(candidate).read() + 1;
        // Write the updated tally back to storage
        self.storage.tally.at(election_id).at(candidate).write(new_tally);
    }

    // Start a new election - only the admin can call this
    #[external("public")]
    fn start_vote(election_id: ElectionId) {
        // Verify the caller is the admin
        assert(self.storage.admin.read().eq(self.msg_sender()), "Only admin can start votes");
        // Mark the election as not ended (active)
        self.storage.vote_ended.at(election_id).write(false);
        // Record the current block number as the election start block (immutable - can only be set once)
        self.storage.active_at_block.at(election_id).initialize(self.context.block_number());
    }

    // End an election - only the admin can call this
    #[external("public")]
    fn end_vote(election_id: ElectionId) {
        // Verify the caller is the admin
        assert(self.storage.admin.read().eq(self.msg_sender()), "Only admin can end votes");
        // Mark the election as ended - no more votes can be cast after this
        self.storage.vote_ended.at(election_id).write(true);
    }

    // Query the vote count for a candidate in an election - unconstrained (no proof needed)
    #[external("utility")]
    unconstrained fn get_tally(election_id: ElectionId, candidate: Field) -> Field {
        // Read and return the current vote count for the given candidate in the given election
        self.storage.tally.at(election_id).at(candidate).read()
    }
}
