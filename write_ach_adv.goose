// The writer of the NACHA ADV batch.
//
// An ADV batch is a batch of automated accounting advice. Its entry
// record, its batch control record and its file control record have
// layouts of their own. The batch header and the file header keep the
// normal layout.
namespace payment_file;

import std;
import fault;
import model_ach;
import model_ach_adv;
import write_ach;

// adv_code_ok tells whether the code is a transaction code of the
// advice set.
fn adv_code_ok(code: i64) -> bool {
    return code >= 81 && code <= 88;
}

// adv_debit_code tells whether the code moves money out of the
// account.
fn adv_debit_code(code: i64) -> bool {
    return code == 82 || code == 84 || code == 86 || code == 88;
}

// check_adv_entry checks one advice entry before any byte goes out.
fn check_adv_entry(e: AdvEntry) -> Fault {
    if !adv_code_ok(e.transaction_code) {
        return fault(F_SYNTAX, 0, 0, "6", "an advice entry holds the code 81 to 88 only");
    }
    if !routing_ok(e.rdfi_routing) {
        return fault(F_SYNTAX, 0, 0, "6", "the routing number does not pass the check digit");
    }
    if e.account.len == 0 {
        return fault(F_SYNTAX, 0, 0, "6", "the account number is blank");
    }
    let f = check_ach_text(e.account, 15, "6");
    if f.kind != F_NONE { return f; }
    if e.amount < 0 {
        return fault(F_AMOUNT, 0, 0, "6", "the amount is below zero");
    }
    if !digits_width(e.advice_routing_number, 9) {
        return fault(F_SYNTAX, 0, 0, "6", "the advice routing number is not 9 digits");
    }
    if e.file_identification.len == 0 {
        return fault(F_SYNTAX, 0, 0, "6", "the file identification is blank");
    }
    let f3 = check_ach_text(e.file_identification, 5, "6");
    if f3.kind != F_NONE { return f3; }
    let f4 = check_ach_text(e.ach_operator_data, 1, "6");
    if f4.kind != F_NONE { return f4; }
    if blank_or_zero(e.individual_name) {
        return fault(F_SYNTAX, 0, 0, "6", "the individual name is blank or all zeros");
    }
    let f5 = check_ach_text(e.individual_name, 22, "6");
    if f5.kind != F_NONE { return f5; }
    let f6 = check_ach_text(e.discretionary, 2, "6");
    if f6.kind != F_NONE { return f6; }
    if e.addenda_indicator != 0 {
        return fault(F_LIMIT, 0, 0, "6", "an advice entry carries no addenda record");
    }
    if !digits_width(e.ach_operator_routing_number, 8) {
        return fault(F_SYNTAX, 0, 0, "6", "the operator routing number is not 8 digits");
    }
    if e.julian_day < 1 || e.julian_day > 366 {
        return fault(F_DATE, 0, 0, "6", "the Julian day is not between 1 and 366");
    }
    if e.sequence_number < 1 || e.sequence_number > 9999 {
        return fault(F_LIMIT, 0, 0, "6", "the sequence number is not between 1 and 9999");
    }
    return no_fault();
}

// write_adv_entry writes record 6 of an advice batch. The columns
// mirror the reader in read_ach_adv.goose.
fn write_adv_entry(out: u8[>..]&, e: AdvEntry) -> Fault {
    if e.rdfi_routing.len != 9 {
        return fault(F_SYNTAX, 0, 0, "6", "the routing number is not 9 digits");
    }
    out.push('6');
    let f = put_num(out, e.transaction_code, 2, "6");
    if f.kind != F_NONE { return f; }
    put(out, e.rdfi_routing);
    let f2 = put_text(out, e.account, 15, "6");
    if f2.kind != F_NONE { return f2; }
    let f3 = put_num(out, e.amount, 12, "6");
    if f3.kind != F_NONE { return f3; }
    let f4 = put_text(out, e.advice_routing_number, 9, "6");
    if f4.kind != F_NONE { return f4; }
    let f5 = put_text(out, e.file_identification, 5, "6");
    if f5.kind != F_NONE { return f5; }
    let f6 = put_text(out, e.ach_operator_data, 1, "6");
    if f6.kind != F_NONE { return f6; }
    let f7 = put_text(out, e.individual_name, 22, "6");
    if f7.kind != F_NONE { return f7; }
    let f8 = put_text(out, e.discretionary, 2, "6");
    if f8.kind != F_NONE { return f8; }
    out.push('0');
    let f9 = put_text(out, e.ach_operator_routing_number, 8, "6");
    if f9.kind != F_NONE { return f9; }
    let f10 = put_num(out, e.julian_day, 3, "6");
    if f10.kind != F_NONE { return f10; }
    return put_num(out, e.sequence_number, 4, "6");
}

