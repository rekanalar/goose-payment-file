// The writer of the NACHA ACH file.
//
// The writer emits the six record types: file header (1), batch
// header (5), entry detail (6), addenda (7, type 05), batch control
// (8) and file control (9). Every record holds exactly 94 columns and
// ends with a line feed. The writer computes every total from the
// entries: the counts, the entry hash, the debit total, the credit
// total, the batch count and the block count. The caller cannot set
// them. The writer pads the file with records of nines to a block of
// ten records. Every text holds printable ASCII, and no text is ever
// truncated: a text longer than its field is a fault.
namespace payment_file;

import std;
import finance from "rekanalar/goose-finance@v0.1.0";
import fault;
import model;
import model_ach;
import charset;
import control;

// routing_check gives the check digit of the first eight digits of a
// routing number. The weights are 3, 7, 1, 3, 7, 1, 3, 7. The digit
// is the next multiple of ten minus the sum. A routing number that
// holds no digits gives false.
fn routing_check(routing: const u8[:]) -> i64, bool {
    if routing.len < 8 { return 0, false; }
    var sum: i64 = 0;
    var i: i64 = 0;
    while i < 8 {
        let c = routing[i];
        if c < '0' || c > '9' { return 0, false; }
        let d = (c - '0') as i64;
        if i == 0 || i == 3 || i == 6 { sum += d * 3; }
        else if i == 1 || i == 4 || i == 7 { sum += d * 7; }
        else { sum += d; }
        i += 1;
    }
    let rest = sum % 10;
    if rest == 0 { return 0, true; }
    return 10 - rest, true;
}

// routing_ok tells whether a routing number holds nine digits and the
// right check digit.
fn routing_ok(routing: const u8[:]) -> bool {
    if routing.len != 9 { return false; }
    var i: i64 = 0;
    while i < 9 {
        if routing[i] < '0' || routing[i] > '9' { return false; }
        i += 1;
    }
    let d, ok = routing_check(routing);
    if !ok { return false; }
    return d == (routing[8] - '0') as i64;
}

// sec_ok tells whether the SEC code is one of the codes of the
// package.
fn sec_ok(code: const u8[:]) -> bool {
    if code == "PPD" || code == "CCD" || code == "WEB" || code == "TEL" { return true; }
    if code == "CTX" || code == "ARC" || code == "BOC" || code == "POP" || code == "RCK" { return true; }
    return false;
}

// service_class_ok tells whether the service class is one of the
// three classes of the package: mixed, credits only, debits only.
fn service_class_ok(code: i64) -> bool {
    return code == 200 || code == 220 || code == 225;
}

// ach_credit_code tells whether the transaction code moves money into
// the receiver account. The codes 21, 31, 41, 51 are returns of a
// debit, so they count as credits.
fn ach_credit_code(code: i64) -> bool {
    if code == 21 || code == 22 || code == 23 || code == 24 { return true; }
    if code == 31 || code == 32 || code == 33 || code == 34 { return true; }
    if code == 41 || code == 42 || code == 43 || code == 44 { return true; }
    if code == 51 || code == 52 || code == 53 || code == 54 { return true; }
    return false;
}

// ach_debit_code tells whether the transaction code moves money out
// of the receiver account.
fn ach_debit_code(code: i64) -> bool {
    if code == 26 || code == 27 || code == 28 || code == 29 { return true; }
    if code == 36 || code == 37 || code == 38 || code == 39 { return true; }
    if code == 46 || code == 47 || code == 48 || code == 49 { return true; }
    if code == 55 || code == 56 { return true; }
    return false;
}

// ach_code_ok tells whether the transaction code is in the NACHA set:
// checking, savings, general ledger and loan accounts.
fn ach_code_ok(code: i64) -> bool {
    return ach_credit_code(code) || ach_debit_code(code);
}

// ach_zero_amount_code tells whether the code is a prenote or a zero
// dollar remittance code. Such an entry holds an amount of zero.
fn ach_zero_amount_code(code: i64) -> bool {
    let d = code % 10;
    return d == 3 || d == 4 || d == 8 || d == 9;
}

// digits_ok tells whether the text holds digits only.
fn digits_ok(text: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < text.len {
        if text[i] < '0' || text[i] > '9' { return false; }
        i += 1;
    }
    return true;
}

