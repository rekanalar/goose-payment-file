// The reader of the NACHA ACH file.
//
// The reader splits the input into records of 94 columns in one
// linear pass, then walks the records in order: the file header, the
// batches, the file control. A batch is its header, its entries with
// their addenda, and its control. The reader checks every control
// record against the data: the counts, the entry hash, the debit
// total and the credit total. Records of nines after the file control
// are padding and are skipped.
namespace payment_file;

import std;
import finance from "rekanalar/goose-finance@v0.1.0";
import fault;
import model;
import model_ach;
import model_ach_iat;
import enums;
import charset;
import control;
import write_ach;
import write_ach_iat;

// AchOptions holds the switches of the reader. check_routing checks
// the check digit of every routing number. skip_total_check turns the
// checks of the control records off.
struct AchOptions {
    skip_total_check: bool,
    check_routing: bool,
}

// new_ach_options gives the strict options.
fn new_ach_options() -> AchOptions {
    return AchOptions { skip_total_check: false, check_routing: true };
}

// fld gives the columns from..to of a record, counted from one. The
// caller bounds the columns.
fn fld(rec: const u8[:], from: i64, to: i64) -> const u8[:] {
    return rec[from - 1..to];
}

// trim_r cuts the spaces on the right of a field.
fn trim_r(text: const u8[:]) -> const u8[:] {
    var end = text.len;
    while end > 0 && text[end - 1] == ' ' { end -= 1; }
    return text[0..end];
}

// num_fld reads a numeric field. Anything but digits is a fault.
fn num_fld(rec: const u8[:], from: i64, to: i64, line: i64, tag: const u8[:]) -> i64, Fault {
    let s = fld(rec, from, to);
    var v: i64 = 0;
    var i: i64 = 0;
    while i < s.len {
        let c = s[i];
        if c < '0' || c > '9' {
            return 0, fault(F_SYNTAX, line, from + i, tag, "the numeric field holds no digit");
        }
        v = v * 10 + (c - '0') as i64;
        i += 1;
    }
    return v, no_fault();
}

// txt_fld reads a text field, trims the spaces on the right and
// checks the printable ASCII set. Empty is allowed.
fn txt_fld(rec: const u8[:], from: i64, to: i64, line: i64, tag: const u8[:]) -> const u8[:], Fault {
    let t = trim_r(fld(rec, from, to));
    if !ascii_ok(t) {
        return "", fault(F_CHARSET, line, from, tag, "the text holds a byte outside printable ASCII");
    }
    return t, no_fault();
}

// date_fld reads a YYMMDD date into a full year, month and day.
fn date_fld(rec: const u8[:], from: i64, line: i64, tag: const u8[:]) -> i32, i32, i32, Fault {
    let v, f = num_fld(rec, from, from + 5, line, tag);
    if f.kind != F_NONE { return 0, 0, 0, f; }
    let yy = v / 10000;
    let m = v / 100 % 100;
    let d = v % 100;
    if !finance::date_ok(2000 + yy, m, d) {
        return 0, 0, 0, fault(F_DATE, line, from, tag, "the date is not a civil date");
    }
    return (2000 + yy) as i32, m as i32, d as i32, no_fault();
}

// num_text reads a number from a text. Anything but digits is a
// fault.
fn num_text(text: const u8[:]) -> i64, Fault {
    var v: i64 = 0;
    var i: i64 = 0;
    while i < text.len {
        let c = text[i];
        if c < '0' || c > '9' {
            return 0, fault(F_SYNTAX, 0, i + 1, "6", "the trace number tail holds no digit");
        }
        v = v * 10 + (c - '0') as i64;
        i += 1;
    }
    return v, no_fault();
}

// parse_ach_file_header reads record 1.
fn parse_ach_file_header(rec: const u8[:], line: i64, h: AchFileHeader&) -> Fault {
    let dr = fld(rec, 5, 13);
    if !ascii_ok(dr) {
        return fault(F_CHARSET, line, 5, "1", "the routing number holds a byte outside printable ASCII");
    }
    h.destination_routing = dr;
    let oid, f1 = txt_fld(rec, 14, 23, line, "1");
    if f1.kind != F_NONE { return f1; }
    h.origin_id = oid;
    let y, m, d, f2 = date_fld(rec, 24, line, "1");
    if f2.kind != F_NONE { return f2; }
    h.creation_year = y;
    h.creation_month = m;
    h.creation_day = d;
    let hh, f3 = num_fld(rec, 30, 31, line, "1");
    if f3.kind != F_NONE { return f3; }
    let mm, f4 = num_fld(rec, 32, 33, line, "1");
    if f4.kind != F_NONE { return f4; }
    if hh > 23 || mm > 59 {
        return fault(F_DATE, line, 30, "1", "the time is not a time of day");
    }
    h.creation_hour = hh as i32;
    h.creation_minute = mm as i32;
    h.id_modifier = fld(rec, 34, 34);
    let m0 = h.id_modifier[0];
    if !((m0 >= '0' && m0 <= '9') || (m0 >= 'A' && m0 <= 'Z') || (m0 >= 'a' && m0 <= 'z')) {
        return fault(F_SYNTAX, line, 34, "1", "the file id modifier is not one letter or digit");
    }
    let dn, f5 = txt_fld(rec, 41, 63, line, "1");
    if f5.kind != F_NONE { return f5; }
    h.destination_name = dn;
    let on, f6 = txt_fld(rec, 64, 86, line, "1");
    if f6.kind != F_NONE { return f6; }
    h.origin_name = on;
    let rf, f7 = txt_fld(rec, 87, 94, line, "1");
    if f7.kind != F_NONE { return f7; }
    h.reference = rf;
    return no_fault();
}

