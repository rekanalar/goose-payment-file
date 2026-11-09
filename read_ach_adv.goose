// The reader of the NACHA ADV batch.
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
import write_ach_adv;

// parse_adv_entry reads record 6 of an advice batch. The columns
// mirror the writer in write_ach_adv.goose.
fn parse_adv_entry(rec: const u8[:], line: i64, e: AdvEntry&) -> Fault {
    let tc, f0 = num_fld(rec, 2, 3, line, "6");
    if f0.kind != F_NONE { return f0; }
    if !adv_code_ok(tc) {
        return fault(F_SYNTAX, line, 2, "6", "an advice entry holds the code 81 to 88 only");
    }
    e.transaction_code = tc;
    let r = fld(rec, 4, 12);
    if !ascii_ok(r) {
        return fault(F_CHARSET, line, 4, "6", "the routing number holds a byte outside printable ASCII");
    }
    e.rdfi_routing = r;
    let ac, f1 = txt_fld(rec, 13, 27, line, "6");
    if f1.kind != F_NONE { return f1; }
    if ac.len == 0 { return fault(F_SYNTAX, line, 13, "6", "the account number is blank"); }
    e.account = ac;
    let am, f2 = num_fld(rec, 28, 39, line, "6");
    if f2.kind != F_NONE { return f2; }
    e.amount = am;
    let arn = fld(rec, 40, 48);
    if !digits_width(arn, 9) {
        return fault(F_SYNTAX, line, 40, "6", "the advice routing number is not 9 digits");
    }
    e.advice_routing_number = arn;
    let fi, f4 = txt_fld(rec, 49, 53, line, "6");
    if f4.kind != F_NONE { return f4; }
    if fi.len == 0 { return fault(F_SYNTAX, line, 49, "6", "the file identification is blank"); }
    e.file_identification = fi;
    let od, f5 = txt_fld(rec, 54, 54, line, "6");
    if f5.kind != F_NONE { return f5; }
    e.ach_operator_data = od;
    let nm, f6 = txt_fld(rec, 55, 76, line, "6");
    if f6.kind != F_NONE { return f6; }
    if blank_or_zero(nm) { return fault(F_SYNTAX, line, 55, "6", "the individual name is blank or all zeros"); }
    e.individual_name = nm;
    let disc, f7 = txt_fld(rec, 77, 78, line, "6");
    if f7.kind != F_NONE { return f7; }
    e.discretionary = disc;
    let ind, f8 = num_fld(rec, 79, 79, line, "6");
    if f8.kind != F_NONE { return f8; }
    if ind != 0 {
        return fault(F_LIMIT, line, 79, "6", "an advice entry carries no addenda record");
    }
    e.addenda_indicator = 0;
    let orr = fld(rec, 80, 87);
    if !digits_width(orr, 8) {
        return fault(F_SYNTAX, line, 80, "6", "the operator routing number is not 8 digits");
    }
    e.ach_operator_routing_number = orr;
    let jd, f10 = num_fld(rec, 88, 90, line, "6");
    if f10.kind != F_NONE { return f10; }
    if jd < 1 || jd > 366 {
        return fault(F_DATE, line, 88, "6", "the Julian day is not between 1 and 366");
    }
    e.julian_day = jd;
    let sn, f11 = num_fld(rec, 91, 94, line, "6");
    if f11.kind != F_NONE { return f11; }
    if sn < 1 || sn > 9999 {
        return fault(F_LIMIT, line, 91, "6", "the sequence number is not between 1 and 9999");
    }
    e.sequence_number = sn;
    return no_fault();
}

