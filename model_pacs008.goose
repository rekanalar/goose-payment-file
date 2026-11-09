// The model of the pacs.008 customer credit transfer.
//
// The message holds one group header and a flat array of
// transactions. The texts point at the input of the reader or at
// string literals of the caller, so they stay valid as long as those
// do. The group header of the credit transfer is part of the header.
namespace payment_file;

import std;
import finance from "rekanalar/goose-finance@v0.1.0";
import model;

// Pacs008Header holds the facts of the group header. The base holds
// the message id, the creation time, the count and the control sum.
struct Pacs008Header {
    base: GrpHeader,
    settlement_method: const u8[:],
    has_settlement_date: bool,
    settle_year: i32,
    settle_month: i32,
    settle_day: i32,
    batch_booking: bool,
    has_batch_booking: bool,
    instructing_bic: const u8[:],
    instructed_bic: const u8[:],
}

// Pacs008Tx holds one credit transfer between two banks. An account
// holds an IBAN or one other id. An agent holds a BIC or one clearing
// system member id.
struct Pacs008Tx {
    instruction_id: const u8[:],
    end_to_end_id: const u8[:],
    transaction_id: const u8[:],
    uetr: const u8[:],
    amount: finance::Money,
    has_settlement_date: bool,
    settle_year: i32,
    settle_month: i32,
    settle_day: i32,
    charge_bearer: const u8[:],
    debtor_name: const u8[:],
    debtor_country: const u8[:],
    debtor_iban: const u8[:],
    debtor_other_id: const u8[:],
    debtor_bic: const u8[:],
    debtor_member_id: const u8[:],
    creditor_name: const u8[:],
    creditor_country: const u8[:],
    creditor_iban: const u8[:],
    creditor_other_id: const u8[:],
    creditor_bic: const u8[:],
    creditor_member_id: const u8[:],
    remittance: const u8[:],
}

// new_pacs008_header gives a header with the zero values.
fn new_pacs008_header() -> Pacs008Header {
    return Pacs008Header {
        base: new_header(), settlement_method: "", has_settlement_date: false,
        settle_year: 0, settle_month: 0, settle_day: 0,
        batch_booking: false, has_batch_booking: false,
        instructing_bic: "", instructed_bic: "",
    };
}

// new_pacs008_tx gives a transaction with the zero values.
fn new_pacs008_tx() -> Pacs008Tx {
    return Pacs008Tx {
        instruction_id: "", end_to_end_id: "", transaction_id: "", uetr: "",
        amount: finance::Money { minor: 0, code: "" },
        has_settlement_date: false, settle_year: 0, settle_month: 0, settle_day: 0,
        charge_bearer: "",
        debtor_name: "", debtor_country: "", debtor_iban: "", debtor_other_id: "",
        debtor_bic: "", debtor_member_id: "",
        creditor_name: "", creditor_country: "", creditor_iban: "", creditor_other_id: "",
        creditor_bic: "", creditor_member_id: "",
        remittance: "",
    };
}