// parse_ach_batch_header reads record 5.
fn parse_ach_batch_header(rec: const u8[:], line: i64, b: AchBatch&) -> Fault {
    let sc, f0 = num_fld(rec, 2, 4, line, "5");
    if f0.kind != F_NONE { return f0; }
    if !service_class_ok(sc) {
        return fault(F_SYNTAX, line, 2, "5", "the service class is not 200, 220 or 225");
    }
    b.service_class = sc;
    let cn, f1 = txt_fld(rec, 5, 20, line, "5");
    if f1.kind != F_NONE { return f1; }
    b.company_name = cn;
    let dd, f2 = txt_fld(rec, 21, 40, line, "5");
    if f2.kind != F_NONE { return f2; }
    b.discretionary = dd;
    let ci, f3 = txt_fld(rec, 41, 50, line, "5");
    if f3.kind != F_NONE { return f3; }
    b.company_id = ci;
    let sec = fld(rec, 51, 53);
    if !sec_ok(sec) {
        return fault(F_SYNTAX, line, 51, "5", "the SEC code is not one of the codes of the package");
    }
    b.sec_code = sec;
    let de, f4 = txt_fld(rec, 54, 63, line, "5");
    if f4.kind != F_NONE { return f4; }
    b.description = de;
    let ds, f5 = txt_fld(rec, 64, 69, line, "5");
    if f5.kind != F_NONE { return f5; }
    b.descriptive_date = ds;
    let y, m, d, f6 = date_fld(rec, 70, line, "5");
    if f6.kind != F_NONE { return f6; }
    b.effective_year = y;
    b.effective_month = m;
    b.effective_day = d;
    let os, f7 = num_fld(rec, 79, 79, line, "5");
    if f7.kind != F_NONE { return f7; }
    if os > 2 {
        return fault(F_SYNTAX, line, 79, "5", "the originator status is not 0, 1 or 2");
    }
    b.originator_status = os;
    let odfi = fld(rec, 80, 87);
    if !ascii_ok(odfi) {
        return fault(F_CHARSET, line, 80, "5", "the ODFI id holds a byte outside printable ASCII");
    }
    if !digits_ok(odfi) {
        return fault(F_SYNTAX, line, 80, "5", "the ODFI id is not 8 digits");
    }
    b.odfi_id = odfi;
    let bn, f9 = num_fld(rec, 88, 94, line, "5");
    if f9.kind != F_NONE { return f9; }
    if bn < 1 {
        return fault(F_SYNTAX, line, 88, "5", "the batch number is below 1");
    }
    b.batch_number = bn;
    return no_fault();
}

// parse_ach_entry reads record 6. The addenda range is set by the
// caller, one addendum at a time.
fn parse_ach_entry(rec: const u8[:], line: i64, e: AchEntry&) -> Fault {
    let tc, f0 = num_fld(rec, 2, 3, line, "6");
    if f0.kind != F_NONE { return f0; }
    if !ach_code_ok(tc) {
        return fault(F_SYNTAX, line, 2, "6", "the transaction code is not in the NACHA set");
    }
    e.transaction_code = tc;
    let r = fld(rec, 4, 12);
    if !ascii_ok(r) {
        return fault(F_CHARSET, line, 4, "6", "the routing number holds a byte outside printable ASCII");
    }
    e.rdfi_routing = r;
    let ac, f1 = txt_fld(rec, 13, 29, line, "6");
    if f1.kind != F_NONE { return f1; }
    e.account = ac;
    let am, f2 = num_fld(rec, 30, 39, line, "6");
    if f2.kind != F_NONE { return f2; }
    e.amount = am;
    let iid, f3 = txt_fld(rec, 40, 54, line, "6");
    if f3.kind != F_NONE { return f3; }
    e.individual_id = iid;
    let nm, f4 = txt_fld(rec, 55, 76, line, "6");
    if f4.kind != F_NONE { return f4; }
    e.individual_name = nm;
    let disc, f5 = txt_fld(rec, 77, 78, line, "6");
    if f5.kind != F_NONE { return f5; }
    e.discretionary = disc;
    let ind, f6 = num_fld(rec, 79, 79, line, "6");
    if f6.kind != F_NONE { return f6; }
    if ind > 1 {
        return fault(F_SYNTAX, line, 79, "6", "the addenda indicator is not 0 or 1");
    }
    e.addenda_start = 0;
    e.addenda_count = 0;
    let tn = fld(rec, 80, 94);
    if !ascii_ok(tn) {
        return fault(F_CHARSET, line, 80, "6", "the trace number holds a byte outside printable ASCII");
    }
    if !digits_ok(tn) {
        return fault(F_SYNTAX, line, 80, "6", "the trace number holds a byte that is no digit");
    }
    e.trace_number = tn;
    return no_fault();
}

// parse_ach_addenda reads record 7. The caller checks the sequence
// and the entry sequence.
fn parse_ach_addenda(rec: const u8[:], line: i64, a: AchAddenda&) -> Fault {
    let tc = fld(rec, 2, 3);
    if tc != "05" {
        return fault(F_UNKNOWN_TAG, line, 2, "7", "the addenda type is not 05");
    }
    let t, f = txt_fld(rec, 4, 83, line, "7");
    if f.kind != F_NONE { return f; }
    a.text = t;
    return no_fault();
}

// digits_width tells whether a text of the given width holds digits
// only. The reader checks the digit fields of the notice and the
// return with it.
fn digits_width(text: const u8[:], width: i64) -> bool {
    return text.len == width && digits_ok(text);
}