// parse_ach_adv reads a whole NACHA file of advice batches into the
// model. After a fault the arrays hold partial results; do not use
// them.
fn parse_ach_adv(input: const u8[:], opts: AchOptions, lim: Limits&, h: AchFileHeader&,
                 batches: AchBatch[>..]&, entries: AdvEntry[>..]&) -> Fault {
    if input.len > lim.max_input {
        return fault(F_LIMIT, 0, 0, "9", "the input is longer than the limits allow");
    }
    var i: i64 = 0;
    var line: i64 = 1;
    var saw_header: bool = false;
    var saw_control: bool = false;
    var open: bool = false;
    var batch: AchBatch = new_ach_batch();
    var entry: AdvEntry = new_adv_entry();
    var file_count: i64 = 0;
    var file_hash: i64 = 0;
    var file_debit: i64 = 0;
    var file_credit: i64 = 0;
    var records: i64 = 0;
    var batch_count: i64 = 0;
    var last_seq: i64 = 0;
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
            if batches.len >= lim.max_batches {
                return fault(F_LIMIT, line, 1, "5", "more batches than the limits allow");
            }
            let bf = parse_ach_batch_header(rec, line, batch);
            if bf.kind != F_NONE { return bf; }
            let kf = check_adv_batch(batch, line);
            if kf.kind != F_NONE { return kf; }
            batch.entry_start = entries.len as i32;
            batch.entry_count = 0;
            open = true;
            batch_count += 1;
            last_seq = 0;
        } else if kind == '6' {
            if !open {
                return fault(F_UNKNOWN_TAG, line, 1, "6", "an entry sits outside a batch");
            }
            if entries.len >= lim.max_entries {
                return fault(F_LIMIT, line, 1, "6", "more entries than the limits allow");
            }
            let ef = parse_adv_entry(rec, line, entry);
            if ef.kind != F_NONE { return ef; }
            if opts.check_routing && !routing_ok(entry.rdfi_routing) {
                return fault(F_SYNTAX, line, 4, "6", "the routing number does not pass the check digit");
            }
            if entry.sequence_number <= last_seq {
                return fault(F_TOTAL, line, 91, "6", "the sequence numbers of the batch do not ascend");
            }
            last_seq = entry.sequence_number;
            entries.push(entry);
            batch.entry_count += 1;
        } else if kind == '8' {
            if !open {
                return fault(F_UNKNOWN_TAG, line, 1, "8", "a batch control sits outside a batch");
            }
            if batch.entry_count == 0 {
                return fault(F_SYNTAX, line, 1, "8", "the batch holds no entry");
            }
            // The control record must agree with the header.
            let sc, g0 = num_fld(rec, 2, 4, line, "8");
            if g0.kind != F_NONE { return g0; }
            if sc != 280 {
                return fault(F_TOTAL, line, 2, "8", "the service class of the control differs from the header");
            }
            let cod, g5 = txt_fld(rec, 80, 87, line, "8");
            if g5.kind != F_NONE { return g5; }
            if cod != batch.odfi_id {
                return fault(F_TOTAL, line, 80, "8", "the ODFI id of the control differs from the header");
            }
            let cbn, g6 = num_fld(rec, 88, 94, line, "8");
            if g6.kind != F_NONE { return g6; }
            if cbn != batch.batch_number {
                return fault(F_TOTAL, line, 88, "8", "the batch number of the control differs from the header");
            }
            let cnt, g1 = num_fld(rec, 5, 10, line, "8");
            if g1.kind != F_NONE { return g1; }
            let hsh, g2 = num_fld(rec, 11, 20, line, "8");
            if g2.kind != F_NONE { return g2; }
            let db, g3 = num_fld(rec, 21, 40, line, "8");
            if g3.kind != F_NONE { return g3; }
            let cr, g4 = num_fld(rec, 41, 60, line, "8");
            if g4.kind != F_NONE { return g4; }
            let count, hash, debit, credit, tf = adv_totals(batch, entries, line);
            if tf.kind != F_NONE { return tf; }
            if !opts.skip_total_check {
                if cnt != count {
                    return fault_sums(F_TOTAL, line, "8", "the entry count of the control differs", cnt, count);
                }
                if hsh != hash {
                    return fault_sums(F_TOTAL, line, "8", "the entry hash of the control differs", hsh, hash);
                }
                if db != debit {
                    return fault_sums(F_TOTAL, line, "8", "the debit total of the control differs", db, debit);
                }
                if cr != credit {
                    return fault_sums(F_TOTAL, line, "8", "the credit total of the control differs", cr, credit);
                }
            }
            batches.push(batch);
            file_count += count;
            let h2, ok4 = checked_add(file_hash, hash);
            if !ok4 { return fault(F_OVERFLOW, line, 0, "9", "the file hash does not fit"); }
            file_hash = h2 % 10000000000;
            let d1, ok5 = checked_add(file_debit, debit);
            if !ok5 { return fault(F_OVERFLOW, line, 0, "9", "the file debit total does not fit"); }
            file_debit = d1;
            let c1, ok6 = checked_add(file_credit, credit);
            if !ok6 { return fault(F_OVERFLOW, line, 0, "9", "the file credit total does not fit"); }
            file_credit = c1;
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
            let fdb, g4 = num_fld(rec, 32, 51, line, "9");
            if g4.kind != F_NONE { return g4; }
            let fcr, g5 = num_fld(rec, 52, 71, line, "9");
            if g5.kind != F_NONE { return g5; }
            // A normal file control holds spaces from column 56, so the
            // twenty digit totals above refuse it. The tail after the
            // totals must hold spaces.
            let ts = tail_spaces(rec, 72, 94, line, "9");
            if ts.kind != F_NONE { return ts; }
            let blocks = (records + 1 + 9) / 10;
            if !opts.skip_total_check {
                if fbc != batch_count {
                    return fault_sums(F_TOTAL, line, "9", "the batch count of the control differs", fbc, batch_count);
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
            return fault(F_UNKNOWN_TAG, line, 1, rec[0..1], "the record type is not 1, 5, 6, 8 or 9");
        }
        records += 1;
        let j, ef3 = skip_line_end(input, i + 94);
        if ef3.kind != F_NONE { return ef3; }
        i = j;
        line += 1;
    }
    if !saw_header {
        return fault(F_UNKNOWN_TAG, 1, 1, "1", "the file holds no file header");
    }
    if !saw_control {
        return fault(F_UNKNOWN_TAG, line, 1, "9", "the file holds no file control");
    }
    if open {
        return fault(F_UNKNOWN_TAG, line, 1, "5", "the file ends inside a batch");
    }
    return no_fault();
}