// check_ach_text checks one text against the printable ASCII set and
// a width. The writer never truncates.
fn check_ach_text(text: const u8[:], width: i64, tag: const u8[:]) -> Fault {
    if text.len > width {
        return fault(F_LIMIT, 0, 0, tag, "the text is longer than the field holds");
    }
    if !ascii_ok(text) {
        return fault(F_CHARSET, 0, 0, tag, "the text holds a byte outside printable ASCII");
    }
    return no_fault();
}

// put_num writes a number zero filled to a width. A number that does
// not fit is a fault.
fn put_num(out: u8[>..]&, v: i64, width: i64, tag: const u8[:]) -> Fault {
    if v < 0 { return fault(F_AMOUNT, 0, 0, tag, "the number is below zero"); }
    var digits: u8[>..] = [];
    var x = v;
    if x == 0 { digits.push('0'); }
    while x > 0 {
        digits.push(('0' + (x % 10)) as u8);
        x = x / 10;
    }
    if digits.len > width {
        return fault(F_LIMIT, 0, 0, tag, "the number does not fit the field");
    }
    var p: i64 = width - digits.len;
    while p > 0 { out.push('0'); p -= 1; }
    var k = digits.len;
    while k > 0 { k -= 1; out.push(digits[k]); }
    return no_fault();
}

// put_date6 writes a date as YYMMDD. The year holds two digits; the
// caller gives the full year and the writer writes its last two
// digits.
fn put_date6(out: u8[>..]&, year: i32, month: i32, day: i32, tag: const u8[:]) -> Fault {
    // The file holds two digits of the year. The reader reads them as 20YY.
    if year < 2000 || year > 2099 || !finance::date_ok(year as i64, month as i64, day as i64) {
        return fault(F_DATE, 0, 0, tag, "the date is not a civil date in 2000 to 2099");
    }
    let f = put_num(out, (year % 100) as i64, 2, tag);
    if f.kind != F_NONE { return f; }
    let g = put_num(out, month as i64, 2, tag);
    if g.kind != F_NONE { return g; }
    return put_num(out, day as i64, 2, tag);
}

// put_time4 writes the creation time as HHMM.
fn put_time4(out: u8[>..]&, hour: i32, minute: i32, tag: const u8[:]) -> Fault {
    if hour < 0 || hour > 23 || minute < 0 || minute > 59 {
        return fault(F_DATE, 0, 0, tag, "the time is not a time of day");
    }
    let f = put_num(out, hour as i64, 2, tag);
    if f.kind != F_NONE { return f; }
    return put_num(out, minute as i64, 2, tag);
}

// put_text pads a text with spaces on the right to the field width.
// A bad text is a fault. The caller checks nothing.
fn put_text(out: u8[>..]&, text: const u8[:], width: i64, tag: const u8[:]) -> Fault {
    let f = check_ach_text(text, width, tag);
    if f.kind != F_NONE { return f; }
    put(out, text);
    var p = width - text.len;
    while p > 0 { out.push(' '); p -= 1; }
    return no_fault();
}

// put_rec ends a record with a line feed.
fn put_rec(out: u8[>..]&) {
    out.push('\n');
}

// put_nines writes one padding record: 94 nines.
fn put_nines(out: u8[>..]&) {
    var i: i64 = 0;
    while i < 94 { out.push('9'); i += 1; }
    put_rec(out);
}

// entry_addenda_total gives the count of the addenda of the entries
// of a batch.
fn entry_addenda_total(b: AchBatch, entries: AchEntry[>..]&) -> i64 {
    var t: i64 = 0;
    var i = b.entry_start;
    while i < b.entry_start + b.entry_count {
        t += entries[i].addenda_count as i64;
        i += 1;
    }
    return t;
}

// batch_entry_bounds checks that the entry range of the batch and the
// addenda range of every entry sit inside the arrays.
fn batch_entry_bounds(batch: AchBatch, entries: AchEntry[>..]&, addenda: AchAddenda[>..]&) -> Fault {
    if batch.entry_start < 0 || batch.entry_count < 0
       || batch.entry_start as i64 + batch.entry_count as i64 > entries.len {
        return fault(F_LIMIT, 0, 0, "5", "the entry range of the batch reaches past the entries");
    }
    var i = batch.entry_start;
    while i < batch.entry_start + batch.entry_count {
        let e = entries[i];
        if e.addenda_start < 0 || e.addenda_count < 0
           || e.addenda_start as i64 + e.addenda_count as i64 > addenda.len {
            return fault(F_LIMIT, 0, 0, "6", "the addenda range of the entry reaches past the addenda");
        }
        i += 1;
    }
    return no_fault();
}