// parse_iat_batch_header reads record 5 of the SEC code IAT.
fn parse_iat_batch_header(rec: const u8[:], line: i64, b: IatBatch&) -> Fault {
    let sc, f0 = num_fld(rec, 2, 4, line, "5");
    if f0.kind != F_NONE { return f0; }
    if !service_class_ok(sc) {
        return fault(F_SYNTAX, line, 2, "5", "the service class is not 200, 220 or 225");
    }
    b.service_class = sc;
    let ind, f1 = txt_fld(rec, 5, 20, line, "5");
    if f1.kind != F_NONE { return f1; }
    b.iat_indicator = ind;
    let fx = fld(rec, 21, 22);
    if !fx_indicator_ok(fx) {
        return fault(F_SYNTAX, line, 21, "5", "the foreign exchange indicator is not FV, VF or FF");
    }
    b.fx_indicator = fx;
    let fri, f2 = num_fld(rec, 23, 23, line, "5");
    if f2.kind != F_NONE { return f2; }
    if fri < 1 || fri > 3 {
        return fault(F_SYNTAX, line, 23, "5", "the foreign exchange reference indicator is not 1, 2 or 3");
    }
    b.fx_ref_indicator = fri;
    let fxr, f3 = txt_fld(rec, 24, 38, line, "5");
    if f3.kind != F_NONE { return f3; }
    b.fx_reference = fxr;
    let dc = fld(rec, 39, 40);
    if !country_ok(dc) {
        return fault(F_SYNTAX, line, 39, "5", "the destination country is not two capital letters");
    }
    b.dest_country = dc;
    let oid, f4 = txt_fld(rec, 41, 50, line, "5");
    if f4.kind != F_NONE { return f4; }
    b.originator_id = oid;
    let de, f5 = txt_fld(rec, 54, 63, line, "5");
    if f5.kind != F_NONE { return f5; }
    b.description = de;
    let oc = fld(rec, 64, 66);
    if !currency_code_ok(oc) {
        return fault(F_SYNTAX, line, 64, "5", "the originating currency is not three capital letters");
    }
    b.origin_currency = oc;
    let dcu = fld(rec, 67, 69);
    if !currency_code_ok(dcu) {
        return fault(F_SYNTAX, line, 67, "5", "the destination currency is not three capital letters");
    }
    b.dest_currency = dcu;
    let y, m, d, f6 = date_fld(rec, 70, line, "5");
    if f6.kind != F_NONE { return f6; }
    b.effective_year = y;
    b.effective_month = m;
    b.effective_day = d;
    let sd, f7 = txt_fld(rec, 76, 78, line, "5");
    if f7.kind != F_NONE { return f7; }
    b.settlement_date = sd;
    let os, f8 = num_fld(rec, 79, 79, line, "5");
    if f8.kind != F_NONE { return f8; }
    if os > 2 {
        return fault(F_SYNTAX, line, 79, "5", "the originator status is not 0, 1 or 2");
    }
    b.originator_status = os;
    let odfi = fld(rec, 80, 87);
    if !digits_ok(odfi) {
        return fault(F_SYNTAX, line, 80, "5", "the ODFI id is not 8 digits");
    }
    b.odfi_id = odfi;
    let bn, f9 = num_fld(rec, 88, 94, line, "5");
    if f9.kind != F_NONE { return f9; }
    if bn < 1 {
        return fault(F_SYNTAX, line, 88, "5", "the batch number is below 1");
    }
    b.batch_number = bn;
    return no_fault();
}

// parse_iat_entry reads record 6 of an IAT batch. It gives the count of
// addenda records that the entry declares. The addenda range is set by
// the caller.
fn parse_iat_entry(rec: const u8[:], line: i64, e: IatEntry&) -> i64, Fault {
    let tc, f0 = num_fld(rec, 2, 3, line, "6");
    if f0.kind != F_NONE { return 0, f0; }
    if !ach_code_ok(tc) {
        return 0, fault(F_SYNTAX, line, 2, "6", "the transaction code is not in the NACHA set");
    }
    e.transaction_code = tc;
    e.rdfi_routing = fld(rec, 4, 12);
    let declared, f1 = num_fld(rec, 13, 16, line, "6");
    if f1.kind != F_NONE { return 0, f1; }
    let am, f2 = num_fld(rec, 30, 39, line, "6");
    if f2.kind != F_NONE { return 0, f2; }
    e.amount = am;
    let ac, f3 = txt_fld(rec, 40, 74, line, "6");
    if f3.kind != F_NONE { return 0, f3; }
    e.dfi_account = ac;
    let o1, f4 = txt_fld(rec, 77, 77, line, "6");
    if f4.kind != F_NONE { return 0, f4; }
    e.ofac_screening = o1;
    let o2, f5 = txt_fld(rec, 78, 78, line, "6");
    if f5.kind != F_NONE { return 0, f5; }
    e.ofac_secondary = o2;
    let ind, f6 = num_fld(rec, 79, 79, line, "6");
    if f6.kind != F_NONE { return 0, f6; }
    if ind > 1 {
        return 0, fault(F_SYNTAX, line, 79, "6", "the addenda indicator is not 0 or 1");
    }
    let tn = fld(rec, 80, 94);
    if !digits_ok(tn) {
        return 0, fault(F_SYNTAX, line, 80, "6", "the trace number holds a byte that is no digit");
    }
    e.trace_number = tn;
    e.addenda_start = 0;
    e.addenda_count = 0;
    return declared, no_fault();
}

// check_entry_seq checks the entry sequence at columns 88 to 94 of an
// addenda record. It is the tail of the trace number of the entry.
fn check_entry_seq(rec: const u8[:], line: i64, trace_number: const u8[:]) -> Fault {
    let es, f = num_fld(rec, 88, 94, line, "7");
    if f.kind != F_NONE { return f; }
    let ts, tf = num_text(trace_number[8..15]);
    if tf.kind != F_NONE { return tf; }
    if es != ts {
        return fault(F_TOTAL, line, 88, "7", "the entry sequence is not the tail of the trace number");
    }
    return no_fault();
}

