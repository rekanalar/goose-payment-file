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
    if code == "ACK" || code == "ATX" || code == "CIE" || code == "COR" || code == "DNE" { return true; }
    return code == "ENR" || code == "SHR" || code == "TRC" || code == "TRX" || code == "XCK"
        || code == "MTE";
}

// swapped_names tells whether the SEC code swaps the two text fields of
// the entry. CIE and MTE hold the name of 15 characters in columns 40 to
// 54 and the identification number of 22 characters in columns 55 to 76.
// Every other code holds the identification number of 15 characters
// first and the name of 22 characters second.
fn swapped_names(sec: const u8[:]) -> bool {
    return sec == "CIE" || sec == "MTE";
}

// blank_or_zero tells whether a text is empty or holds only spaces and
// zeros.
fn blank_or_zero(s: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < s.len {
        if s[i] != ' ' && s[i] != '0' { return false; }
        i += 1;
    }
    return true;
}

// name_rule_sec tells whether the SEC code needs a name that is not
// blank and not all zeros.
fn name_rule_sec(sec: const u8[:]) -> bool {
    if sec == "ARC" || sec == "BOC" || sec == "CIE" || sec == "DNE" || sec == "ENR" { return true; }
    if sec == "MTE" || sec == "POP" || sec == "PPD" || sec == "RCK" { return true; }
    return sec == "SHR" || sec == "TEL" || sec == "WEB";
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
// code may hold. PPD, CCD and WEB hold one. CTX, ATX and TRX hold
// many. ACK, CIE, DNE and ENR hold one. The rest hold none. A notice
// of change, a return or a terminal record stands alone beside this
// limit.
fn sec_addenda_max(sec: const u8[:]) -> i64 {
    if sec == "PPD" || sec == "CCD" || sec == "WEB" { return 1; }
    if sec == "CTX" || sec == "ATX" || sec == "TRX" { return 9999; }
    if sec == "ACK" || sec == "CIE" || sec == "DNE" || sec == "ENR" { return 1; }
    return 0;
}

// entry_addenda_max gives the most addenda that an entry may hold. A
// notice of change or a return rides on an entry of any SEC code and
// stands alone. The other addenda follow the limit of the SEC code. An
// entry never mixes the kinds.
fn entry_addenda_max(sec: const u8[:], e: AchEntry, addenda: AchAddenda[>..]&) -> i64 {
    if e.addenda_count > 0 && e.addenda_start >= 0 && e.addenda_start < addenda.len
       && addenda[e.addenda_start].kind != 5 {
        return 1;
    }
    return sec_addenda_max(sec);
}

// catx_count_fault checks the addenda records count of an ATX or TRX
// entry. The count stands in the first four columns of the
// individual name and must equal the count of the addenda 05 records.
fn catx_count_fault(e: AchEntry, addenda: AchAddenda[>..]&) -> Fault {
    if e.addenda_count <= 0 { return no_fault(); }
    if e.addenda_start < 0 || e.addenda_start >= addenda.len { return no_fault(); }
    if addenda[e.addenda_start].kind != 5 { return no_fault(); }
    if e.individual_name.len < 4 {
        return fault(F_LIMIT, 0, 0, "6", "the addenda count of the entry is not 4 columns");
    }
    var v: i64 = 0;
    var i: i64 = 0;
    while i < 4 {
        let c = e.individual_name[i];
        if c < '0' || c > '9' {
            return fault(F_SYNTAX, 0, 0, "6", "the addenda count of the entry holds a byte that is no digit");
        }
        v = v * 10 + (c - '0') as i64;
        i += 1;
    }
    if v != e.addenda_count as i64 {
        return fault(F_TOTAL, 0, 0, "6", "the addenda count of the entry does not match the records");
    }
    return no_fault();
}

// card_expiry_fault checks the card expiration date of a SHR entry.
// The date holds MMYY in the first four columns of the entry id. The
// month is 01 to 12 and the year is 18 to 50.
fn card_expiry_fault(id: const u8[:]) -> Fault {
    if id.len < 4 {
        return fault(F_LIMIT, 0, 0, "6", "the card expiration date of the entry is not 4 columns");
    }
    var i: i64 = 0;
    while i < 4 {
        let c = id[i];
        if c < '0' || c > '9' {
            return fault(F_SYNTAX, 0, 0, "6", "the card expiration date holds a byte that is no digit");
        }
        i += 1;
    }
    let month = (id[0] - '0') as i64 * 10 + (id[1] - '0') as i64;
    let year = (id[2] - '0') as i64 * 10 + (id[3] - '0') as i64;
    if month < 1 || month > 12 {
        return fault(F_DATE, 0, 0, "6", "the card expiration month is not 01 to 12");
    }
    if year < 18 || year > 50 {
        return fault(F_DATE, 0, 0, "6", "the card expiration year is not 18 to 50");
    }
    return no_fault();
}

// sec_entry_fault applies the rules of the SEC code to one entry.
// TEL, ARC, BOC, POP and RCK hold debits only, and a reversal batch
// holds credits only. ARC holds at most 25000.00 and RCK at most
// 2500.00 per entry. The new codes take the service class and the
// addenda of the entry: ACK, ATX, CIE, COR, DNE, ENR, SHR, TRC, TRX
// and XCK.
fn sec_entry_fault(sec: const u8[:], reversal: bool, code: i64, amount: i64,
                   service_class: i64, e: AchEntry) -> Fault {
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
    if name_rule_sec(sec) && blank_or_zero(e.individual_name) {
        return fault(F_SYNTAX, 0, 0, "6", "the individual name is blank or all zeros");
    }
    // MTE: a cash withdrawal holds an amount and an identification number.
    if sec == "MTE" {
        if amount == 0 {
            return fault(F_AMOUNT, 0, 0, "6", "an MTE entry holds an amount above zero");
        }
        if blank_or_zero(e.individual_id) {
            return fault(F_SYNTAX, 0, 0, "6", "the identification number is blank or all zeros");
        }
    }
    // ACK: zero dollar remittance credit prenotes only.
    if sec == "ACK" {
        if code != 23 && code != 33 {
            return fault(F_SYNTAX, 0, 0, "6", "an ACK entry holds the code 23 or 33 only");
        }
    }
    // ATX: prenote credits and the credit of a return or notice.
    if sec == "ATX" {
        if code != 23 && code != 33 && code != 21 {
            return fault(F_SYNTAX, 0, 0, "6", "an ATX entry holds the code 23, 33 or 21 only");
        }
    }
    // CIE: credits only.
    if sec == "CIE" && !ach_credit_code(code) {
        return fault(F_TOTAL, 0, 0, "6", "a CIE entry holds a credit code only");
    }
    // COR: returns and notices only.
    if sec == "COR" {
        if code != 21 && code != 31 {
            return fault(F_SYNTAX, 0, 0, "6", "a COR entry holds the code 21 or 31 only");
        }
    }
    // DNE and ENR: the codes of the record.
    if sec == "DNE" {
        if code != 23 && code != 33 {
            return fault(F_SYNTAX, 0, 0, "6", "a DNE entry holds the code 23 or 33 only");
        }
    }
    if sec == "ENR" {
        if code != 23 && code != 33 && code != 21 && code != 31 {
            return fault(F_SYNTAX, 0, 0, "6", "an ENR entry holds the code 23, 33, 21 or 31 only");
        }
    }
    // SHR: the card transaction type and the card expiration date.
    if sec == "SHR" {
        if !card_type_ok(e.discretionary) {
            return fault(F_SYNTAX, 0, 0, "6", "the card transaction type is not in the card list");
        }
        let xf = card_expiry_fault(e.individual_id);
        if xf.kind != F_NONE { return xf; }
    }
    // TRC, TRX and XCK: a batch of credits only takes credits, every
    // other batch takes debits.
    if sec == "TRC" || sec == "TRX" || sec == "XCK" {
        if service_class == 220 && !reversal {
            if ach_debit_code(code) {
                return fault(F_TOTAL, 0, 0, "6", "a batch of credits only holds a debit");
            }
        } else {
            if ach_credit_code(code) {
                return fault(F_TOTAL, 0, 0, "6", "this SEC code holds debits only");
            }
        }
    }
    if sec == "XCK" && amount > 250000 {
        return fault(F_AMOUNT, 0, 0, "6", "an XCK entry holds at most 2500.00");
    }
    return no_fault();
}

// sec_entry_addenda_fault applies the rules of the SEC code that
// need the addenda of the entry: the addenda 98 of a COR entry, the
// one addenda 05 of DNE and ENR, and the addenda count of ATX and
// TRX.
fn sec_entry_addenda_fault(sec: const u8[:], e: AchEntry, addenda: AchAddenda[>..]&) -> Fault {
    let takes_terminal = sec == "SHR" || sec == "MTE";
    if e.addenda_count > 0 && e.addenda_start >= 0 && e.addenda_start < addenda.len
       && addenda[e.addenda_start].kind == 2 && !takes_terminal {
        return fault(F_LIMIT, 0, 0, "7", "a terminal record rides on a SHR or MTE entry only");
    }
    if takes_terminal {
        if e.addenda_count != 1 || e.addenda_start < 0 || e.addenda_start >= addenda.len
           || addenda[e.addenda_start].kind != 2 {
            return fault(F_LIMIT, 0, 0, "7", "a SHR or MTE entry carries one terminal record");
        }
    }
    if sec == "COR" {
        if e.addenda_count < 1 || e.addenda_start < 0 || e.addenda_start >= addenda.len
           || addenda[e.addenda_start].kind != 98 {
            return fault(F_LIMIT, 0, 0, "7", "a COR entry carries an addenda 98");
        }
    }
    if sec == "DNE" || sec == "ENR" {
        if e.addenda_count == 0 {
            if sec == "DNE" {
                return fault(F_LIMIT, 0, 0, "7", "a DNE entry carries one addenda 05");
            }
            return fault(F_LIMIT, 0, 0, "7", "an ENR entry carries one addenda 05");
        }
        if e.addenda_start >= 0 && e.addenda_start < addenda.len
           && addenda[e.addenda_start].kind == 5 && e.addenda_count != 1 {
            return fault(F_LIMIT, 0, 0, "7", "this SEC code entry carries exactly one addenda 05");
        }
    }
    if sec == "ATX" || sec == "TRX" {
        let cf = catx_count_fault(e, addenda);
        if cf.kind != F_NONE { return cf; }
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

// service_class_fault gives the fault of a transaction code that moves
// money against the service class of its batch. The caller gives the
// line and the column of the record.
fn service_class_fault(service_class: i64, code: i64) -> Fault {
    if service_class == 220 && ach_debit_code(code) {
        return fault(F_TOTAL, 0, 0, "6", "a batch of credits only holds a debit");
    }
    if service_class == 225 && ach_credit_code(code) {
        return fault(F_TOTAL, 0, 0, "6", "a batch of debits only holds a credit");
    }
    return no_fault();
}

// check_entry checks one entry before any byte goes out: the code,
// the routing number, the amount, the trace number and the ranges.
fn check_entry(e: AchEntry, odfi_id: const u8[:], service_class: i64, sec: const u8[:],
               reversal: bool, add_max: i64, addenda: AchAddenda[>..]&) -> Fault {
    if !ach_code_ok(e.transaction_code) {
        return fault(F_SYNTAX, 0, 0, "6", "the transaction code is not in the NACHA set");
    }
    let df = service_class_fault(service_class, e.transaction_code);
    if df.kind != F_NONE { return df; }
    let sf = sec_entry_fault(sec, reversal, e.transaction_code, e.amount, service_class, e);
    if sf.kind != F_NONE { return sf; }
    let af = sec_entry_addenda_fault(sec, e, addenda);
    if af.kind != F_NONE { return af; }
    if e.addenda_count as i64 > add_max {
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
    // The service class 280 belongs to the SEC code ADV and to no other.
    if !service_class_ok(b.service_class) && b.service_class != 280 {
        return fault(F_SYNTAX, 0, 0, "5", "the service class is not 200, 220, 225 or 280");
    }
    if !sec_ok(b.sec_code) && b.sec_code != "ADV" {
        return fault(F_SYNTAX, 0, 0, "5", "the SEC code is not one of the codes of the package");
    }
    if (b.service_class == 280) != (b.sec_code == "ADV") {
        return fault(F_SYNTAX, 0, 0, "5", "the service class 280 and the SEC code ADV go together");
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
fn write_ach_entry(out: u8[>..]&, e: AchEntry, sec: const u8[:]) -> Fault {
    out.push('6');
    let f = put_num(out, e.transaction_code, 2, "6");
    if f.kind != F_NONE { return f; }
    put(out, e.rdfi_routing);
    let f2 = put_text(out, e.account, 17, "6");
    if f2.kind != F_NONE { return f2; }
    let f3 = put_num(out, e.amount, 10, "6");
    if f3.kind != F_NONE { return f3; }
    var first = e.individual_id;
    var second = e.individual_name;
    if swapped_names(sec) {
        first = e.individual_name;
        second = e.individual_id;
    }
    let f4 = put_text(out, first, 15, "6");
    if f4.kind != F_NONE { return f4; }
    let f5 = put_text(out, second, 22, "6");
    if f5.kind != F_NONE { return f5; }
    let f6 = put_text(out, e.discretionary, 2, "6");
    if f6.kind != F_NONE { return f6; }
    if e.addenda_count > 0 { out.push('1'); } else { out.push('0'); }
    put(out, e.trace_number);
    return no_fault();
}

// check_ach_addenda checks one addenda record before any byte goes
// out. The kind picks the checks: the code lists, the widths and the
// digit fields of the notice and the return.
fn check_ach_addenda(a: AchAddenda) -> Fault {
    if a.kind == 5 {
        return check_ach_text(a.text, 80, "7");
    }
    if a.kind == 2 {
        let f = check_ach_text(a.ref_one, 7, "7");
        if f.kind != F_NONE { return f; }
        let f2 = check_ach_text(a.ref_two, 3, "7");
        if f2.kind != F_NONE { return f2; }
        let f3 = check_ach_text(a.terminal_id, 6, "7");
        if f3.kind != F_NONE { return f3; }
        let f4 = check_ach_text(a.serial, 6, "7");
        if f4.kind != F_NONE { return f4; }
        if a.date_month < 1 || a.date_month > 12 || a.date_day < 1 || a.date_day > 31 {
            return fault(F_DATE, 0, 0, "7", "the transaction date of the terminal record is not a civil day");
        }
        let f5 = check_ach_text(a.auth_code, 6, "7");
        if f5.kind != F_NONE { return f5; }
        let f6 = check_ach_text(a.location, 27, "7");
        if f6.kind != F_NONE { return f6; }
        let f7 = check_ach_text(a.city, 15, "7");
        if f7.kind != F_NONE { return f7; }
        if !us_state_ok(a.state) {
            return fault(F_SYNTAX, 0, 0, "7", "the terminal state is not a state or territory of the United States");
        }
        return no_fault();
    }
    if a.kind == 98 {
        if !noc_code_ok(a.change_code) {
            return fault(F_SYNTAX, 0, 0, "7", "the change code is not in the notice list");
        }
        if !digits_width(a.original_trace, 15) {
            return fault(F_SYNTAX, 0, 0, "7", "the original trace number is not 15 digits");
        }
        if !digits_width(a.original_dfi, 8) {
            return fault(F_SYNTAX, 0, 0, "7", "the original DFI number is not 8 digits");
        }
        return check_ach_text(a.corrected_data, 29, "7");
    }
    if a.kind == 99 {
        if a.form == 1 {
            return check_ach_dishonored(a);
        }
        if a.form == 2 {
            return check_ach_contested(a);
        }
        if dishonor_code_ok(a.return_code) || contest_code_ok(a.return_code) {
            return fault(F_SYNTAX, 0, 0, "7", "this return code needs the dishonored or the contested form");
        }
        if !return_code_ok(a.return_code) {
            return fault(F_SYNTAX, 0, 0, "7", "the return code is not in the return reason list");
        }
        if !digits_width(a.original_trace, 15) {
            return fault(F_SYNTAX, 0, 0, "7", "the original trace number is not 15 digits");
        }
        if !digits_width(a.original_dfi, 8) {
            return fault(F_SYNTAX, 0, 0, "7", "the original DFI number is not 8 digits");
        }
        if a.death_month > 0 || a.death_day > 0 || a.death_year > 0 {
            if a.death_year < 2000 || a.death_year > 2099
               || !finance::date_ok(a.death_year as i64, a.death_month as i64, a.death_day as i64) {
                return fault(F_DATE, 0, 0, "7", "the date of death is not a civil date in 2000 to 2099");
            }
        }
        return check_ach_text(a.addenda_information, 44, "7");
    }
    return fault(F_UNKNOWN_TAG, 0, 0, "7", "the addenda kind is not 2, 5, 98 or 99");
}

// settlement_ok tells whether a number is a day of the year.
fn settlement_ok(day: i32) -> bool {
    return day >= 1 && day <= 366;
}

// check_ach_dishonored checks the dishonored form of addenda 99.
fn check_ach_dishonored(a: AchAddenda) -> Fault {
    if !dishonor_code_ok(a.return_code) {
        return fault(F_SYNTAX, 0, 0, "7", "the dishonored return code is not in the dishonored list");
    }
    if !digits_width(a.original_trace, 15) {
        return fault(F_SYNTAX, 0, 0, "7", "the original trace number is not 15 digits");
    }
    if !digits_width(a.original_dfi, 8) {
        return fault(F_SYNTAX, 0, 0, "7", "the original DFI number is not 8 digits");
    }
    if !digits_width(a.return_trace, 15) {
        return fault(F_SYNTAX, 0, 0, "7", "the return trace number is not 15 digits");
    }
    if !settlement_ok(a.return_settlement) {
        return fault(F_DATE, 0, 0, "7", "the return settlement date is not a day of the year");
    }
    if !digits_width(a.return_reason, 2) {
        return fault(F_SYNTAX, 0, 0, "7", "the return reason code is not two digits");
    }
    return check_ach_text(a.addenda_information, 21, "7");
}

// check_ach_contested checks the contested form of addenda 99.
fn check_ach_contested(a: AchAddenda) -> Fault {
    if !contest_code_ok(a.return_code) {
        return fault(F_SYNTAX, 0, 0, "7", "the contested return code is not in the contested list");
    }
    if !digits_width(a.original_trace, 15) {
        return fault(F_SYNTAX, 0, 0, "7", "the original trace number is not 15 digits");
    }
    if !digits_width(a.original_dfi, 8) {
        return fault(F_SYNTAX, 0, 0, "7", "the original DFI number is not 8 digits");
    }
    if !digits_width(a.date_returned, 6) {
        return fault(F_SYNTAX, 0, 0, "7", "the date of the returned entry is not 6 digits");
    }
    let month = (a.date_returned[2] - '0') as i64 * 10 + (a.date_returned[3] - '0') as i64;
    let day = (a.date_returned[4] - '0') as i64 * 10 + (a.date_returned[5] - '0') as i64;
    if month < 1 || month > 12 || day < 1 || day > 31 {
        return fault(F_DATE, 0, 0, "7", "the date of the returned entry is not a civil day");
    }
    if !settlement_ok(a.original_settlement) {
        return fault(F_DATE, 0, 0, "7", "the original settlement date is not a day of the year");
    }
    if !settlement_ok(a.return_settlement) {
        return fault(F_DATE, 0, 0, "7", "the return settlement date is not a day of the year");
    }
    if !settlement_ok(a.dishonored_settlement) {
        return fault(F_DATE, 0, 0, "7", "the dishonored settlement date is not a day of the year");
    }
    if !digits_width(a.return_reason, 2) {
        return fault(F_SYNTAX, 0, 0, "7", "the return reason code is not two digits");
    }
    if !digits_width(a.dishonored_reason, 2) {
        return fault(F_SYNTAX, 0, 0, "7", "the dishonored reason code is not two digits");
    }
    if !digits_width(a.return_trace, 15) {
        return fault(F_SYNTAX, 0, 0, "7", "the return trace number is not 15 digits");
    }
    if !digits_width(a.dishonored_trace, 15) {
        return fault(F_SYNTAX, 0, 0, "7", "the dishonored trace number is not 15 digits");
    }
    return no_fault();
}

// write_ach_addenda writes record 7. The columns mirror the reader
// in read_ach.goose: the same widths, in the same order. The
// sequence counts the addenda of one entry from one. The entry sequence is the last seven digits
// of the trace number of the entry. A notice of change and a return
// carry their own layouts and no sequence.
fn write_ach_addenda(out: u8[>..]&, a: AchAddenda, seq: i64, trace_number: const u8[:]) -> Fault {
    out.push('7');
    if a.kind == 2 {
        put(out, "02");
        let f = put_text(out, a.ref_one, 7, "7");
        if f.kind != F_NONE { return f; }
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
        let fa = put_text(out, a.state, 2, "7");
        if fa.kind != F_NONE { return fa; }
        let fb = put_text(out, trace_number, 15, "7");
        if fb.kind != F_NONE { return fb; }
        return no_fault();
    }
    if a.kind == 98 {
        put(out, "98");
        let f = put_text(out, a.change_code, 3, "7");
        if f.kind != F_NONE { return f; }
        let f2 = put_text(out, a.original_trace, 15, "7");
        if f2.kind != F_NONE { return f2; }
        put(out, "      ");
        let f3 = put_text(out, a.original_dfi, 8, "7");
        if f3.kind != F_NONE { return f3; }
        let f4 = put_text(out, a.corrected_data, 29, "7");
        if f4.kind != F_NONE { return f4; }
        put(out, "      ");
        put(out, "         ");
        let f5 = put_text(out, trace_number, 15, "7");
        if f5.kind != F_NONE { return f5; }
        return no_fault();
    }
    if a.kind == 99 {
        put(out, "99");
        let f = put_text(out, a.return_code, 3, "7");
        if f.kind != F_NONE { return f; }
        if a.form == 1 {
            let f1 = put_text(out, a.original_trace, 15, "7");
            if f1.kind != F_NONE { return f1; }
            put(out, "      ");
            let f2 = put_text(out, a.original_dfi, 8, "7");
            if f2.kind != F_NONE { return f2; }
            put(out, "   ");
            let f3 = put_text(out, a.return_trace, 15, "7");
            if f3.kind != F_NONE { return f3; }
            let f4 = put_num(out, a.return_settlement as i64, 3, "7");
            if f4.kind != F_NONE { return f4; }
            let f5 = put_text(out, a.return_reason, 2, "7");
            if f5.kind != F_NONE { return f5; }
            let f6 = put_text(out, a.addenda_information, 21, "7");
            if f6.kind != F_NONE { return f6; }
            let f7 = put_text(out, trace_number, 15, "7");
            if f7.kind != F_NONE { return f7; }
            return no_fault();
        }
        if a.form == 2 {
            let f1 = put_text(out, a.original_trace, 15, "7");
            if f1.kind != F_NONE { return f1; }
            let f2 = put_text(out, a.date_returned, 6, "7");
            if f2.kind != F_NONE { return f2; }
            let f3 = put_text(out, a.original_dfi, 8, "7");
            if f3.kind != F_NONE { return f3; }
            let f4 = put_num(out, a.original_settlement as i64, 3, "7");
            if f4.kind != F_NONE { return f4; }
            let f5 = put_text(out, a.return_trace, 15, "7");
            if f5.kind != F_NONE { return f5; }
            let f6 = put_num(out, a.return_settlement as i64, 3, "7");
            if f6.kind != F_NONE { return f6; }
            let f7 = put_text(out, a.return_reason, 2, "7");
            if f7.kind != F_NONE { return f7; }
            let f8 = put_text(out, a.dishonored_trace, 15, "7");
            if f8.kind != F_NONE { return f8; }
            let f9 = put_num(out, a.dishonored_settlement as i64, 3, "7");
            if f9.kind != F_NONE { return f9; }
            let fa = put_text(out, a.dishonored_reason, 2, "7");
            if fa.kind != F_NONE { return fa; }
            put(out, " ");
            let fb = put_text(out, trace_number, 15, "7");
            if fb.kind != F_NONE { return fb; }
            return no_fault();
        }
        let f2 = put_text(out, a.original_trace, 15, "7");
        if f2.kind != F_NONE { return f2; }
        if a.death_year > 0 {
            let f3 = put_date6(out, a.death_year, a.death_month, a.death_day, "7");
            if f3.kind != F_NONE { return f3; }
        } else {
            put(out, "      ");
        }
        let f4 = put_text(out, a.original_dfi, 8, "7");
        if f4.kind != F_NONE { return f4; }
        let f5 = put_text(out, a.addenda_information, 44, "7");
        if f5.kind != F_NONE { return f5; }
        let f6 = put_text(out, trace_number, 15, "7");
        if f6.kind != F_NONE { return f6; }
        return no_fault();
    }
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
            let add_max = entry_addenda_max(b.sec_code, e, addenda);
            let ef = check_entry(e, b.odfi_id, b.service_class, b.sec_code, is_reversal(b.description), add_max, addenda);
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
                let af = check_ach_addenda(addenda[a]);
                if af.kind != F_NONE { return af; }
                if addenda[a].kind != addenda[e.addenda_start].kind {
                    return fault(F_SYNTAX, 0, 0, "7", "an entry mixes addenda of two kinds");
                }
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
        if b.sec_code == "ADV" {
            return fault(F_SYNTAX, 0, 0, "5", "an advice batch needs write_ach_adv");
        }
        let bf = write_ach_batch_header(body, b);
        if bf.kind != F_NONE { return bf; }
        put_rec(body);
        var i = b.entry_start;
        while i < b.entry_start + b.entry_count {
            let e = entries[i];
            let ef = write_ach_entry(body, e, b.sec_code);
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
    let ff = write_ach_file_control(body, batches.len, total_count, total_hash, total_debit, total_credit, blocks);
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
fn batch_totals<B, E>(b: B, entries: E[>..]&) -> i64, i64, i64, i64 {
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
fn write_ach_file_control(out: u8[>..]&, batch_count: i64, total_count: i64,
                          total_hash: i64, total_debit: i64, total_credit: i64, blocks: i64) -> Fault {
    out.push('9');
    let f = put_num(out, batch_count, 6, "9");
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