// is_reversal tells whether the batch description marks a reversal.
// A reversal batch holds the opposite direction of the forward batch.
fn is_reversal(description: const u8[:]) -> bool {
    return description.len >= 8 && description[0..8] == "REVERSAL";
}

// sec_addenda_max gives the most addenda that an entry of the SEC
// code may hold. PPD, CCD and WEB hold one. CTX holds many. The
// other codes hold none.
fn sec_addenda_max(sec: const u8[:]) -> i64 {
    if sec == "PPD" || sec == "CCD" || sec == "WEB" { return 1; }
    if sec == "CTX" { return 9999; }
    return 0;
}

// sec_entry_fault applies the rules of the SEC code to one entry.
// TEL, ARC, BOC, POP and RCK hold debits only, and a reversal batch
// holds credits only. ARC holds at most 25000.00 and RCK at most
// 2500.00 per entry.
fn sec_entry_fault(sec: const u8[:], reversal: bool, code: i64, amount: i64) -> Fault {
    let debit_only = sec == "TEL" || sec == "ARC" || sec == "BOC" || sec == "POP" || sec == "RCK";
    if debit_only {
        if !reversal && ach_credit_code(code) {
            return fault(F_TOTAL, 0, 0, "6", "this SEC code holds debits only");
        }
        if reversal && ach_debit_code(code) {
            return fault(F_TOTAL, 0, 0, "6", "a reversal batch of this SEC code holds credits only");
        }
    }
    if sec == "ARC" && amount > 2500000 {
        return fault(F_AMOUNT, 0, 0, "6", "an ARC entry holds at most 25000.00");
    }
    if sec == "RCK" && amount > 250000 {
        return fault(F_AMOUNT, 0, 0, "6", "an RCK entry holds at most 2500.00");
    }
    return no_fault();
}

// trace_after tells whether trace number a sorts after trace number b.
// Both hold 15 digits, so a byte compare gives the order.
fn trace_after(a: const u8[:], b: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < a.len && i < b.len {
        if a[i] != b[i] { return a[i] > b[i]; }
        i += 1;
    }
    return false;
}

// check_entry checks one entry before any byte goes out: the code,
// the routing number, the amount, the trace number and the ranges.
fn check_entry(e: AchEntry, odfi_id: const u8[:], service_class: i64, sec: const u8[:], reversal: bool) -> Fault {
    if !ach_code_ok(e.transaction_code) {
        return fault(F_SYNTAX, 0, 0, "6", "the transaction code is not in the NACHA set");
    }
    if service_class == 220 && ach_debit_code(e.transaction_code) {
        return fault(F_TOTAL, 0, 0, "6", "a batch of credits only holds a debit");
    }
    if service_class == 225 && ach_credit_code(e.transaction_code) {
        return fault(F_TOTAL, 0, 0, "6", "a batch of debits only holds a credit");
    }
    let sf = sec_entry_fault(sec, reversal, e.transaction_code, e.amount);
    if sf.kind != F_NONE { return sf; }
    if e.addenda_count as i64 > sec_addenda_max(sec) {
        return fault(F_LIMIT, 0, 0, "7", "the entry holds more addenda than its SEC code allows");
    }
    if ach_zero_amount_code(e.transaction_code) && e.amount != 0 {
        return fault(F_AMOUNT, 0, 0, "6", "a prenote or a zero dollar entry holds an amount");
    }
    if e.amount < 0 {
        return fault(F_AMOUNT, 0, 0, "6", "the amount is below zero");
    }
    if !routing_ok(e.rdfi_routing) {
        return fault(F_SYNTAX, 0, 0, "6", "the routing number does not pass the check digit");
    }
    let tf = check_ach_text(e.account, 17, "6");
    if tf.kind != F_NONE { return tf; }
    if e.trace_number.len != 15 {
        return fault(F_LIMIT, 0, 0, "6", "the trace number is not 15 columns");
    }
    if !digits_ok(e.trace_number) {
        return fault(F_SYNTAX, 0, 0, "6", "the trace number holds a byte that is no digit");
    }
    if odfi_id.len != 8 || !digits_ok(odfi_id) {
        return fault(F_SYNTAX, 0, 0, "5", "the ODFI id is not 8 digits");
    }
    var i: i64 = 0;
    while i < 8 {
        if e.trace_number[i] != odfi_id[i] {
            return fault(F_TOTAL, 0, 0, "6", "the trace number does not start with the ODFI id");
        }
        i += 1;
    }
    return no_fault();
}