// parse_iat_addenda reads record 7 of type 02 or 10 to 18 into the
// union record. It checks the widths of the layout of the type and the
// entry sequence against the trace number of the entry.
fn parse_iat_addenda(rec: const u8[:], line: i64, trace_number: const u8[:], a: IatAddenda&) -> Fault {
    let tc, f0 = num_fld(rec, 2, 3, line, "7");
    if f0.kind != F_NONE { return f0; }
    if tc == 2 {
        a.kind = 2;
        let r1, g1 = txt_fld(rec, 4, 10, line, "7");
        if g1.kind != F_NONE { return g1; }
        a.ref_one = r1;
        let r2, g2 = txt_fld(rec, 11, 13, line, "7");
        if g2.kind != F_NONE { return g2; }
        a.ref_two = r2;
        let ti, g3 = txt_fld(rec, 14, 19, line, "7");
        if g3.kind != F_NONE { return g3; }
        a.terminal_id = ti;
        let se, g4 = txt_fld(rec, 20, 25, line, "7");
        if g4.kind != F_NONE { return g4; }
        a.serial = se;
        let mo, g5 = num_fld(rec, 26, 27, line, "7");
        if g5.kind != F_NONE { return g5; }
        let da, g6 = num_fld(rec, 28, 29, line, "7");
        if g6.kind != F_NONE { return g6; }
        a.date_month = mo as i32;
        a.date_day = da as i32;
        let au, g7 = txt_fld(rec, 30, 35, line, "7");
        if g7.kind != F_NONE { return g7; }
        a.auth_code = au;
        let lo, g8 = txt_fld(rec, 36, 62, line, "7");
        if g8.kind != F_NONE { return g8; }
        a.location = lo;
        let ci, g9 = txt_fld(rec, 63, 77, line, "7");
        if g9.kind != F_NONE { return g9; }
        a.city = ci;
        let st, g10 = txt_fld(rec, 78, 79, line, "7");
        if g10.kind != F_NONE { return g10; }
        a.state = st;
        if fld(rec, 80, 94) != trace_number {
            return fault(F_TOTAL, line, 80, "7", "the trace number of the addenda differs from the entry");
        }
        return no_fault();
    }
    if tc < 10 || tc > 18 {
        return fault(F_UNKNOWN_TAG, line, 2, "7", "the IAT addenda type is not 02 or 10 to 18");
    }
    a.kind = tc;
    if tc == 10 {
        let tt, g1 = txt_fld(rec, 4, 6, line, "7");
        if g1.kind != F_NONE { return g1; }
        if !txn_type_code_ok(tt) {
            return fault(F_SYNTAX, line, 4, "7", "the transaction type code is not in the list");
        }
        a.txn_type_code = tt;
        let fa, g2 = num_fld(rec, 7, 24, line, "7");
        if g2.kind != F_NONE { return g2; }
        a.foreign_amount = fa;
        let ft, g3 = txt_fld(rec, 25, 46, line, "7");
        if g3.kind != F_NONE { return g3; }
        a.foreign_trace = ft;
        let nm, g4 = txt_fld(rec, 47, 81, line, "7");
        if g4.kind != F_NONE { return g4; }
        a.name = nm;
    } else if tc == 11 {
        let nm, g1 = txt_fld(rec, 4, 38, line, "7");
        if g1.kind != F_NONE { return g1; }
        a.name = nm;
        let st, g2 = txt_fld(rec, 39, 73, line, "7");
        if g2.kind != F_NONE { return g2; }
        a.street = st;
    } else if tc == 12 || tc == 16 {
        let cs, g1 = txt_fld(rec, 4, 38, line, "7");
        if g1.kind != F_NONE { return g1; }
        a.city_state = cs;
        let cp, g2 = txt_fld(rec, 39, 73, line, "7");
        if g2.kind != F_NONE { return g2; }
        a.country_postal = cp;
        let db, g3 = txt_fld(rec, 74, 83, line, "7");
        if g3.kind != F_NONE { return g3; }
        if !iat_dob_ok(db) {
            return fault(F_DATE, line, 74, "7", "the date of birth is not YYYY-MM-DD");
        }
        a.date_of_birth = db;
    } else if tc == 13 || tc == 14 || tc == 18 {
        let nm, g1 = txt_fld(rec, 4, 38, line, "7");
        if g1.kind != F_NONE { return g1; }
        a.name = nm;
        let qu, g2 = txt_fld(rec, 39, 40, line, "7");
        if g2.kind != F_NONE { return g2; }
        a.id_qualifier = qu;
        let idn, g3 = txt_fld(rec, 41, 74, line, "7");
        if g3.kind != F_NONE { return g3; }
        a.id_number = idn;
        let bc, g4 = txt_fld(rec, 75, 77, line, "7");
        if g4.kind != F_NONE { return g4; }
        if !branch_country_ok(bc) {
            return fault(F_SYNTAX, line, 75, "7", "the branch country is not two or three capital letters or digits");
        }
        a.branch_country = bc;
    } else if tc == 15 {
        let ri, g1 = txt_fld(rec, 4, 18, line, "7");
        if g1.kind != F_NONE { return g1; }
        a.receiver_id = ri;
        let st, g2 = txt_fld(rec, 19, 53, line, "7");
        if g2.kind != F_NONE { return g2; }
        a.street = st;
    } else {
        let pi, g1 = txt_fld(rec, 4, 83, line, "7");
        if g1.kind != F_NONE { return g1; }
        a.payment_info = pi;
    }
    if tc == 17 || tc == 18 {
        let sq, g5 = num_fld(rec, 84, 87, line, "7");
        if g5.kind != F_NONE { return g5; }
        a.sequence = sq;
    }
    return check_entry_seq(rec, line, trace_number);
}

// parse_ach_notice reads record 7 of type 98 or 99 of a normal batch:
// a notice of change or a return. The trace number at columns 80 to 94
// is the trace number of the entry.
fn parse_ach_notice(rec: const u8[:], line: i64, trace_number: const u8[:], a: AchAddenda&) -> Fault {
    let tc = fld(rec, 2, 3);
    let code = fld(rec, 4, 6);
    let otr = fld(rec, 7, 21);
    if !digits_width(otr, 15) {
        return fault(F_SYNTAX, line, 7, "7", "the original trace number is not 15 digits");
    }
    a.original_trace = otr;
    let odfi = fld(rec, 28, 35);
    if !digits_width(odfi, 8) {
        return fault(F_SYNTAX, line, 28, "7", "the original DFI number is not 8 digits");
    }
    a.original_dfi = odfi;
    if fld(rec, 80, 94) != trace_number {
        return fault(F_TOTAL, line, 80, "7", "the trace number of the addenda differs from the entry");
    }
    if tc == "98" {
        if !noc_code_ok(code) {
            return fault(F_SYNTAX, line, 4, "7", "the change code is not in the notice list");
        }
        a.kind = 98;
        a.change_code = code;
        let cd, f = txt_fld(rec, 36, 64, line, "7");
        if f.kind != F_NONE { return f; }
        a.corrected_data = cd;
        return no_fault();
    }
    if !return_code_ok(code) {
        return fault(F_SYNTAX, line, 4, "7", "the return code is not in the return reason list");
    }
    a.kind = 99;
    a.return_code = code;
    if trim_r(fld(rec, 22, 27)).len > 0 {
        let y, m, d, df = date_fld(rec, 22, line, "7");
        if df.kind != F_NONE { return df; }
        a.death_year = y;
        a.death_month = m;
        a.death_day = d;
    }
    let ai, f2 = txt_fld(rec, 36, 79, line, "7");
    if f2.kind != F_NONE { return f2; }
    a.addenda_information = ai;
    return no_fault();
}

// IatState holds the batch, the entry and the counters that the reader
// keeps while it walks the records of an IAT batch.
struct IatState {
    batch: IatBatch,
    entry: IatEntry,
    has_entry: bool,
    declared: i64,
    indicator: i64,
    n17: i64,
    n18: i64,
}

// new_iat_state gives the state of a reader with no batch open.
fn new_iat_state() -> IatState {
    return IatState {
        batch: new_iat_batch(), entry: new_iat_entry(), has_entry: false,
        declared: 0, indicator: 0, n17: 0, n18: 0,
    };
}

