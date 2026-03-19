mod test;

use aztec::macros::aztec;

// Minimal token implementation that supports `AuthWit` accounts.
// The auth message follows a similar pattern to the cross-chain message and includes a designated caller.
// The designated caller is ALWAYS used here, and not based on a flag as cross-chain.
// message hash = H([caller, contract, selector, ...args])
// To be read as `caller` calls function at `contract` defined by `selector` with `args`
// Including a nonce in the message hash ensures that the message can only be used once.
#[aztec]
pub contract Token {
    // Libs
    use std::ops::{Add, Sub};

    use compressed_string::FieldCompressedString;

    use aztec::{
        authwit::auth::compute_authwit_nullifier,
        context::{PrivateCall, PrivateContext},
        macros::{
            events::event,
            functions::{authorize_once, external, initializer, internal, only_self, view},
            storage::storage,
        },
        messages::message_delivery::MessageDelivery,
        protocol::{address::AztecAddress, traits::ToField},
        state_vars::{Map, Owned, PublicImmutable, PublicMutable, StateVariable},
    };

    use uint_note::{PartialUintNote, UintNote};

    use balance_set::BalanceSet;

    // In the first transfer iteration we are computing a lot of additional information (validating inputs, retrieving
    // keys, etc.), so the gate count is already relatively high. We therefore only read a few notes to keep the happy
    // case with few constraints.
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    // All the recursive call does is nullify notes, meaning the gate count is low, but it is all constant overhead. We
    // therefore read more notes than in the base case to increase the efficiency of the overhead, since this results in
    // an overall small circuit regardless.
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    #[event]
    struct Transfer {
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
    }

    #[storage]
    struct Storage<Context> {
        admin: PublicMutable<AztecAddress, Context>,
        balances: Owned<BalanceSet<Context>, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        name: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
    }

    #[external("public")]
    #[initializer]
    fn constructor(admin: AztecAddress, name: str<31>, symbol: str<31>, decimals: u8) {
        assert(!admin.is_zero(), "invalid admin");
        self.storage.admin.write(admin);
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);
    }

    #[external("public")]
    fn set_admin(new_admin: AztecAddress) {
        assert(self.storage.admin.read().eq(self.msg_sender()), "caller is not admin");
        self.storage.admin.write(new_admin);
    }

    #[external("public")]
    #[view]
    fn public_get_name() -> FieldCompressedString {
        self.storage.name.read()
    }

    #[external("private")]
    #[view]
    fn private_get_name() -> FieldCompressedString {
        self.storage.name.read()
    }

    #[external("public")]
    #[view]
    fn public_get_symbol() -> pub FieldCompressedString {
        self.storage.symbol.read()
    }

    #[external("private")]
    #[view]
    fn private_get_symbol() -> pub FieldCompressedString {
        self.storage.symbol.read()
    }

    #[external("public")]
    #[view]
    fn public_get_decimals() -> pub u8 {
        self.storage.decimals.read()
    }

    #[external("private")]
    #[view]
    fn private_get_decimals() -> pub u8 {
        self.storage.decimals.read()
    }

    #[external("public")]
    #[view]
    fn get_admin() -> Field {
        self.storage.admin.read().to_field()
    }

    #[external("public")]
    #[view]
    fn total_supply() -> u128 {
        self.storage.total_supply.read()
    }

    #[external("public")]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> u128 {
        self.storage.public_balances.at(owner).read()
    }

    #[external("public")]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        // 1. check the caller is the minter
        assert(self.storage.admin.read().eq(self.msg_sender()), "caller is not minter");
        // 2. increase the balance of `to` and the total supply by `amount`
        let new_balance = self.storage.public_balances.at(to).read().add(amount);
        // 3. Increase the total supply by `amount`
        let supply = self.storage.total_supply.read().add(amount);
        // 4. Write the new balance and total supply to storage
        self.storage.public_balances.at(to).write(new_balance);
        // 5. Write the new total supply to storage
        self.storage.total_supply.write(supply);
    }

    #[authorize_once("from", "authwit_nonce")]
    #[external("public")]
    fn transfer_in_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        authwit_nonce: Field,
    ) {
        let from_balance = self.storage.public_balances.at(from).read().sub(amount);
        self.storage.public_balances.at(from).write(from_balance);
        let to_balance = self.storage.public_balances.at(to).read().add(amount);
        self.storage.public_balances.at(to).write(to_balance);
    }

    #[authorize_once("from", "authwit_nonce")]
    #[external("private")]
    fn transfer_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        authwit_nonce: Field,
    ) {
        // transfer from private to public
        self.storage.balances.at(from).sub(amount).deliver(MessageDelivery.ONCHAIN_CONSTRAINED);
        // enqueue a call to increase the public balance of `to` by `amount`. We enqueue the call instead of executing it directly because we want the transfer to be atomic, meaning that if the call to transfer fails for some reason (e.g. because of insufficient balance), the entire transaction should fail and the state should not be changed.
        self.enqueue_self._increase_public_balance(to, amount);
    }

    #[external("private")]
    fn transfer_in_private(to: AztecAddress, amount: u128) {
        let from = self.msg_sender();

        // We reduce `from`'s balance by amount by recursively removing notes over potentially multiple calls. This
        // method keeps the gate count for each individual call low - reading too many notes at once could result in
        // circuits in which proving is not feasible.
        // Since the sum of the amounts in the notes we nullified was potentially larger than amount, we create a new
        // note for `from` with the change amount, e.g. if `amount` is 10 and two notes are nullified with amounts 8 and
        // 5, then the change will be 3 (since 8 + 5 - 10 = 3).
        let change = self.internal.subtract_balance(from, amount, INITIAL_TRANSFER_CALL_MAX_NOTES);
        self.storage.balances.at(from).add(change).deliver(MessageDelivery.ONCHAIN_UNCONSTRAINED);
        self.storage.balances.at(to).add(amount).deliver(MessageDelivery.ONCHAIN_UNCONSTRAINED);

        // We don't constrain encryption of the note log in `transfer` (unlike in `transfer_in_private`) because the transfer
        // function is only designed to be used in situations where the event is not strictly necessary (e.g. payment to
        // another person where the payment is considered to be successful when the other party successfully decrypts a
        // note).
        self.emit(Transfer { from, to, amount }).deliver_to(
            to,
            MessageDelivery.ONCHAIN_UNCONSTRAINED,
        );
    }

    #[internal("private")]
    fn subtract_balance(account: AztecAddress, amount: u128, max_notes: u32) -> u128 {
        let subtracted = self.storage.balances.at(account).try_sub(amount, max_notes);
        // Failing to subtract any amount means that the owner was unable to produce more notes that could be nullified.
        // We could in some cases fail early inside try_sub if we detected that fewer notes than the maximum were
        // returned and we were still unable to reach the target amount, but that'd make the code more complicated, and
        // optimizing for the failure scenario is not as important.
        assert(subtracted > 0 as u128, "Balance too low");
        if subtracted >= amount {
            // We have achieved our goal of nullifying notes that add up to more than amount, so we return the change
            subtracted - amount
        } else {
            // try_sub failed to nullify enough notes to reach the target amount, so we compute the amount remaining
            // and try again.
            let remaining = amount - subtracted;
            compute_recurse_subtract_balance_call(*context, account, remaining).call(context)
        }
    }

    // TODO(#7729): apply no_predicates to the contract interface method directly instead of having to use a wrapper
    // like we do here.
    #[no_predicates]
    #[contract_library_method]
    fn compute_recurse_subtract_balance_call(
        context: PrivateContext,
        account: AztecAddress,
        remaining: u128,
    ) -> PrivateCall<25, 2, u128> {
        Token::at(context.this_address())._recurse_subtract_balance(account, remaining)
    }

    #[only_self]
    #[external("private")]
    fn _recurse_subtract_balance(account: AztecAddress, amount: u128) -> u128 {
        self.internal.subtract_balance(account, amount, RECURSIVE_TRANSFER_CALL_MAX_NOTES)
    }

    /**
     * Cancel a private authentication witness.
     * @param inner_hash The inner hash of the authwit to cancel.
     */
    #[external("private")]
    fn cancel_authwit(inner_hash: Field) {
        let on_behalf_of = self.msg_sender();
        let nullifier = compute_authwit_nullifier(on_behalf_of, inner_hash);
        self.context.push_nullifier(nullifier);
    }

    #[authorize_once("from", "authwit_nonce")]
    #[external("private")]
    fn transfer_from_in_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        authwit_nonce: Field,
    ) {
        self.storage.balances.at(from).sub(amount).deliver(MessageDelivery.ONCHAIN_CONSTRAINED);
        self.storage.balances.at(to).add(amount).deliver(MessageDelivery.ONCHAIN_CONSTRAINED);
    }

    // Transfers token `amount` from public balance of message sender to a private balance of `to`.
    #[external("private")]
    fn transfer_to_private(to: AztecAddress, amount: u128) {
        // `from` is the owner of the public balance from which we'll subtract the `amount`.
        let from = self.msg_sender();

        // We prepare the private balance increase (the partial note).
        let partial_note = self.internal._prepare_private_balance_increase(to);

        // At last we finalize the transfer. Usage of the `unsafe` method here is safe because we set the `from`
        // function argument to a message sender, guaranteeing that he can transfer only his own tokens.
        self.enqueue_self._finalize_transfer_to_private(from, amount, partial_note);
    }

    /// This function exists separately from `prepare_private_balance_increase` solely as an optimization as it allows
    /// us to have it inlined in the `transfer_to_private` function which results in one fewer kernel iteration. Note
    /// that in this case we don't pass `completer` as an argument to this function because in all the callsites we
    /// want to use the message sender as the completer anyway.
    // docs:start:prepare_private_balance_increase
    #[internal("private")]
    fn _prepare_private_balance_increase(to: AztecAddress) -> PartialUintNote {
        let partial_note = UintNote::partial(
            to,
            self.storage.balances.get_storage_slot(),
            self.context,
            to,
            self.msg_sender(),
        );

        partial_note
    }

    /// This is a wrapper around `_finalize_transfer_to_private` placed here so that a call
    /// to `_finalize_transfer_to_private` can be enqueued. Called unsafe as it does not check `from_and_completer`
    /// (this has to be done in the calling function).
    #[external("public")]
    #[only_self]
    fn _finalize_transfer_to_private(
        from_and_completer: AztecAddress,
        amount: u128,
        partial_note: PartialUintNote,
    ) {
        // First we subtract the `amount` from the public balance of `from_and_completer`
        let balance_storage = self.storage.public_balances.at(from_and_completer);

        let from_balance = balance_storage.read().sub(amount);
        balance_storage.write(from_balance);

        // We finalize the transfer by completing the partial note.
        partial_note.complete(self.context, from_and_completer, amount);
    }

    /// Mints token `amount` to a private balance of `to`. Message sender has to have minter permissions (checked
    /// in the enqueued call).
    #[external("private")]
    fn mint_to_private(to: AztecAddress, amount: u128) {
        // We prepare the partial note to which we'll "send" the minted amount.
        let partial_note = self.internal._prepare_private_balance_increase(to);

        // At last we finalize the mint. Usage of the `unsafe` method here is safe because we set
        // the `minter_and_completer` function argument to a message sender, guaranteeing that only a message sender
        // with minter permissions can successfully execute the function.
        self.enqueue_self._finalize_mint_to_private(self.msg_sender(), amount, partial_note);
    }

    #[external("public")]
    #[only_self]
    fn _finalize_mint_to_private(
        minter: AztecAddress,
        amount: u128,
        partial_note: PartialUintNote,
    ) {
        assert(self.storage.admin.read().eq(minter), "caller is not admin");

        let supply = self.storage.total_supply.read().add(amount);
        self.storage.total_supply.write(supply);

        partial_note.complete(self.context, minter, amount);
    }

    #[external("public")]
    #[only_self]
    fn _increase_public_balance(to: AztecAddress, amount: u128) {
        let to_balance = self.storage.public_balances.at(to);

        let new_balance = to_balance.read().add(amount);
        to_balance.write(new_balance);
    }

    #[external("public")]
    #[only_self]
    fn _reduce_total_supply(amount: u128) {
        // Only to be called from burn.
        let new_supply = self.storage.total_supply.read().sub(amount);
        self.storage.total_supply.write(new_supply);
    }

    #[external("utility")]
    unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        self.storage.balances.at(owner).balance_of()
    }
}
