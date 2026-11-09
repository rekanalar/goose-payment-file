// The model of the NACHA IAT batch and its addenda.
//
// An IAT batch is a batch of international entries. Its header holds
// the foreign exchange fields and the ISO codes. Its entry holds a
// longer account number and the two screening indicators. Its addenda
// are records of type 02 and 10 to 18, and every entry carries the
// seven mandatory records of types 10 to 16.
//
// The batches, the entries and the addenda live in flat arrays the
// caller owns, as the normal ACH model does. The texts point at the
// input of the reader or at string literals of the caller, so they
// stay valid as long as those do.
namespace payment_file;

import std;
import fault;
import finance;

// IatBatch holds one batch header of the SEC code IAT. The entries of
// the batch are entries[entry_start .. entry_start + entry_count].
struct IatBatch {
    service_class: i64,
    iat_indicator: const u8[:],
    fx_indicator: const u8[:],
    fx_ref_indicator: i64,
    fx_reference: const u8[:],
    dest_country: const u8[:],
    originator_id: const u8[:],
    description: const u8[:],
    origin_currency: const u8[:],
    dest_currency: const u8[:],
    effective_year: i32,
    effective_month: i32,
    effective_day: i32,
    settlement_date: const u8[:],
    originator_status: i64,
    odfi_id: const u8[:],
    batch_number: i64,
    entry_start: i32,
    entry_count: i32,
}

// IatEntry holds one entry detail record of an IAT batch. The amount
// holds cents. The routing number holds all nine digits with the
// check digit. The addenda of the entry are
// addenda[addenda_start .. addenda_start + addenda_count]. The count
// of addenda records and the trace number are computed values; the
// caller cannot set them.
struct IatEntry {
    transaction_code: i64,
    rdfi_routing: const u8[:],
    amount: i64,
    dfi_account: const u8[:],
    ofac_screening: const u8[:],
    ofac_secondary: const u8[:],
    trace_number: const u8[:],
    addenda_start: i32,
    addenda_count: i32,
}

// IatAddenda holds one addenda record of type 02 or 10 to 18. The
// fields a type does not use stay empty. Two records of type 17 carry
// no role marker; the order carries the role.
struct IatAddenda {
    kind: i64,
    ref_one: const u8[:],
    ref_two: const u8[:],
    terminal_id: const u8[:],
    serial: const u8[:],
    date_month: i32,
    date_day: i32,
    auth_code: const u8[:],
    location: const u8[:],
    city: const u8[:],
    state: const u8[:],
    txn_type_code: const u8[:],
    foreign_amount: i64,
    foreign_trace: const u8[:],
    name: const u8[:],
    street: const u8[:],
    city_state: const u8[:],
    country_postal: const u8[:],
    date_of_birth: const u8[:],
    id_qualifier: const u8[:],
    id_number: const u8[:],
    branch_country: const u8[:],
    receiver_id: const u8[:],
    payment_info: const u8[:],
    sequence: i64,
}

// new_iat_batch gives a batch with the zero values. The originator
// status holds the usual 1.
fn new_iat_batch() -> IatBatch {
    return IatBatch {
        service_class: 0, iat_indicator: "", fx_indicator: "",
        fx_ref_indicator: 0, fx_reference: "", dest_country: "",
        originator_id: "", description: "", origin_currency: "",
        dest_currency: "", effective_year: 0, effective_month: 0,
        effective_day: 0, settlement_date: "", originator_status: 1,
        odfi_id: "",
        batch_number: 0, entry_start: 0, entry_count: 0,
    };
}

// new_iat_entry gives an entry with the zero values.
fn new_iat_entry() -> IatEntry {
    return IatEntry {
        transaction_code: 0, rdfi_routing: "", amount: 0,
        dfi_account: "", ofac_screening: "", ofac_secondary: "",
        trace_number: "", addenda_start: 0, addenda_count: 0,
    };
}

// new_iat_addenda gives an addenda record of the kind. The kinds are
// 2 and 10 to 18.
fn new_iat_addenda(kind: i64) -> IatAddenda {
    var k = kind;
    if k != 2 && (k < 10 || k > 18) { k = 0; }
    return IatAddenda {
        kind: k, ref_one: "", ref_two: "", terminal_id: "",
        serial: "", date_month: 0, date_day: 0, auth_code: "",
        location: "", city: "", state: "", txn_type_code: "",
        foreign_amount: 0, foreign_trace: "", name: "", street: "",
        city_state: "", country_postal: "", date_of_birth: "",
        id_qualifier: "", id_number: "", branch_country: "",
        receiver_id: "", payment_info: "", sequence: 0,
    };
}

// iat_dob_ok tells whether a date of birth is a real date of the form
// YYYY-MM-DD. An empty field is allowed, because a corporate
// originator has no date of birth.
fn iat_dob_ok(text: const u8[:]) -> bool {
    if text.len == 0 { return true; }
    if text.len != 10 { return false; }
    if text[4] != '-' || text[7] != '-' { return false; }
    let y, ok1 = digits_value(text[0..4]);
    let m, ok2 = digits_value(text[5..7]);
    let d, ok3 = digits_value(text[8..10]);
    if !ok1 || !ok2 || !ok3 { return false; }
    return finance::date_ok(y, m, d);
}

// iat_addenda_order_ok checks the addenda of one IAT entry. The seven
// mandatory records of types 10 to 16 stand in order. One record of
// type 02 comes before them, records of types 17 and 18 follow them.
// An entry holds two records of type 17 at most.
fn iat_addenda_order_ok(addenda: IatAddenda[>..]&, start: i64, count: i64) -> Fault {
    if count <= 0 {
        return fault(F_SYNTAX, 0, 0, "7", "the IAT entry holds no addenda record");
    }
    var i = start;
    let end = start + count;
    if i < end && addenda[i].kind == 2 { i += 1; }
    var want: i64 = 10;
    while want <= 16 {
        if i >= end {
            return fault(F_SYNTAX, 0, 0, "7", "the IAT entry misses a mandatory addenda record");
        }
        if addenda[i].kind > want {
            return fault(F_SYNTAX, 0, 0, "7", "the IAT entry misses a mandatory addenda record");
        }
        if addenda[i].kind != want {
            return fault(F_UNKNOWN_TAG, 0, 0, "7", "the mandatory addenda records stand in the wrong order");
        }
        i += 1;
        want += 1;
    }
    var n17: i64 = 0;
    while i < end {
        let k = addenda[i].kind;
        if k == 17 {
            n17 += 1;
            if n17 > 2 {
                return fault(F_LIMIT, 0, 0, "7", "the entry holds more than two records of type 17");
            }
        } else if k != 18 {
            return fault(F_UNKNOWN_TAG, 0, 0, "7", "an addenda record stands after the mandatory records");
        }
        i += 1;
    }
    return no_fault();
}