// hash_prefix gives the eight digit prefix of a routing number as a
// number. The caller checked the digits.
fn hash_prefix(routing: const u8[:]) -> i64 {
    var v: i64 = 0;
    var i: i64 = 0;
    while i < 8 {
        v = v * 10 + (routing[i] - '0') as i64;
        i += 1;
    }
    return v;
}

// write_ach_file_header writes record 1.
fn write_ach_file_header(out: u8[>..]&, h: AchFileHeader) -> Fault {
    let f = check_ach_text(h.destination_routing, 9, "1");
    if f.kind != F_NONE { return f; }
    if !routing_ok(h.destination_routing) {
        return fault(F_SYNTAX, 0, 0, "1", "the routing number does not pass the check digit");
    }
    if h.origin_id.len > 10 {
        return fault(F_LIMIT, 0, 0, "1", "the origin id is longer than the field holds");
    }
    let of = check_ach_text(h.origin_id, 10, "1");
    if of.kind != F_NONE { return of; }
    if h.id_modifier.len != 1 || h.id_modifier[0] < '0' || h.id_modifier[0] > 'z'
       || (h.id_modifier[0] > '9' && h.id_modifier[0] < 'A')
       || (h.id_modifier[0] > 'Z' && h.id_modifier[0] < 'a') {
        return fault(F_SYNTAX, 0, 0, "1", "the file id modifier is not one letter or digit");
    }
    out.push('1');
    put(out, "01");
    out.push(' ');
    put(out, h.destination_routing);
    var t: u8[>..] = [];
    let pf = put_text(t, h.origin_id, 10, "1");
    if pf.kind != F_NONE { return pf; }
    put(out, t);
    let df = put_date6(out, h.creation_year, h.creation_month, h.creation_day, "1");
    if df.kind != F_NONE { return df; }
    let tf = put_time4(out, h.creation_hour, h.creation_minute, "1");
    if tf.kind != F_NONE { return tf; }
    put(out, h.id_modifier);
    put(out, "094");
    put(out, "10");
    out.push('1');
    let nf = put_text(out, h.destination_name, 23, "1");
    if nf.kind != F_NONE { return nf; }
    let of2 = put_text(out, h.origin_name, 23, "1");
    if of2.kind != F_NONE { return of2; }
    return put_text(out, h.reference, 8, "1");
}

// write_ach_batch_header writes record 5.
fn write_ach_batch_header(out: u8[>..]&, b: AchBatch) -> Fault {
    if !service_class_ok(b.service_class) {
        return fault(F_SYNTAX, 0, 0, "5", "the service class is not 200, 220 or 225");
    }
    if !sec_ok(b.sec_code) {
        return fault(F_SYNTAX, 0, 0, "5", "the SEC code is not one of the codes of the package");
    }
    if b.originator_status < 0 || b.originator_status > 2 {
        return fault(F_SYNTAX, 0, 0, "5", "the originator status is not 0, 1 or 2");
    }
    if b.odfi_id.len != 8 || !digits_ok(b.odfi_id) {
        return fault(F_SYNTAX, 0, 0, "5", "the ODFI id is not 8 digits");
    }
    let of = check_ach_text(b.odfi_id, 8, "5");
    if of.kind != F_NONE { return of; }
    if b.batch_number < 1 || b.batch_number > 9999999 {
        return fault(F_LIMIT, 0, 0, "5", "the batch number is not between 1 and 9999999");
    }
    if b.effective_year < 0 || b.effective_month < 1 || b.effective_day < 1 {
        return fault(F_DATE, 0, 0, "5", "the effective date is missing or not valid");
    }
    out.push('5');
    let f = put_num(out, b.service_class, 3, "5");
    if f.kind != F_NONE { return f; }
    let f2 = put_text(out, b.company_name, 16, "5");
    if f2.kind != F_NONE { return f2; }
    let f3 = put_text(out, b.discretionary, 20, "5");
    if f3.kind != F_NONE { return f3; }
    let f4 = put_text(out, b.company_id, 10, "5");
    if f4.kind != F_NONE { return f4; }
    put(out, b.sec_code);
    let f5 = put_text(out, b.description, 10, "5");
    if f5.kind != F_NONE { return f5; }
    let f6 = put_text(out, b.descriptive_date, 6, "5");
    if f6.kind != F_NONE { return f6; }
    let f7 = put_date6(out, b.effective_year, b.effective_month, b.effective_day, "5");
    if f7.kind != F_NONE { return f7; }
    put(out, "   ");
    let f8 = put_num(out, b.originator_status, 1, "5");
    if f8.kind != F_NONE { return f8; }
    put(out, b.odfi_id);
    return put_num(out, b.batch_number, 7, "5");
}

