// The writer of the NACHA IAT batch.
//
// The writer writes the file header, the IAT batches with their
// entries and addenda, the batch controls and the file control, and
// pads the file with records of nines. It computes the trace numbers,
// the addenda counts and every total from the data. Every check runs
// before the first byte goes out, so a fault leaves the output buffer
// as it was.
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

// check_iat_batch checks one IAT batch header before any byte goes
// out.
fn check_iat_batch(b: IatBatch) -> Fault {
    if !service_class_ok(b.service_class) {
        return fault(F_SYNTAX, 0, 0, "5", "the service class is not 200, 220 or 225");
    }
    if !fx_indicator_ok(b.fx_indicator) {
        return fault(F_SYNTAX, 0, 0, "5", "the foreign exchange indicator is not FV, VF or FF");
    }
    if b.fx_ref_indicator < 1 || b.fx_ref_indicator > 3 {
        return fault(F_SYNTAX, 0, 0, "5", "the foreign exchange reference indicator is not 1, 2 or 3");
    }
    if !country_ok(b.dest_country) {
        return fault(F_SYNTAX, 0, 0, "5", "the destination country is not two capital letters");
    }
    if !currency_code_ok(b.origin_currency) {
        return fault(F_SYNTAX, 0, 0, "5", "the originating currency is not three capital letters");
    }
    if !currency_code_ok(b.dest_currency) {
        return fault(F_SYNTAX, 0, 0, "5", "the destination currency is not three capital letters");
    }
    if b.originator_status < 0 || b.originator_status > 2 {
        return fault(F_SYNTAX, 0, 0, "5", "the originator status is not 0, 1 or 2");
    }
    if b.odfi_id.len != 8 || !digits_ok(b.odfi_id) {
        return fault(F_SYNTAX, 0, 0, "5", "the ODFI id is not 8 digits");
    }
    if b.batch_number < 1 || b.batch_number > 9999999 {
        return fault(F_LIMIT, 0, 0, "5", "the batch number is not between 1 and 9999999");
    }
    if b.effective_year < 2000 || b.effective_year > 2099
       || !finance::date_ok(b.effective_year as i64, b.effective_month as i64, b.effective_day as i64) {
        return fault(F_DATE, 0, 0, "5", "the effective date is not a civil date in 2000 to 2099");
    }
    let f1 = check_ach_text(b.iat_indicator, 16, "5");
    if f1.kind != F_NONE { return f1; }
    let f2 = check_ach_text(b.fx_reference, 15, "5");
    if f2.kind != F_NONE { return f2; }
    let f3 = check_ach_text(b.originator_id, 10, "5");
    if f3.kind != F_NONE { return f3; }
    let f4 = check_ach_text(b.description, 10, "5");
    if f4.kind != F_NONE { return f4; }
    return no_fault();
}

// check_iat_entry checks one IAT entry before any byte goes out: the
// code, the routing number, the amount, the account and the two
// screening indicators.
fn check_iat_entry(e: IatEntry, service_class: i64) -> Fault {
    if !ach_code_ok(e.transaction_code) {
        return fault(F_SYNTAX, 0, 0, "6", "the transaction code is not in the NACHA set");
    }
    let df = service_class_fault(service_class, e.transaction_code);
    if df.kind != F_NONE { return df; }
    if ach_zero_amount_code(e.transaction_code) && e.amount != 0 {
        return fault(F_AMOUNT, 0, 0, "6", "a prenote or a zero dollar entry holds an amount");
    }
    if e.amount < 0 || e.amount > 9999999999 {
        return fault(F_AMOUNT, 0, 0, "6", "the amount does not fit the ten digit field");
    }
    if !routing_ok(e.rdfi_routing) {
        return fault(F_SYNTAX, 0, 0, "6", "the routing number does not pass the check digit");
    }
    let f1 = check_ach_text(e.dfi_account, 35, "6");
    if f1.kind != F_NONE { return f1; }
    let f2 = check_ach_text(e.ofac_screening, 1, "6");
    if f2.kind != F_NONE { return f2; }
    let f3 = check_ach_text(e.ofac_secondary, 1, "6");
    if f3.kind != F_NONE { return f3; }
    return no_fault();
}