// iat_finish_entry checks the entry that the reader holds. The caller
// has pushed the entry into the array already. The count of addenda
// records that the entry declares must equal the records that follow
// it, and the mandatory records must stand in order.
fn iat_finish_entry(st: IatState&, ia: IatAddenda[>..]&, line: i64) -> Fault {
    if st.declared != st.entry.addenda_count as i64 {
        return fault_sums(F_TOTAL, line, "6", "the count of addenda records differs from the records that follow",
                          st.entry.addenda_count as i64, st.declared);
    }
    if st.indicator != 1 {
        return fault(F_TOTAL, line, 79, "6", "the IAT entry declares no addendum");
    }
    let of = iat_addenda_order_ok(ia, st.entry.addenda_start as i64, st.entry.addenda_count as i64);
    if of.kind != F_NONE { return fault(of.kind, line, 1, of.tag, of.detail); }
    st.batch.entry_count += 1;
    st.has_entry = false;
    return no_fault();
}

// iat_open_batch reads a batch header of the SEC code IAT.
fn iat_open_batch(rec: const u8[:], line: i64, st: IatState&, entry_len: i64) -> Fault {
    st.batch = new_iat_batch();
    let f = parse_iat_batch_header(rec, line, st.batch);
    if f.kind != F_NONE { return f; }
    st.batch.entry_start = entry_len as i32;
    st.batch.entry_count = 0;
    st.has_entry = false;
    return no_fault();
}

// iat_entry_record reads an entry of an IAT batch and applies the
// checks of the normal entry: the routing check digit, the service
// class, the zero amount rule and the trace number rules.
fn iat_entry_record(rec: const u8[:], line: i64, st: IatState&, ie: IatEntry[>..]&,
                    ia: IatAddenda[>..]&, opts: AchOptions, lim: Limits&) -> Fault {
    if st.has_entry {
        let ff = iat_finish_entry(st, ia, line - 1);
        if ff.kind != F_NONE { return ff; }
    }
    if ie.len >= lim.max_entries {
        return fault(F_LIMIT, line, 1, "6", "more entries than the limits allow");
    }
    var e: IatEntry = new_iat_entry();
    let declared, pf = parse_iat_entry(rec, line, e);
    if pf.kind != F_NONE { return pf; }
    if opts.check_routing && !routing_ok(e.rdfi_routing) {
        return fault(F_SYNTAX, line, 4, "6", "the routing number does not pass the check digit");
    }
    let df = service_class_fault(st.batch.service_class, e.transaction_code);
    if df.kind != F_NONE { return fault(df.kind, line, 2, "6", df.detail); }
    if ach_zero_amount_code(e.transaction_code) && e.amount != 0 {
        return fault(F_AMOUNT, line, 30, "6", "a prenote or a zero dollar entry holds an amount");
    }
    if st.batch.entry_count > 0 && !trace_after(e.trace_number, ie[ie.len - 1].trace_number) {
        return fault(F_TOTAL, line, 80, "6", "the trace numbers of the batch do not ascend");
    }
    if e.trace_number[0..8] != st.batch.odfi_id {
        return fault(F_TOTAL, line, 80, "6", "the trace number does not start with the ODFI id");
    }
    e.addenda_start = ia.len as i32;
    st.entry = e;
    st.declared = declared;
    st.indicator = (rec[78] - '0') as i64;
    st.has_entry = true;
    st.n17 = 0;
    st.n18 = 0;
    return no_fault();
}

// iat_addenda_record reads an addenda record of an IAT batch and
// checks the sequence of the types 17 and 18.
fn iat_addenda_record(rec: const u8[:], line: i64, st: IatState&, ia: IatAddenda[>..]&,
                      lim: Limits&) -> Fault {
    if !st.has_entry {
        return fault(F_UNKNOWN_TAG, line, 1, "7", "an addendum sits before the first entry");
    }
    if ia.len >= lim.max_addenda {
        return fault(F_LIMIT, line, 1, "7", "more addenda than the limits allow");
    }
    var a: IatAddenda = new_iat_addenda(0);
    let af = parse_iat_addenda(rec, line, st.entry.trace_number, a);
    if af.kind != F_NONE { return af; }
    if a.kind == 17 {
        st.n17 += 1;
        if a.sequence != st.n17 {
            return fault(F_TOTAL, line, 84, "7", "the sequence of the type 17 records does not count from one");
        }
    }
    if a.kind == 18 {
        st.n18 += 1;
        if a.sequence != st.n18 {
            return fault(F_TOTAL, line, 84, "7", "the sequence of the type 18 records does not count from one");
        }
    }
    ia.push(a);
    st.entry.addenda_count += 1;
    return no_fault();
}