// write_ach_entry writes record 6.
fn write_ach_entry(out: u8[>..]&, e: AchEntry) -> Fault {
    out.push('6');
    let f = put_num(out, e.transaction_code, 2, "6");
    if f.kind != F_NONE { return f; }
    put(out, e.rdfi_routing);
    let f2 = put_text(out, e.account, 17, "6");
    if f2.kind != F_NONE { return f2; }
    let f3 = put_num(out, e.amount, 10, "6");
    if f3.kind != F_NONE { return f3; }
    let f4 = put_text(out, e.individual_id, 15, "6");
    if f4.kind != F_NONE { return f4; }
    let f5 = put_text(out, e.individual_name, 22, "6");
    if f5.kind != F_NONE { return f5; }
    let f6 = put_text(out, e.discretionary, 2, "6");
    if f6.kind != F_NONE { return f6; }
    if e.addenda_count > 0 { out.push('1'); } else { out.push('0'); }
    put(out, e.trace_number);
    return no_fault();
}

// write_ach_addenda writes record 7. The sequence counts the addenda
// of one entry from one. The entry sequence is the last seven digits
// of the trace number of the entry.
fn write_ach_addenda(out: u8[>..]&, a: AchAddenda, seq: i64, trace_number: const u8[:]) -> Fault {
    out.push('7');
    put(out, "05");
    let f = put_text(out, a.text, 80, "7");
    if f.kind != F_NONE { return f; }
    let f2 = put_num(out, seq, 4, "7");
    if f2.kind != F_NONE { return f2; }
    var i: i64 = 8;
    while i < 15 { out.push(trace_number[i]); i += 1; }
    return no_fault();
}