// iat_entry_seq copies the last seven digits of a trace number.
fn iat_entry_seq(out: u8[>..]&, trace_number: const u8[:]) {
    var i: i64 = 8;
    while i < 15 { out.push(trace_number[i]); i += 1; }
}

// write_iat_addenda_rec writes one addenda record of type 02 or 10 to
// 18. The kinds 17 and 18 carry their own sequence numbers. The other
// kinds carry the entry sequence, the last seven digits of the trace
// number of the entry.
fn write_iat_addenda_rec(out: u8[>..]&, a: IatAddenda, seq17: i64, seq18: i64,
                         trace_number: const u8[:]) -> Fault {
    out.push('7');
    if a.kind == 2 {
        put(out, "02");
        let f1 = put_text(out, a.ref_one, 7, "7");
        if f1.kind != F_NONE { return f1; }
        let f2 = put_text(out, a.ref_two, 3, "7");
        if f2.kind != F_NONE { return f2; }
        let f3 = put_text(out, a.terminal_id, 6, "7");
        if f3.kind != F_NONE { return f3; }
        let f4 = put_text(out, a.serial, 6, "7");
        if f4.kind != F_NONE { return f4; }
        let f5 = put_num(out, a.date_month as i64, 2, "7");
        if f5.kind != F_NONE { return f5; }
        let f6 = put_num(out, a.date_day as i64, 2, "7");
        if f6.kind != F_NONE { return f6; }
        let f7 = put_text(out, a.auth_code, 6, "7");
        if f7.kind != F_NONE { return f7; }
        let f8 = put_text(out, a.location, 27, "7");
        if f8.kind != F_NONE { return f8; }
        let f9 = put_text(out, a.city, 15, "7");
        if f9.kind != F_NONE { return f9; }
        let f10 = put_text(out, a.state, 2, "7");
        if f10.kind != F_NONE { return f10; }
        let f11 = put_text(out, trace_number, 15, "7");
        if f11.kind != F_NONE { return f11; }
        return no_fault();
    }
    if a.kind == 10 {
        put(out, "10");
        if !txn_type_code_ok(a.txn_type_code) {
            return fault(F_SYNTAX, 0, 0, "7", "the transaction type code is not in the list");
        }
        let f1 = put_text(out, a.txn_type_code, 3, "7");
        if f1.kind != F_NONE { return f1; }
        let f2 = put_num(out, a.foreign_amount, 18, "7");
        if f2.kind != F_NONE { return f2; }
        let f3 = put_text(out, a.foreign_trace, 22, "7");
        if f3.kind != F_NONE { return f3; }
        let f4 = put_text(out, a.name, 35, "7");
        if f4.kind != F_NONE { return f4; }
        put(out, "      ");
        iat_entry_seq(out, trace_number);
        return no_fault();
    }
    if a.kind == 11 {
        put(out, "11");
        let f1 = put_text(out, a.name, 35, "7");
        if f1.kind != F_NONE { return f1; }
        let f2 = put_text(out, a.street, 35, "7");
        if f2.kind != F_NONE { return f2; }
        put(out, "              ");
        iat_entry_seq(out, trace_number);
        return no_fault();
    }
    if a.kind == 12 || a.kind == 16 {
        put_num(out, a.kind, 2, "7");
        let f1 = put_text(out, a.city_state, 35, "7");
        if f1.kind != F_NONE { return f1; }
        let f2 = put_text(out, a.country_postal, 35, "7");
        if f2.kind != F_NONE { return f2; }
        if !iat_dob_ok(a.date_of_birth) {
            return fault(F_DATE, 0, 0, "7", "the date of birth is not YYYY-MM-DD");
        }
        let f3 = put_text(out, a.date_of_birth, 10, "7");
        if f3.kind != F_NONE { return f3; }
        put(out, "    ");
        iat_entry_seq(out, trace_number);
        return no_fault();
    }
    if a.kind == 13 || a.kind == 14 || a.kind == 18 {
        put_num(out, a.kind, 2, "7");
        let f1 = put_text(out, a.name, 35, "7");
        if f1.kind != F_NONE { return f1; }
        let f2 = put_text(out, a.id_qualifier, 2, "7");
        if f2.kind != F_NONE { return f2; }
        let f3 = put_text(out, a.id_number, 34, "7");
        if f3.kind != F_NONE { return f3; }
        if !branch_country_ok(a.branch_country) {
            return fault(F_SYNTAX, 0, 0, "7", "the branch country is not two or three capital letters or digits");
        }
        let f4 = put_text(out, a.branch_country, 3, "7");
        if f4.kind != F_NONE { return f4; }
        if a.kind == 18 {
            put(out, "      ");
            let f5 = put_num(out, seq18, 4, "7");
            if f5.kind != F_NONE { return f5; }
            iat_entry_seq(out, trace_number);
        } else {
            put(out, "          ");
            iat_entry_seq(out, trace_number);
        }
        return no_fault();
    }
    if a.kind == 15 {
        put(out, "15");
        let f1 = put_text(out, a.receiver_id, 15, "7");
        if f1.kind != F_NONE { return f1; }
        let f2 = put_text(out, a.street, 35, "7");
        if f2.kind != F_NONE { return f2; }
        put(out, "                                  ");
        iat_entry_seq(out, trace_number);
        return no_fault();
    }
    if a.kind == 17 {
        put(out, "17");
        let f1 = put_text(out, a.payment_info, 80, "7");
        if f1.kind != F_NONE { return f1; }
        let f2 = put_num(out, seq17, 4, "7");
        if f2.kind != F_NONE { return f2; }
        iat_entry_seq(out, trace_number);
        return no_fault();
    }
    return fault(F_UNKNOWN_TAG, 0, 0, "7", "the addenda kind is not 2 or 10 to 18");
}

