// The model of the NACHA ACH file.
//
// The batches, the entries and the addenda live in flat arrays the
// caller owns. A batch holds the start and the count of its entries.
// An entry holds the start and the count of its addenda. The texts
// point at the input of the reader or at string literals of the
// caller, so they stay valid as long as those do.
namespace payment_file;

import std;

// AchFileHeader holds the facts of the file header record. The
// routing number holds all nine digits with the check digit.
struct AchFileHeader {
    destination_routing: const u8[:],
    origin_id: const u8[:],
    creation_year: i32,
    creation_month: i32,
    creation_day: i32,
    creation_hour: i32,
    creation_minute: i32,
    id_modifier: const u8[:],
    destination_name: const u8[:],
    origin_name: const u8[:],
    reference: const u8[:],
}

// AchBatch holds one batch. The entries of the batch are
// entries[entry_start .. entry_start + entry_count].
struct AchBatch {
    service_class: i64,
    company_name: const u8[:],
    discretionary: const u8[:],
    company_id: const u8[:],
    sec_code: const u8[:],
    description: const u8[:],
    descriptive_date: const u8[:],
    effective_year: i32,
    effective_month: i32,
    effective_day: i32,
    originator_status: i64,
    odfi_id: const u8[:],
    batch_number: i64,
    entry_start: i32,
    entry_count: i32,
}

// AchEntry holds one entry detail record. The amount holds cents.
// The routing number holds all nine digits with the check digit. The
// addenda of the entry are addenda[addenda_start .. addenda_start +
// addenda_count].
struct AchEntry {
    transaction_code: i64,
    rdfi_routing: const u8[:],
    account: const u8[:],
    amount: i64,
    individual_id: const u8[:],
    individual_name: const u8[:],
    discretionary: const u8[:],
    trace_number: const u8[:],
    addenda_start: i32,
    addenda_count: i32,
}

// AchAddenda holds one addenda record of type 05: the payment
// related text.
struct AchAddenda {
    text: const u8[:],
}

// new_ach_file_header gives a file header with the zero values.
fn new_ach_file_header() -> AchFileHeader {
    return AchFileHeader {
        destination_routing: "", origin_id: "",
        creation_year: 0, creation_month: 0, creation_day: 0,
        creation_hour: 0, creation_minute: 0,
        id_modifier: "", destination_name: "", origin_name: "", reference: "",
    };
}

// new_ach_batch gives a batch with the zero values. The originator
// status holds the usual 1.
fn new_ach_batch() -> AchBatch {
    return AchBatch {
        service_class: 0, company_name: "", discretionary: "", company_id: "",
        sec_code: "", description: "", descriptive_date: "",
        effective_year: 0, effective_month: 0, effective_day: 0,
        originator_status: 1, odfi_id: "", batch_number: 0,
        entry_start: 0, entry_count: 0,
    };
}

// new_ach_entry gives an entry with the zero values.
fn new_ach_entry() -> AchEntry {
    return AchEntry {
        transaction_code: 0, rdfi_routing: "", account: "", amount: 0,
        individual_id: "", individual_name: "", discretionary: "",
        trace_number: "", addenda_start: 0, addenda_count: 0,
    };
}

// new_ach_addenda gives an addenda with the zero values.
fn new_ach_addenda() -> AchAddenda {
    return AchAddenda { text: "" };
}
