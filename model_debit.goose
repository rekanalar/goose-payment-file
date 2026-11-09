// The model of the pain.008 direct debit.
//
// The blocks and the items live in flat arrays the caller owns. A
// block holds the start and the count of its items. The texts point
// at the input of the reader or at string literals of the caller. The
// group header is the one of the credit transfer.
namespace payment_file;

import std;
import finance from "rekanalar/goose-finance@v0.1.0";
import model_party;

// DebitInfo holds one payment block of a direct debit. The items of
// the block are items[item_start .. item_start + item_count].
struct DebitInfo {
    id: const u8[:],
    batch_booking: bool,
    has_batch_booking: bool,
    creditor_name: const u8[:],
    creditor_detail: PartyDetail,
    creditor_iban: const u8[:],
    creditor_bic: const u8[:],
    ultimate_creditor_name: const u8[:],
    ultimate_creditor_detail: PartyDetail,
    scheme_id: const u8[:],
    charge_bearer: const u8[:],
    seq_type: const u8[:],
    instrument: const u8[:],
    collection_year: i32,
    collection_month: i32,
    collection_day: i32,
    has_collection_date: bool,
    item_start: i32,
    item_count: i32,
}

// DirectDebit holds one collection: the amount, the mandate and the
// debtor.
struct DirectDebit {
    end_to_end_id: const u8[:],
    amount: finance::Money,
    mandate_id: const u8[:],
    signature_year: i32,
    signature_month: i32,
    signature_day: i32,
    has_signature_date: bool,
    amendment: bool,
    has_amendment: bool,
    debtor_name: const u8[:],
    debtor_detail: PartyDetail,
    debtor_iban: const u8[:],
    debtor_bic: const u8[:],
    ultimate_creditor_name: const u8[:],
    ultimate_creditor_detail: PartyDetail,
    ultimate_debtor_name: const u8[:],
    ultimate_debtor_detail: PartyDetail,
    purpose: const u8[:],
    remittance: const u8[:],
    structured_type: const u8[:],
    structured_issuer: const u8[:],
    structured_ref: const u8[:],
}

// new_debit_info gives a block with the zero values.
fn new_debit_info() -> DebitInfo {
    return DebitInfo {
        id: "", batch_booking: false, has_batch_booking: false,
        creditor_name: "", creditor_detail: new_party_detail(),
        creditor_iban: "", creditor_bic: "",
        ultimate_creditor_name: "", ultimate_creditor_detail: new_party_detail(),
        scheme_id: "",
        charge_bearer: "", seq_type: "", instrument: "",
        collection_year: 0, collection_month: 0, collection_day: 0, has_collection_date: false,
        item_start: 0, item_count: 0,
    };
}

// new_direct_debit gives an item with the zero values.
fn new_direct_debit() -> DirectDebit {
    return DirectDebit {
        end_to_end_id: "", amount: finance::Money { minor: 0, code: "" },
        mandate_id: "", signature_year: 0, signature_month: 0, signature_day: 0,
        has_signature_date: false, amendment: false, has_amendment: false,
        debtor_name: "", debtor_detail: new_party_detail(),
        debtor_iban: "", debtor_bic: "",
        ultimate_creditor_name: "", ultimate_creditor_detail: new_party_detail(),
        ultimate_debtor_name: "", ultimate_debtor_detail: new_party_detail(),
        purpose: "", remittance: "",
        structured_type: "", structured_issuer: "", structured_ref: "",
    };
}