// write_iat_entry writes record 6 of an IAT batch. The count of
// addenda records and the addenda record indicator come from the data.
fn write_iat_entry(out: u8[>..]&, e: IatEntry, trace_number: const u8[:]) -> Fault {
    out.push('6');
    let f = put_num(out, e.transaction_code, 2, "6");
    if f.kind != F_NONE { return f; }
    put(out, e.rdfi_routing);
    let f2 = put_num(out, e.addenda_count as i64, 4, "6");
    if f2.kind != F_NONE { return f2; }
    put(out, "             ");
    let f3 = put_num(out, e.amount, 10, "6");
    if f3.kind != F_NONE { return f3; }
    let f4 = put_text(out, e.dfi_account, 35, "6");
    if f4.kind != F_NONE { return f4; }
    put(out, "  ");
    let f5 = put_text(out, e.ofac_screening, 1, "6");
    if f5.kind != F_NONE { return f5; }
    let f6 = put_text(out, e.ofac_secondary, 1, "6");
    if f6.kind != F_NONE { return f6; }
    if e.addenda_count > 0 { out.push('1'); } else { out.push('0'); }
    return put_text(out, trace_number, 15, "6");
}

// write_iat_batch_header writes record 5 of the SEC code IAT.
fn write_iat_batch_header(out: u8[>..]&, b: IatBatch) -> Fault {
    out.push('5');
    let f = put_num(out, b.service_class, 3, "5");
    if f.kind != F_NONE { return f; }
    let f2 = put_text(out, b.iat_indicator, 16, "5");
    if f2.kind != F_NONE { return f2; }
    let f3 = put_text(out, b.fx_indicator, 2, "5");
    if f3.kind != F_NONE { return f3; }
    let f4 = put_num(out, b.fx_ref_indicator, 1, "5");
    if f4.kind != F_NONE { return f4; }
    let f5 = put_text(out, b.fx_reference, 15, "5");
    if f5.kind != F_NONE { return f5; }
    let f6 = put_text(out, b.dest_country, 2, "5");
    if f6.kind != F_NONE { return f6; }
    let f7 = put_text(out, b.originator_id, 10, "5");
    if f7.kind != F_NONE { return f7; }
    put(out, "IAT");
    let f8 = put_text(out, b.description, 10, "5");
    if f8.kind != F_NONE { return f8; }
    let f9 = put_text(out, b.origin_currency, 3, "5");
    if f9.kind != F_NONE { return f9; }
    let f10 = put_text(out, b.dest_currency, 3, "5");
    if f10.kind != F_NONE { return f10; }
    let f11 = put_date6(out, b.effective_year, b.effective_month, b.effective_day, "5");
    if f11.kind != F_NONE { return f11; }
    let f12 = put_text(out, b.settlement_date, 3, "5");
    if f12.kind != F_NONE { return f12; }
    let f13 = put_num(out, b.originator_status, 1, "5");
    if f13.kind != F_NONE { return f13; }
    put(out, b.odfi_id);
    return put_num(out, b.batch_number, 7, "5");
}