// iat_close_batch reads the control record of an IAT batch. It checks
// the control against the header and against the entries, and it gives
// the count, the hash, the debit total and the credit total. The caller
// has pushed the last entry already and pushes the batch after the
// call.
fn iat_close_batch(rec: const u8[:], line: i64, st: IatState&, ie: IatEntry[>..]&,
                   ia: IatAddenda[>..]&, opts: AchOptions) -> i64, i64, i64, i64, Fault {
    if !st.has_entry {
        return 0, 0, 0, 0, fault(F_SYNTAX, line, 1, "8", "the batch holds no entry");
    }
    let ff = iat_finish_entry(st, ia, line - 1);
    if ff.kind != F_NONE { return 0, 0, 0, 0, ff; }
    let csc, c0 = num_fld(rec, 2, 4, line, "8");
    if c0.kind != F_NONE { return 0, 0, 0, 0, c0; }
    if csc != st.batch.service_class {
        return 0, 0, 0, 0, fault(F_TOTAL, line, 2, "8", "the service class of the control differs from the header");
    }
    let cid, c1 = txt_fld(rec, 45, 54, line, "8");
    if c1.kind != F_NONE { return 0, 0, 0, 0, c1; }
    if cid != st.batch.originator_id {
        return 0, 0, 0, 0, fault(F_TOTAL, line, 45, "8", "the originator id of the control differs from the header");
    }
    let cod, c2 = txt_fld(rec, 80, 87, line, "8");
    if c2.kind != F_NONE { return 0, 0, 0, 0, c2; }
    if cod != st.batch.odfi_id {
        return 0, 0, 0, 0, fault(F_TOTAL, line, 80, "8", "the ODFI id of the control differs from the header");
    }
    let cbn, c3 = num_fld(rec, 88, 94, line, "8");
    if c3.kind != F_NONE { return 0, 0, 0, 0, c3; }
    if cbn != st.batch.batch_number {
        return 0, 0, 0, 0, fault(F_TOTAL, line, 88, "8", "the batch number of the control differs from the header");
    }
    let count, hash, debit, credit = batch_totals(st.batch, ie);
    let ccn, c4 = num_fld(rec, 5, 10, line, "8");
    if c4.kind != F_NONE { return 0, 0, 0, 0, c4; }
    let chc, c5 = num_fld(rec, 11, 20, line, "8");
    if c5.kind != F_NONE { return 0, 0, 0, 0, c5; }
    let cdb, c6 = num_fld(rec, 21, 32, line, "8");
    if c6.kind != F_NONE { return 0, 0, 0, 0, c6; }
    let ccr, c7 = num_fld(rec, 33, 44, line, "8");
    if c7.kind != F_NONE { return 0, 0, 0, 0, c7; }
    if !opts.skip_total_check {
        if ccn != count {
            return 0, 0, 0, 0, fault_sums(F_TOTAL, line, "8", "the entry count of the control differs", ccn, count);
        }
        if chc != hash {
            return 0, 0, 0, 0, fault_sums(F_TOTAL, line, "8", "the entry hash of the control differs", chc, hash);
        }
        if cdb != debit {
            return 0, 0, 0, 0, fault_sums(F_TOTAL, line, "8", "the debit total of the control differs", cdb, debit);
        }
        if ccr != credit {
            return 0, 0, 0, 0, fault_sums(F_TOTAL, line, "8", "the credit total of the control differs", ccr, credit);
        }
    }
    return count, hash, debit, credit, no_fault();
}

// is_nines tells whether the record holds nothing but nines.
fn is_nines(rec: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < rec.len {
        if rec[i] != '9' { return false; }
        i += 1;
    }
    return true;
}

// skip_line_end moves i over the line end of a record. The file may
// end without one.
fn skip_line_end(input: const u8[:], i: i64) -> i64, Fault {
    if i >= input.len { return i, no_fault(); }
    var j = i;
    if input[j] == '\r' {
        j += 1;
        if j >= input.len || input[j] != '\n' {
            return 0, fault(F_LIMIT, 0, 95, "9", "the record end holds a lone carriage return");
        }
        j += 1;
        return j, no_fault();
    }
    if input[j] == '\n' { return j + 1, no_fault(); }
    return 0, fault(F_LIMIT, 0, 95, "9", "the record end is missing");
}

// parse_ach reads a whole NACHA file of normal batches into the model.
// A file that holds an IAT batch is a fault: the caller reads it with
// parse_ach_iat. After a fault the arrays hold partial results; do not
// use them.
fn parse_ach(input: const u8[:], opts: AchOptions, lim: Limits&, h: AchFileHeader&,
             batches: AchBatch[>..]&, entries: AchEntry[>..]&, addenda: AchAddenda[>..]&) -> Fault {
    var ib: IatBatch[>..] = [];
    var ie: IatEntry[>..] = [];
    var ia: IatAddenda[>..] = [];
    let f = parse_ach_iat(input, opts, lim, h, batches, entries, addenda, ib, ie, ia);
    if f.kind != F_NONE { return f; }
    if ib.len > 0 {
        return fault(F_UNKNOWN_TAG, 0, 0, "5", "the file holds an IAT batch; read it with parse_ach_iat");
    }
    return no_fault();
}