// write_ach writes the whole file: the records of the header and the
// batches, the control records computed from the data, and the
// padding of nines. Every check runs before the first byte goes out.
fn write_ach(h: AchFileHeader, batches: AchBatch[>..]&, entries: AchEntry[>..]&,
             addenda: AchAddenda[>..]&, lim: Limits&, out: u8[>..]&) -> Fault {
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
    // the codes, the amounts and the trace numbers run here too, so a
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
        let bf = batch_entry_bounds(b, entries, addenda);
        if bf.kind != F_NONE { return bf; }
        if b.entry_count == 0 {
            return fault(F_SYNTAX, 0, 0, "5", "the batch holds no entry");
        }
        if b.entry_start as i64 != next {
            return fault(F_LIMIT, 0, 0, "5", "the entry ranges of the batches do not follow each other");
        }
        var cursor = next_add;
        var i = b.entry_start;
        while i < b.entry_start + b.entry_count {
            let e = entries[i];
            if e.addenda_start as i64 != cursor {
                return fault(F_LIMIT, 0, 0, "6", "the addenda ranges of the entries do not follow each other");
            }
            cursor += e.addenda_count as i64;
            let ef = check_entry(e, b.odfi_id, b.service_class, b.sec_code, is_reversal(b.description));
            if ef.kind != F_NONE { return ef; }
            if i > b.entry_start && !trace_after(e.trace_number, entries[i - 1].trace_number) {
                return fault(F_TOTAL, 0, 0, "6", "the trace numbers of the batch do not ascend");
            }
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
            var a = e.addenda_start;
            while a < e.addenda_start + e.addenda_count {
                let af = check_ach_text(addenda[a].text, 80, "7");
                if af.kind != F_NONE { return af; }
                a += 1;
            }
            i += 1;
        }
        next += b.entry_count as i64;
        next_add += entry_addenda_total(b, entries);
        q += 1;
    }
    if next != entries.len {
        return fault(F_LIMIT, 0, 0, "5", "the batches do not cover every entry");
    }
    if next_add != addenda.len {
        return fault(F_LIMIT, 0, 0, "5", "the entries do not cover every addendum");
    }
    // Count the records without the padding: the header, the batch
    // records and the file control.
    var records: i64 = 1;
    q = 0;
    while q < batches.len {
        let b = batches[q];
        records += 2 + b.entry_count as i64 + entry_addenda_total(b, entries);
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
        let bf = write_ach_batch_header(body, b);
        if bf.kind != F_NONE { return bf; }
        put_rec(body);
        var i = b.entry_start;
        while i < b.entry_start + b.entry_count {
            let e = entries[i];
            let ef = write_ach_entry(body, e);
            if ef.kind != F_NONE { return ef; }
            put_rec(body);
            var a = e.addenda_start;
            var seq: i64 = 1;
            while a < e.addenda_start + e.addenda_count {
                let af = write_ach_addenda(body, addenda[a], seq, e.trace_number);
                if af.kind != F_NONE { return af; }
                put_rec(body);
                seq += 1;
                a += 1;
            }
            i += 1;
        }
        let cf = write_ach_batch_control(body, b, entries);
        if cf.kind != F_NONE { return cf; }
        put_rec(body);
        q += 1;
    }
    let ff = write_ach_file_control(body, batches, total_count, total_hash, total_debit, total_credit, blocks);
    if ff.kind != F_NONE { return ff; }
    put_rec(body);
    let fill = blocks * 10 - records;
    var p: i64 = 0;
    while p < fill { put_nines(body); p += 1; }
    put(out, body);
    return no_fault();
}

// batch_totals gives the computed values of one batch: the count of
// the entries and the addenda, the hash, the debit total and the
// credit total. The caller checked the codes and the routing numbers.
fn batch_totals(b: AchBatch, entries: AchEntry[>..]&) -> i64, i64, i64, i64 {
    var count: i64 = 0;
    var hash: i64 = 0;
    var debit: i64 = 0;
    var credit: i64 = 0;
    var i = b.entry_start;
    while i < b.entry_start + b.entry_count {
        let e = entries[i];
        count += 1 + e.addenda_count as i64;
        let h, ok = checked_add(hash, hash_prefix(e.rdfi_routing));
        if ok { hash = h % 10000000000; }
        if ach_debit_code(e.transaction_code) {
            let d, ok2 = checked_add(debit, e.amount);
            if ok2 { debit = d; }
        } else {
            let c, ok3 = checked_add(credit, e.amount);
            if ok3 { credit = c; }
        }
        i += 1;
    }
    return count, hash, debit, credit;
}

// write_ach_batch_control writes record 8 from the computed totals.
fn write_ach_batch_control(out: u8[>..]&, b: AchBatch, entries: AchEntry[>..]&) -> Fault {
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
    let f6 = put_text(out, b.company_id, 10, "8");
    if f6.kind != F_NONE { return f6; }
    put(out, "                   ");
    put(out, "      ");
    put(out, b.odfi_id);
    return put_num(out, b.batch_number, 7, "8");
}

// write_ach_file_control writes record 9 from the totals of the whole
// file.
fn write_ach_file_control(out: u8[>..]&, batches: AchBatch[>..]&, total_count: i64,
                          total_hash: i64, total_debit: i64, total_credit: i64, blocks: i64) -> Fault {
    out.push('9');
    let f = put_num(out, batches.len, 6, "9");
    if f.kind != F_NONE { return f; }
    let f2 = put_num(out, blocks, 6, "9");
    if f2.kind != F_NONE { return f2; }
    let f3 = put_num(out, total_count, 8, "9");
    if f3.kind != F_NONE { return f3; }
    let f4 = put_num(out, total_hash, 10, "9");
    if f4.kind != F_NONE { return f4; }
    let f5 = put_num(out, total_debit, 12, "9");
    if f5.kind != F_NONE { return f5; }
    let f6 = put_num(out, total_credit, 12, "9");
    if f6.kind != F_NONE { return f6; }
    var i: i64 = 0;
    while i < 39 { out.push(' '); i += 1; }
    return no_fault();
}