// write_iat_batch_control writes record 8 of an IAT batch. The
// originator identification stands where the company id stands in the
// control of a normal batch.
fn write_iat_batch_control(out: u8[>..]&, b: IatBatch, entries: IatEntry[>..]&) -> Fault {
    let count, hash, debit, credit = batch_totals(b, entries);
    out.push('8');
    let f = put_num(out, b.service_class, 3, "8");
    if f.kind != F_NONE { return f; }
    let f2 = put_num(out, count, 6, "8");
    if f2.kind != F_NONE { return f2; }
    let f3 = put_num(out, hash, 10, "8");
    if f3.kind != F_NONE { return f3; }
    let f4 = put_num(out, debit, 12, "8");
    if f4.kind != F_NONE { return f4; }
    let f5 = put_num(out, credit, 12, "8");
    if f5.kind != F_NONE { return f5; }
    let f6 = put_text(out, b.originator_id, 10, "8");
    if f6.kind != F_NONE { return f6; }
    put(out, "                   ");
    put(out, "      ");
    put(out, b.odfi_id);
    return put_num(out, b.batch_number, 7, "8");
}

// write_ach_iat writes a file of IAT batches. The writer computes the
// trace numbers, the addenda counts and every total from the data.
fn write_ach_iat(h: AchFileHeader, batches: IatBatch[>..]&, entries: IatEntry[>..]&,
                 addenda: IatAddenda[>..]&, lim: Limits&, out: u8[>..]&) -> Fault {
    if batches.len > lim.max_batches {
        return fault(F_LIMIT, 0, 0, "9", "more batches than the limits allow");
    }
    if entries.len > lim.max_entries {
        return fault(F_LIMIT, 0, 0, "9", "more entries than the limits allow");
    }
    if addenda.len > lim.max_addenda {
        return fault(F_LIMIT, 0, 0, "9", "more addenda than the limits allow");
    }
    if batches.len == 0 {
        return fault(F_SYNTAX, 0, 0, "9", "the file holds no batch");
    }
    if h.creation_year < 0 || h.creation_month < 1 || h.creation_day < 1 {
        return fault(F_DATE, 0, 0, "1", "the creation date is missing or not valid");
    }
    // The blocks must tile the entries and the addenda. The checks of
    // the headers, the entries and the addenda run here too, so a
    // fault can come before any byte goes out.
    var next: i64 = 0;
    var next_add: i64 = 0;
    var total_count: i64 = 0;
    var total_hash: i64 = 0;
    var total_debit: i64 = 0;
    var total_credit: i64 = 0;
    var q: i64 = 0;
    while q < batches.len {
        let b = batches[q];
        if b.entry_start < 0 || b.entry_count < 0
           || b.entry_start as i64 + b.entry_count as i64 > entries.len {
            return fault(F_LIMIT, 0, 0, "5", "the entry range of the batch reaches past the entries");
        }
        if b.entry_count == 0 {
            return fault(F_SYNTAX, 0, 0, "5", "the batch holds no entry");
        }
        if b.entry_start as i64 != next {
            return fault(F_LIMIT, 0, 0, "5", "the entry ranges of the batches do not follow each other");
        }
        let bf = check_iat_batch(b);
        if bf.kind != F_NONE { return bf; }
        var cursor = next_add;
        var i = b.entry_start;
        while i < b.entry_start + b.entry_count {
            let e = entries[i];
            if e.addenda_start < 0 || e.addenda_count < 0
               || e.addenda_start as i64 + e.addenda_count as i64 > addenda.len {
                return fault(F_LIMIT, 0, 0, "6", "the addenda range of the entry reaches past the addenda");
            }
            if e.addenda_start as i64 != cursor {
                return fault(F_LIMIT, 0, 0, "6", "the addenda ranges of the entries do not follow each other");
            }
            cursor += e.addenda_count as i64;
            let ef = check_iat_entry(e, b.service_class);
            if ef.kind != F_NONE { return ef; }
            let of = iat_addenda_order_ok(addenda, e.addenda_start as i64, e.addenda_count as i64);
            if of.kind != F_NONE { return of; }
            let h2, ok = checked_add(total_hash, hash_prefix(e.rdfi_routing));
            if !ok { return fault(F_OVERFLOW, 0, 0, "8", "the entry hash does not fit"); }
            total_hash = h2 % 10000000000;
            let s, ok2 = checked_add(total_count, 1 + e.addenda_count as i64);
            if !ok2 { return fault(F_OVERFLOW, 0, 0, "8", "the entry count does not fit"); }
            total_count = s;
            if ach_debit_code(e.transaction_code) {
                let d, ok3 = checked_add(total_debit, e.amount);
                if !ok3 { return fault(F_OVERFLOW, 0, 0, "8", "the debit total does not fit"); }
                total_debit = d;
            } else {
                let c, ok4 = checked_add(total_credit, e.amount);
                if !ok4 { return fault(F_OVERFLOW, 0, 0, "8", "the credit total does not fit"); }
                total_credit = c;
            }
            i += 1;
        }
        next += b.entry_count as i64;
        next_add = cursor;
        q += 1;
    }
    if next != entries.len {
        return fault(F_LIMIT, 0, 0, "5", "the batches do not cover every entry");
    }
    if next_add != addenda.len {
        return fault(F_LIMIT, 0, 0, "5", "the entries do not cover every addendum");
    }
    var records: i64 = 1;
    q = 0;
    while q < batches.len {
        let b = batches[q];
        records += 2 + b.entry_count as i64;
        var i = b.entry_start;
        while i < b.entry_start + b.entry_count {
            records += entries[i].addenda_count as i64;
            i += 1;
        }
        q += 1;
    }
    records += 1;
    let blocks = (records + 9) / 10;
    // Write into a scratch buffer, so a late fault leaves out untouched.
    var body: u8[>..] = [];
    let wf = write_ach_file_header(body, h);
    if wf.kind != F_NONE { return wf; }
    put_rec(body);
    q = 0;
    while q < batches.len {
        let b = batches[q];
        let hdr_start = body.len;
        let bf = write_iat_batch_header(body, b);
        if bf.kind != F_NONE { return bf; }
        if body.len - hdr_start != 94 {
            return fault(F_LIMIT, 0, 0, "5", "a batch header is not 94 columns");
        }
        put_rec(body);
        var i = b.entry_start;
        while i < b.entry_start + b.entry_count {
            var trace: u8[>..] = [];
            put(trace, b.odfi_id);
            let f = put_num(trace, i - b.entry_start + 1, 7, "6");
            if f.kind != F_NONE { return f; }
            let rec_start = body.len;
            let ef = write_iat_entry(body, entries[i], trace);
            if ef.kind != F_NONE { return ef; }
            if body.len - rec_start != 94 {
                return fault(F_LIMIT, 0, 0, "6", "an entry record is not 94 columns");
            }
            put_rec(body);
            var a = entries[i].addenda_start;
            var n17: i64 = 0;
            var n18: i64 = 0;
            while a < entries[i].addenda_start + entries[i].addenda_count {
                let ad = addenda[a];
                if ad.kind == 17 { n17 += 1; }
                if ad.kind == 18 { n18 += 1; }
                let rec_start = body.len;
                let af = write_iat_addenda_rec(body, ad, n17, n18, trace);
                if af.kind != F_NONE { return af; }
                if body.len - rec_start != 94 {
                    return fault(F_LIMIT, 0, 0, "7", "an addenda record is not 94 columns");
                }
                put_rec(body);
                a += 1;
            }
            i += 1;
        }
        let ctl_start = body.len;
        let cf = write_iat_batch_control(body, b, entries);
        if cf.kind != F_NONE { return cf; }
        if body.len - ctl_start != 94 {
            return fault(F_LIMIT, 0, 0, "8", "a batch control is not 94 columns");
        }
        put_rec(body);
        q += 1;
    }
    let ff = write_ach_file_control(body, batches.len, total_count, total_hash, total_debit, total_credit, blocks);
    if ff.kind != F_NONE { return ff; }
    put_rec(body);
    let fill = blocks * 10 - records;
    var p: i64 = 0;
    while p < fill { put_nines(body); p += 1; }
    put(out, body);
    return no_fault();
}