// adv_totals gives the count, the hash, the debit total and the
// credit total of the advice entries of a batch.
fn adv_totals(b: AchBatch, entries: AdvEntry[>..]&, line: i64) -> i64, i64, i64, i64, Fault {
    var count: i64 = 0;
    var hash: i64 = 0;
    var debit: i64 = 0;
    var credit: i64 = 0;
    var i = b.entry_start;
    while i < b.entry_start + b.entry_count {
        let e = entries[i];
        count += 1;
        let h, d, c, tf = fold_totals(hash, debit, credit, e.rdfi_routing, e.amount,
                                      adv_debit_code(e.transaction_code), line);
        if tf.kind != F_NONE { return 0, 0, 0, 0, tf; }
        hash = h;
        debit = d;
        credit = c;
        i += 1;
    }
    return count, hash, debit, credit, no_fault();
}

// write_adv_batch_control writes record 8 of an advice batch. The
// totals hold twenty columns each.
fn write_adv_batch_control(out: u8[>..]&, b: AchBatch, count: i64, hash: i64,
                            debit: i64, credit: i64) -> Fault {
    out.push('8');
    let f = put_num(out, b.service_class, 3, "8");
    if f.kind != F_NONE { return f; }
    let f2 = put_num(out, count, 6, "8");
    if f2.kind != F_NONE { return f2; }
    let f3 = put_num(out, hash, 10, "8");
    if f3.kind != F_NONE { return f3; }
    let f4 = put_num(out, debit, 20, "8");
    if f4.kind != F_NONE { return f4; }
    let f5 = put_num(out, credit, 20, "8");
    if f5.kind != F_NONE { return f5; }
    let f6 = put_text(out, b.company_name, 19, "8");
    if f6.kind != F_NONE { return f6; }
    put(out, b.odfi_id);
    return put_num(out, b.batch_number, 7, "8");
}

// write_adv_file_control writes record 9 of an advice file. The
// totals hold twenty columns each.
fn write_adv_file_control(out: u8[>..]&, batch_count: i64, total_count: i64,
                           total_hash: i64, total_debit: i64, total_credit: i64,
                           blocks: i64) -> Fault {
    out.push('9');
    let f = put_num(out, batch_count, 6, "9");
    if f.kind != F_NONE { return f; }
    let f2 = put_num(out, blocks, 6, "9");
    if f2.kind != F_NONE { return f2; }
    let f3 = put_num(out, total_count, 8, "9");
    if f3.kind != F_NONE { return f3; }
    let f4 = put_num(out, total_hash, 10, "9");
    if f4.kind != F_NONE { return f4; }
    let f5 = put_num(out, total_debit, 20, "9");
    if f5.kind != F_NONE { return f5; }
    let f6 = put_num(out, total_credit, 20, "9");
    if f6.kind != F_NONE { return f6; }
    var i: i64 = 0;
    while i < 23 { out.push(' '); i += 1; }
    return no_fault();
}

// check_adv_batch checks the rules of an advice batch header. The
// rules of the other kinds of batch stand in their own functions.
fn check_adv_batch(b: AchBatch, line: i64) -> Fault {
    if b.service_class != 280 {
        return fault(F_SYNTAX, line, 2, "5", "an advice batch holds the service class 280 only");
    }
    if b.sec_code != "ADV" {
        return fault(F_SYNTAX, line, 51, "5", "an advice batch holds the SEC code ADV only");
    }
    if b.originator_status != 0 {
        return fault(F_SYNTAX, line, 79, "5", "an advice batch holds the originator status 0 only");
    }
    return no_fault();
}