// parse_ach_iat reads a whole NACHA file into the model. The normal
// batches go into the first three arrays and the IAT batches into the
// last three. The file control covers both kinds. After a fault the
// arrays hold partial results; do not use them.
fn parse_ach_iat(input: const u8[:], opts: AchOptions, lim: Limits&, h: AchFileHeader&,
                 batches: AchBatch[>..]&, entries: AchEntry[>..]&, addenda: AchAddenda[>..]&,
                 ib: IatBatch[>..]&, ie: IatEntry[>..]&, ia: IatAddenda[>..]&) -> Fault {
    if input.len > lim.max_input {
        return fault(F_LIMIT, 0, 0, "9", "the input is longer than the limits allow");
    }
    var i: i64 = 0;
    var line: i64 = 1;
    var saw_header: bool = false;
    var saw_control: bool = false;
    var open: bool = false;
    var batch: AchBatch = new_ach_batch();
    var iat: IatState = new_iat_state();
    var iat_mode: bool = false;
    var entry: AchEntry = new_ach_entry();
    var has_entry: bool = false;
    var entry_indicator: i64 = 0;
    var addenda_seq: i64 = 0;
    var file_count: i64 = 0;
    var file_hash: i64 = 0;
    var file_debit: i64 = 0;
    var file_credit: i64 = 0;
    var records: i64 = 0;
    while i < input.len {
        let rest = input.len - i;
        if rest < 94 {
            return fault(F_LIMIT, line, rest + 1, "9", "the last record is shorter than 94 columns");
        }
        let rec = input[i..i + 94];
        if rec[0] == '9' && is_nines(rec) {
            if !saw_control {
                return fault(F_UNKNOWN_TAG, line, 1, "9", "a record of nines sits before the file control");
            }
            let j, ef = skip_line_end(input, i + 94);
            if ef.kind != F_NONE { return ef; }
            i = j;
            line += 1;
            continue;
        }
        if !ascii_ok(rec) {
            return fault(F_CHARSET, line, 1, "9", "the record holds a byte outside printable ASCII");
        }
        let kind = rec[0];
        if !saw_header {
            if kind != '1' || fld(rec, 2, 3) != "01" {
                return fault(F_UNKNOWN_TAG, line, 1, "1", "the first record is not a file header");
            }
            let hf = parse_ach_file_header(rec, line, h);
            if hf.kind != F_NONE { return hf; }
            if fld(rec, 35, 40) != "094101" {
                return fault(F_SYNTAX, line, 35, "1", "the record size, blocking factor or format code is wrong");
            }
            if opts.check_routing && !routing_ok(h.destination_routing) {
                return fault(F_SYNTAX, line, 5, "1", "the routing number does not pass the check digit");
            }
            saw_header = true;
        } else if kind == '5' {
            if saw_control {
                return fault(F_UNKNOWN_TAG, line, 1, "5", "a batch header sits after the file control");
            }
            if open {
                return fault(F_UNKNOWN_TAG, line, 1, "5", "a batch header sits inside an open batch");
            }
            if batches.len + ib.len >= lim.max_batches {
                return fault(F_LIMIT, line, 1, "5", "more batches than the limits allow");
            }
            if fld(rec, 51, 53) == "IAT" {
                let tf = iat_open_batch(rec, line, iat, ie.len);
                if tf.kind != F_NONE { return tf; }
                iat_mode = true;
                open = true;
            } else {
                let bf = parse_ach_batch_header(rec, line, batch);
                if bf.kind != F_NONE { return bf; }
                batch.entry_start = entries.len as i32;
                batch.entry_count = 0;
                iat_mode = false;
                open = true;
                has_entry = false;
                addenda_seq = 0;
            }
        } else if kind == '6' && iat_mode {
            if !open {
                return fault(F_UNKNOWN_TAG, line, 1, "6", "an entry sits outside a batch");
            }
            if iat.has_entry { ie.push(iat.entry); }
            let tf = iat_entry_record(rec, line, iat, ie, ia, opts, lim);
            if tf.kind != F_NONE { return tf; }
        } else if kind == '7' && iat_mode {
            if !open {
                return fault(F_UNKNOWN_TAG, line, 1, "7", "an addendum sits outside a batch");
            }
            let tf = iat_addenda_record(rec, line, iat, ia, lim);
            if tf.kind != F_NONE { return tf; }
        } else if kind == '8' && iat_mode {
            if !open {
                return fault(F_UNKNOWN_TAG, line, 1, "8", "a batch control sits outside a batch");
            }
            if iat.has_entry { ie.push(iat.entry); }
            let count, hash, debit, credit, tf = iat_close_batch(rec, line, iat, ie, ia, opts);
            if tf.kind != F_NONE { return tf; }
            ib.push(iat.batch);
            file_count += count;
            let h1, ok1 = checked_add(file_hash, hash);
            if !ok1 { return fault(F_OVERFLOW, line, 0, "9", "the file hash does not fit"); }
            file_hash = h1 % 10000000000;
            let d1, ok2 = checked_add(file_debit, debit);
            if !ok2 { return fault(F_OVERFLOW, line, 0, "9", "the file debit total does not fit"); }
            file_debit = d1;
            let cr1, ok3 = checked_add(file_credit, credit);
            if !ok3 { return fault(F_OVERFLOW, line, 0, "9", "the file credit total does not fit"); }
            file_credit = cr1;
            open = false;
            iat_mode = false;
        } else if kind == '6' {
            if !open {
                return fault(F_UNKNOWN_TAG, line, 1, "6", "an entry sits outside a batch");
            }
            if has_entry {
                if entry_indicator == 1 && entry.addenda_count == 0 {
                    return fault(F_TOTAL, line - 1, 79, "6", "the entry declares an addendum it does not hold");
                }
                entries.push(entry);
                batch.entry_count += 1;
                has_entry = false;
            }
            if entries.len >= lim.max_entries {
                return fault(F_LIMIT, line, 1, "6", "more entries than the limits allow");
            }
            let ef = parse_ach_entry(rec, line, entry);
            if ef.kind != F_NONE { return ef; }
            if opts.check_routing && !routing_ok(entry.rdfi_routing) {
                return fault(F_SYNTAX, line, 4, "6", "the routing number does not pass the check digit");
            }
            let df = service_class_fault(batch.service_class, entry.transaction_code);
            if df.kind != F_NONE { return fault(df.kind, line, 2, "6", df.detail); }
            if ach_zero_amount_code(entry.transaction_code) && entry.amount != 0 {
                return fault(F_AMOUNT, line, 30, "6", "a prenote or a zero dollar entry holds an amount");
            }
            let sf = sec_entry_fault(batch.sec_code, is_reversal(batch.description),
                                     entry.transaction_code, entry.amount);
            if sf.kind != F_NONE {
                return fault(sf.kind, line, 2, "6", sf.detail);
            }
            if batch.entry_count > 0 && !trace_after(entry.trace_number, entries[entries.len - 1].trace_number) {
                return fault(F_TOTAL, line, 80, "6", "the trace numbers of the batch do not ascend");
            }
            if entry.trace_number[0..8] != batch.odfi_id {
                return fault(F_TOTAL, line, 80, "6", "the trace number does not start with the ODFI id");
            }
            entry.addenda_start = addenda.len as i32;
            entry.addenda_count = 0;
            entry_indicator = (rec[78] - '0') as i64;
            has_entry = true;
            addenda_seq = 0;
        } else if kind == '7' {
            if !open || !has_entry {
                return fault(F_UNKNOWN_TAG, line, 1, "7", "an addendum sits before the first entry");
            }
            if entry_indicator == 0 {
                return fault(F_TOTAL, line, 1, "7", "the entry declares no addendum");
            }
            let notice = fld(rec, 2, 3) == "98" || fld(rec, 2, 3) == "99";
            // A notice of change or a return stands alone on its entry.
            var add_max = sec_addenda_max(batch.sec_code);
            if notice { add_max = 1; }
            if entry.addenda_count > 0 && notice != (addenda[entry.addenda_start].kind != 5) {
                return fault(F_SYNTAX, line, 2, "7", "an entry mixes addenda of two kinds");
            }
            if entry.addenda_count as i64 >= add_max {
                return fault(F_LIMIT, line, 1, "7", "the entry holds more addenda than its SEC code allows");
            }
            if addenda.len >= lim.max_addenda {
                return fault(F_LIMIT, line, 1, "7", "more addenda than the limits allow");
            }
            var a: AchAddenda = new_ach_addenda();
            if notice {
                let nf = parse_ach_notice(rec, line, entry.trace_number, a);
                if nf.kind != F_NONE { return nf; }
                addenda.push(a);
                entry.addenda_count += 1;
                records += 1;
                let jn, en = skip_line_end(input, i + 94);
                if en.kind != F_NONE { return en; }
                i = jn;
                line += 1;
                continue;
            }
            let af = parse_ach_addenda(rec, line, a);
            if af.kind != F_NONE { return af; }
            addenda_seq += 1;
            let seq, sf = num_fld(rec, 84, 87, line, "7");
            if sf.kind != F_NONE { return sf; }
            if seq != addenda_seq {
                return fault(F_TOTAL, line, 84, "7", "the addenda sequence does not count from one");
            }
            let ef2 = check_entry_seq(rec, line, entry.trace_number);
            if ef2.kind != F_NONE { return ef2; }
            addenda.push(a);
            entry.addenda_count += 1;
        } else if kind == '8' {
            if !open {
                return fault(F_UNKNOWN_TAG, line, 1, "8", "a batch control sits outside a batch");
            }
            if !has_entry {
                return fault(F_SYNTAX, line, 1, "8", "the batch holds no entry");
            }
            if entry_indicator == 1 && entry.addenda_count == 0 {
                return fault(F_TOTAL, line, 79, "6", "the entry declares an addendum it does not hold");
            }
            entries.push(entry);
            batch.entry_count += 1;
            has_entry = false;
            batch.entry_start = (entries.len - batch.entry_count as i64) as i32;
            // The control record must agree with the header.
            let csc, c0 = num_fld(rec, 2, 4, line, "8");
            if c0.kind != F_NONE { return c0; }
            if csc != batch.service_class {
                return fault(F_TOTAL, line, 2, "8", "the service class of the control differs from the header");
            }
            let cci, c1 = txt_fld(rec, 45, 54, line, "8");
            if c1.kind != F_NONE { return c1; }
            if cci != batch.company_id {
                return fault(F_TOTAL, line, 45, "8", "the company id of the control differs from the header");
            }
            let cod, c2 = txt_fld(rec, 80, 87, line, "8");
            if c2.kind != F_NONE { return c2; }
            if cod != batch.odfi_id {
                return fault(F_TOTAL, line, 80, "8", "the ODFI id of the control differs from the header");
            }
            let cbn, c3 = num_fld(rec, 88, 94, line, "8");
            if c3.kind != F_NONE { return c3; }
            if cbn != batch.batch_number {
                return fault(F_TOTAL, line, 88, "8", "the batch number of the control differs from the header");
            }
            // The computed totals of the batch.
            let count, hash, debit, credit = batch_totals(batch, entries);
            let ccn, c4 = num_fld(rec, 5, 10, line, "8");
            if c4.kind != F_NONE { return c4; }
            let chc, c5 = num_fld(rec, 11, 20, line, "8");
            if c5.kind != F_NONE { return c5; }
            let cdb, c6 = num_fld(rec, 21, 32, line, "8");
            if c6.kind != F_NONE { return c6; }
            let ccr, c7 = num_fld(rec, 33, 44, line, "8");
            if c7.kind != F_NONE { return c7; }
            if !opts.skip_total_check {
                if ccn != count {
                    return fault_sums(F_TOTAL, line, "8", "the entry count of the control differs", ccn, count);
                }
                if chc != hash {
                    return fault_sums(F_TOTAL, line, "8", "the entry hash of the control differs", chc, hash);
                }
                if cdb != debit {
                    return fault_sums(F_TOTAL, line, "8", "the debit total of the control differs", cdb, debit);
                }
                if ccr != credit {
                    return fault_sums(F_TOTAL, line, "8", "the credit total of the control differs", ccr, credit);
                }
            }
            file_count += count;
            let h1, ok1 = checked_add(file_hash, hash);
            if !ok1 { return fault(F_OVERFLOW, line, 0, "9", "the file hash does not fit"); }
            file_hash = h1 % 10000000000;
            let d1, ok2 = checked_add(file_debit, debit);
            if !ok2 { return fault(F_OVERFLOW, line, 0, "9", "the file debit total does not fit"); }
            file_debit = d1;
            let cr1, ok3 = checked_add(file_credit, credit);
            if !ok3 { return fault(F_OVERFLOW, line, 0, "9", "the file credit total does not fit"); }
            file_credit = cr1;
            batches.push(batch);
            open = false;
        } else if kind == '9' {
            if saw_control {
                return fault(F_UNKNOWN_TAG, line, 1, "9", "a second file control sits in the file");
            }
            if open {
                return fault(F_UNKNOWN_TAG, line, 1, "9", "the file control sits inside an open batch");
            }
            let fbc, g0 = num_fld(rec, 2, 7, line, "9");
            if g0.kind != F_NONE { return g0; }
            let fbl, g1 = num_fld(rec, 8, 13, line, "9");
            if g1.kind != F_NONE { return g1; }
            let fcn, g2 = num_fld(rec, 14, 21, line, "9");
            if g2.kind != F_NONE { return g2; }
            let fha, g3 = num_fld(rec, 22, 31, line, "9");
            if g3.kind != F_NONE { return g3; }
            let fdb, g4 = num_fld(rec, 32, 43, line, "9");
            if g4.kind != F_NONE { return g4; }
            let fcr, g5 = num_fld(rec, 44, 55, line, "9");
            if g5.kind != F_NONE { return g5; }
            let blocks = (records + 1 + 9) / 10;
            if !opts.skip_total_check {
                if fbc != batches.len + ib.len {
                    return fault_sums(F_TOTAL, line, "9", "the batch count of the control differs", fbc, batches.len + ib.len);
                }
                if fbl != blocks {
                    return fault_sums(F_TOTAL, line, "9", "the block count of the control differs", fbl, blocks);
                }
                if fcn != file_count {
                    return fault_sums(F_TOTAL, line, "9", "the entry count of the control differs", fcn, file_count);
                }
                if fha != file_hash {
                    return fault_sums(F_TOTAL, line, "9", "the entry hash of the control differs", fha, file_hash);
                }
                if fdb != file_debit {
                    return fault_sums(F_TOTAL, line, "9", "the debit total of the control differs", fdb, file_debit);
                }
                if fcr != file_credit {
                    return fault_sums(F_TOTAL, line, "9", "the credit total of the control differs", fcr, file_credit);
                }
            }
            saw_control = true;
        } else {
            return fault(F_UNKNOWN_TAG, line, 1, rec[0..1], "the record type is not 1, 5, 6, 7, 8 or 9");
        }
        records += 1;
        let j, ef3 = skip_line_end(input, i + 94);
        if ef3.kind != F_NONE { return ef3; }
        i = j;
        line += 1;
    }
    if !saw_header { return fault(F_UNKNOWN_TAG, 0, 0, "1", "the file holds no file header"); }
    if open { return fault(F_UNKNOWN_TAG, 0, 0, "8", "the last batch holds no control record"); }
    if !saw_control { return fault(F_UNKNOWN_TAG, 0, 0, "9", "the file holds no file control"); }
    return no_fault();
}
