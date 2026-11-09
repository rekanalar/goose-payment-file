// The model of the pain.001 credit transfer.
//
// The payments and the items live in flat arrays the caller owns. A
// payment holds the start and the count of its items, as the
// statements and entries of a bank statement do. The texts point at
// the input of the reader or at string literals of the caller, so
// they stay valid as long as those do.
namespace payment_file;

import std;
import finance from "rekanalar/goose-finance@v0.1.0";

// GrpHeader holds the facts of the group header.
struct GrpHeader {
    message_id: const u8[:],
    has_creation: bool,
    creation_year: i32,
    creation_month: i32,
    creation_day: i32,
    creation_minutes: i32,
    creation_offset: i32,
    count: i64,
    has_control_sum: bool,
    control_sum: i64,
    control_currency: const u8[:],
    initiator: const u8[:],
}

// PaymentInfo holds one payment information block. The items of the
// block are items[item_start .. item_start + item_count].
struct PaymentInfo {
    id: const u8[:],
    method: const u8[:],
    batch_booking: bool,
    has_batch_booking: bool,
    charge_bearer: const u8[:],
    debtor_name: const u8[:],
    debtor_iban: const u8[:],
    debtor_bic: const u8[:],
    execution_year: i32,
    execution_month: i32,
    execution_day: i32,
    has_execution_date: bool,
    item_start: i32,
    item_count: i32,
}

// CreditTransfer holds one credit transfer item. The structured
// remittance holds the creditor reference.
struct CreditTransfer {
    end_to_end_id: const u8[:],
    instruction_id: const u8[:],
    amount: finance::Money,
    creditor_name: const u8[:],
    creditor_iban: const u8[:],
    creditor_bic: const u8[:],
    purpose: const u8[:],
    remittance: const u8[:],
    structured_ref: const u8[:],
}

// no_date gives the zero date. A year of zero names a date the file
// holds not.
fn no_date() -> i32, i32, i32 {
    return 0, 0, 0;
}

// new_header gives a header with the zero values.
fn new_header() -> GrpHeader {
    return GrpHeader {
        message_id: "", has_creation: false, creation_year: 0, creation_month: 0,
        creation_day: 0, creation_minutes: 0, creation_offset: 0, count: 0,
        has_control_sum: false, control_sum: 0, control_currency: "", initiator: "",
    };
}

// new_payment gives a payment block with the zero values.
fn new_payment() -> PaymentInfo {
    return PaymentInfo {
        id: "", method: "", batch_booking: false, has_batch_booking: false, charge_bearer: "",
        debtor_name: "", debtor_iban: "", debtor_bic: "",
        execution_year: 0, execution_month: 0, execution_day: 0, has_execution_date: false,
        item_start: 0, item_count: 0,
    };
}

// new_transfer gives a credit transfer item with the zero values.
fn new_transfer() -> CreditTransfer {
    return CreditTransfer {
        end_to_end_id: "", instruction_id: "",
        amount: finance::Money { minor: 0, code: "" },
        creditor_name: "", creditor_iban: "", creditor_bic: "",
        purpose: "", remittance: "",
        structured_ref: "",
    };
}