// write_ach_adv writes a file of advice batches. The writer computes
// the totals and every count from the data.
fn write_ach_adv(h: AchFileHeader, batches: AchBatch[>..]&, entries: AdvEntry[>..]&,
                 lim: Limits&, out: u8[>..]&) -> Fault {
    if batches.len > lim.max_batches {
        return fault(F_LIMIT, 0, 0, "9", "more batches than the limits allow");
    }
    if entries.len > lim.max_entries {
        return fault(F_LIMIT, 0, 0, "9", "more entries than the limits allow");
    }
    if batches.len == 0 {
        return fault(F_SYNTAX, 0, 0, "9", "the file holds no batch");
    }
    if h.creation_year < 0 || h.creation_month < 1 || h.creation_day < 1 {
        return fault(F_DATE, 0, 0, "1", "the creation date is missing or not valid");
    }
    // Count the records without the padding: the header, the batch
    // records and the file control.
    var records: i64 = 1;
    var rq: i64 = 0;
    while rq < batches.len {
        let rb = batches[rq];
        records += 2 + rb.entry_count as i64;
        rq += 1;
    }
    records += 1;
    let blocks = (records + 9) / 10;
    // Write into a scratch buffer, so a late fault leaves out untouched.
    var body: u8[>..] = [];
    let hf = write_ach_file_header(body, h);
    if hf.kind != F_NONE { return hf; }
    put_rec(body);
    var next: i64 = 0;
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
        if b.entry_start != next {
            return fault(F_LIMIT, 0, 0, "5", "the entry ranges of the batches do not follow each other");
        }
        let bf = check_adv_batch(b, 0);
        if bf.kind != F_NONE { return bf; }
        let bhf = write_ach_batch_header(body, b);
        if bhf.kind != F_NONE { return bhf; }
        put_rec(body);
        var last_seq: i64 = 0;
        var i = b.entry_start;
        while i < b.entry_start + b.entry_count {
            let e = entries[i];
            let ef = check_adv_entry(e);
            if ef.kind != F_NONE { return ef; }
            if e.sequence_number <= last_seq {
                return fault(F_TOTAL, 0, 0, "6", "the sequence numbers of the batch do not ascend");
            }
            last_seq = e.sequence_number;
            let wf = write_adv_entry(body, e);
            if wf.kind != F_NONE { return wf; }
            put_rec(body);
            i += 1;
        }
        next = b.entry_start as i64 + b.entry_count as i64;
        let count, hash, debit, credit, tf = adv_totals(b, entries, 0);
        if tf.kind != F_NONE { return tf; }
        let c, ok1 = checked_add(total_count, count);
        if !ok1 { return fault(F_OVERFLOW, 0, 0, "9", "the entry count does not fit"); }
        total_count = c;
        let h2, ok2 = checked_add(total_hash, hash);
        if !ok2 { return fault(F_OVERFLOW, 0, 0, "9", "the file hash does not fit"); }
        total_hash = h2 % 10000000000;
        let d, ok3 = checked_add(total_debit, debit);
        if !ok3 { return fault(F_OVERFLOW, 0, 0, "9", "the file debit total does not fit"); }
        total_debit = d;
        let cr, ok4 = checked_add(total_credit, credit);
        if !ok4 { return fault(F_OVERFLOW, 0, 0, "9", "the file credit total does not fit"); }
        total_credit = cr;
        let cf = write_adv_batch_control(body, b, count, hash, debit, credit);
        if cf.kind != F_NONE { return cf; }
        put_rec(body);
        q += 1;
    }
    let fcf = write_adv_file_control(body, batches.len, total_count, total_hash,
                                     total_debit, total_credit, blocks);
    if fcf.kind != F_NONE { return fcf; }
    put_rec(body);
    let fill = blocks * 10 - records;
    var p: i64 = 0;
    while p < fill {
        put_nines(body);
        p += 1;
    }
    put(out, body);
    return no_fault();
}
