// The model of the NACHA ADV batch.
//
// An ADV batch is a batch of automated accounting advice. Its entry
// holds the advice fields. It has no trace number and no addenda.
//
// The batches and the entries live in flat arrays the caller owns, as
// the normal ACH model does. The texts point at the input of the
// reader or at string literals of the caller, so they stay valid as
// long as those do.
namespace payment_file;

import std;
import fault;

// AdvEntry holds one entry detail record of an ADV batch. The amount
// holds cents. The routing number holds all nine digits with the
// check digit. The sequence number counts the entries of the batch.
struct AdvEntry {
    transaction_code: i64,
    rdfi_routing: const u8[:],
    account: const u8[:],
    amount: i64,
    advice_routing_number: const u8[:],
    file_identification: const u8[:],
    ach_operator_data: const u8[:],
    individual_name: const u8[:],
    discretionary: const u8[:],
    addenda_indicator: i64,
    ach_operator_routing_number: const u8[:],
    julian_day: i64,
    sequence_number: i64,
}

// new_adv_entry gives an entry with the zero values.
fn new_adv_entry() -> AdvEntry {
    return AdvEntry {
        transaction_code: 0, rdfi_routing: "", account: "", amount: 0,
        advice_routing_number: "", file_identification: "",
        ach_operator_data: "", individual_name: "", discretionary: "",
        addenda_indicator: 0, ach_operator_routing_number: "",
        julian_day: 0, sequence_number: 0,
    };
}
