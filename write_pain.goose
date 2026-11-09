// The writer of the pain.001 credit transfer.
//
// The writer emits the pain.001.001.03 form: a Document element with
// the pain.001 namespace, a group header, one PmtInf element per
// payment block, and one CdtTrfTxInf element per item. The control
// sum comes from the items, never from the caller. Every text passes
// the EPC set and its length limit, and every escape character
// becomes an entity.
namespace payment_file;

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import fault;
import model;
import charset;
import control;
import enums;

// PainWriteOptions holds the switches of the writer.
struct PainWriteOptions {
    epc_charset: bool,
    indent: bool,
}

// put escapes a text and appends it. The caller checked the text
// before the call.
fn put_escaped(out: u8[>..]&, text: const u8[:]) {
    var i: i64 = 0;
    while i < text.len {
        let c = text[i];
        if c == '&' { put(out, "&amp;"); }
        else if c == '<' { put(out, "&lt;"); }
        else if c == '>' { put(out, "&gt;"); }
        else { out.push(c); }
        i += 1;
    }
}

// leaf writes an element with a text: <tag>text</tag>.
fn leaf(out: u8[>..]&, tag: const u8[:], text: const u8[:], depth: i64, opts: PainWriteOptions) {
    if opts.indent { var i: i64 = 0; while i < depth { put(out, "  "); i += 1; } }
    out.push('<'); put(out, tag); out.push('>');
    put_escaped(out, text);
    put(out, "</"); put(out, tag); out.push('>');
    if opts.indent { out.push('\n'); }
}

// open writes an open tag and close writes the close tag.
fn open(out: u8[>..]&, tag: const u8[:], depth: i64, opts: PainWriteOptions) {
    if opts.indent { var i: i64 = 0; while i < depth { put(out, "  "); i += 1; } }
    out.push('<'); put(out, tag); out.push('>');
    if opts.indent { out.push('\n'); }
}

fn close(out: u8[>..]&, tag: const u8[:], depth: i64, opts: PainWriteOptions) {
    if opts.indent { var i: i64 = 0; while i < depth { put(out, "  "); i += 1; } }
    put(out, "</"); put(out, tag); out.push('>');
    if opts.indent { out.push('\n'); }
}

// text_leaf checks a text and writes it as a leaf. An empty text is a
// fault when the schema requires the element.
fn text_leaf(out: u8[>..]&, tag: const u8[:], text: const u8[:], max: i64, required: bool,
             depth: i64, opts: PainWriteOptions, lim: Limits&) -> Fault {
    let f = check_text(text, max, tag, opts.epc_charset, lim);
    if f.kind != F_NONE { return f; }
    if required && text.len == 0 { return fault(F_SYNTAX, 0, 0, tag, "the required text is empty"); }
    leaf(out, tag, text, depth, opts);
    return no_fault();
}

// party writes a party element with its name. The name limit is the
// limit of the EPC rulebook, not the one of the schema.
fn party(out: u8[>..]&, tag: const u8[:], name: const u8[:], depth: i64,
         opts: PainWriteOptions, lim: Limits&) -> Fault {
    open(out, tag, depth, opts);
    let f = text_leaf(out, "Nm", name, 70, true, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    close(out, tag, depth, opts);
    return no_fault();
}

// account writes an account element with an IBAN that passes the check
// digits.
fn account(out: u8[>..]&, tag: const u8[:], iban: const u8[:], depth: i64,
           opts: PainWriteOptions, lim: Limits&) -> Fault {
    if !payment_identifier::iban_is_valid(iban) {
        return fault(F_IBAN, 0, 0, tag, "the IBAN does not pass the check digits");
    }
    open(out, tag, depth, opts);
    open(out, "Id", depth + 1, opts);
    let f = text_leaf(out, "IBAN", iban, 34, true, depth + 2, opts, lim);
    if f.kind != F_NONE { return f; }
    close(out, "Id", depth + 1, opts);
    close(out, tag, depth, opts);
    return no_fault();
}

// agent writes an agent element. The BIC may be empty.
fn agent(out: u8[>..]&, tag: const u8[:], bic: const u8[:], depth: i64,
         opts: PainWriteOptions, lim: Limits&) -> Fault {
    open(out, tag, depth, opts);
    open(out, "FinInstnId", depth + 1, opts);
    if bic.len > 0 {
        if !bic_ok(bic) { return fault(F_SYNTAX, 0, 0, "BIC", "the BIC is not 8 or 11 capital letters and digits"); }
        let f = text_leaf(out, "BIC", bic, 11, true, depth + 2, opts, lim);
        if f.kind != F_NONE { return f; }
    }
    close(out, "FinInstnId", depth + 1, opts);
    close(out, tag, depth, opts);
    return no_fault();
}

// write_group checks the header and writes everything up to the end
// of the group header: the declaration, the Document element, the
// container element and the group header. The count and the total
// come from the items.
fn write_group(out: u8[>..]&, schema: const u8[:], container: const u8[:], header: GrpHeader,
               count: i64, total: i64, ccy: const u8[:], opts: PainWriteOptions, lim: Limits&) -> Fault {
    if !header.has_creation || !finance::date_ok(header.creation_year as i64, header.creation_month as i64, header.creation_day as i64)
       || header.creation_minutes < 0 || header.creation_minutes >= 1440 {
        return fault(F_DATE, 0, 0, "CreDtTm", "the creation time is missing or not valid");
    }
    var cs: u8[>..] = [];
    let cf = amount_text(&cs, total, ccy);
    if cf.kind != F_NONE { return cf; }
    put(out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
    if opts.indent { out.push('\n'); }
    put(out, "<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:"); put(out, schema); put(out, "\">");
    if opts.indent { out.push('\n'); }
    open(out, container, 1, opts);
    open(out, "GrpHdr", 2, opts);
    let mf = text_leaf(out, "MsgId", header.message_id, 35, true, 3, opts, lim);
    if mf.kind != F_NONE { return mf; }
    var dt: u8[>..] = [];
    put_dt(&dt, header);
    leaf(out, "CreDtTm", dt, 3, opts);
    var nb: u8[>..] = [];
    put_count(&nb, count);
    leaf(out, "NbOfTxs", nb, 3, opts);
    leaf(out, "CtrlSum", cs, 3, opts);
    // The EPC rulebook limit of 70 holds for the initiator too.
    let pf = party(out, "InitgPty", header.initiator, 3, opts, lim);
    if pf.kind != F_NONE { return pf; }
    close(out, "GrpHdr", 2, opts);
    return no_fault();
}

// flag_leaf writes a boolean element as true or false.
fn flag_leaf(out: u8[>..]&, tag: const u8[:], v: bool, depth: i64, opts: PainWriteOptions) {
    if v { leaf(out, tag, "true", depth, opts); }
    else { leaf(out, tag, "false", depth, opts); }
}

// amt_leaf writes an amount element with its currency attribute:
// <tag Ccy="EUR">12.34</tag>.
fn amt_leaf(out: u8[>..]&, tag: const u8[:], minor: i64, code: const u8[:], depth: i64, opts: PainWriteOptions) -> Fault {
    var at: u8[>..] = [];
    let f = amount_text(at, minor, code);
    if f.kind != F_NONE { return f; }
    if opts.indent { var w: i64 = 0; while w < depth { put(out, "  "); w += 1; } }
    out.push('<'); put(out, tag); put(out, " Ccy=\""); put(out, code); put(out, "\">");
    put(out, at);
    put(out, "</"); put(out, tag); out.push('>');
    if opts.indent { out.push('\n'); }
    return no_fault();
}

// instd_amt writes the InstdAmt element with its currency attribute.
fn instd_amt(out: u8[>..]&, minor: i64, code: const u8[:], depth: i64, opts: PainWriteOptions) -> Fault {
    return amt_leaf(out, "InstdAmt", minor, code, depth, opts);
}

// date_leaf writes a date element. A date that is no civil date is a fault.
fn date_leaf(out: u8[>..]&, tag: const u8[:], y: i32, m: i32, d: i32, depth: i64, opts: PainWriteOptions) -> Fault {
    if !finance::date_ok(y as i64, m as i64, d as i64) {
        return fault(F_DATE, 0, 0, tag, "the date is missing or not valid");
    }
    var t: u8[>..] = [];
    put_day(t, y, m, d);
    leaf(out, tag, t, depth, opts);
    return no_fault();
}

// write_pain001 writes the credit transfer initiation. The payments
// and the items live in flat arrays. The control sum of the group
// header is the sum over every item. The elements follow the order of
// the schema, which is a sequence.
fn write_pain001(header: GrpHeader, payments: PaymentInfo[>..]&, items: CreditTransfer[>..]&,
                 opts: PainWriteOptions, lim: Limits&, out: u8[>..]&) -> Fault {
    if payments.len > lim.max_payments {
        return fault(F_LIMIT, 0, 0, "PmtInf", "more payment blocks than the limits allow");
    }
    if items.len > lim.max_items {
        return fault(F_LIMIT, 0, 0, "CdtTrfTxInf", "more items than the limits allow");
    }
    if payments.len == 0 {
        return fault(F_SYNTAX, 0, 0, "PmtInf", "the message holds no payment block");
    }
    if items.len == 0 {
        return fault(F_SYNTAX, 0, 0, "CdtTrfTxInf", "the message holds no credit transfer item");
    }
    // The blocks must tile the items: each item sits in exactly one block.
    var next: i64 = 0;
    var q: i64 = 0;
    while q < payments.len {
        if payments[q].item_start as i64 != next {
            return fault(F_LIMIT, 0, 0, "PmtInf", "the item ranges of the blocks do not follow each other");
        }
        next += payments[q].item_count as i64;
        q += 1;
    }
    if next != items.len { return fault(F_LIMIT, 0, 0, "PmtInf", "the blocks do not cover every item"); }
    // Check the whole message before the first byte goes out.
    let total, sf = sum_range(items, 0, items.len);
    if sf.kind != F_NONE { return sf; }
    let gf = write_group(out, "pain.001.001.03", "CstmrCdtTrfInitn", header, items.len, total, items[0].amount.code, opts, lim);
    if gf.kind != F_NONE { return gf; }
    var p: i64 = 0;
    while p < payments.len {
        let pf = write_pmt_inf(out, payments[p], items, opts, lim);
        if pf.kind != F_NONE { return pf; }
        p += 1;
    }
    close(out, "CstmrCdtTrfInitn", 1, opts);
    close(out, "Document", 0, opts);
    return no_fault();
}

// write_pmt_inf writes one payment block and its items.
fn write_pmt_inf(out: u8[>..]&, pay: PaymentInfo, items: CreditTransfer[>..]&,
                 opts: PainWriteOptions, lim: Limits&) -> Fault {
    let start = pay.item_start as i64;
    let count = pay.item_count as i64;
    let sum, sf = sum_range(items, start, count);
    if sf.kind != F_NONE { return sf; }
    if count == 0 { return fault(F_SYNTAX, 0, 0, "PmtInf", "the payment block holds no item"); }
    var cs: u8[>..] = [];
    let cf = amount_text(&cs, sum, items[start].amount.code);
    if cf.kind != F_NONE { return cf; }
    if !pay.has_execution_date {
        return fault(F_DATE, 0, 0, "ReqdExctnDt", "the execution date is missing or not valid");
    }
    open(out, "PmtInf", 2, opts);
    var f = text_leaf(out, "PmtInfId", pay.id, 35, true, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    if pay.method.len > 0 && !pay_method_ok(pay.method) {
        return fault(F_SYNTAX, 0, 0, "PmtMtd", "the payment method is not TRF, CHK or TRA");
    }
    // An empty method means a credit transfer.
    if pay.method.len == 0 { f = text_leaf(out, "PmtMtd", "TRF", 3, true, 3, opts, lim); }
    else { f = text_leaf(out, "PmtMtd", pay.method, 3, true, 3, opts, lim); }
    if f.kind != F_NONE { return f; }
    if pay.has_batch_booking {
        flag_leaf(out, "BtchBookg", pay.batch_booking, 3, opts);
    }
    var nb: u8[>..] = [];
    put_count(&nb, count);
    leaf(out, "NbOfTxs", nb, 3, opts);
    leaf(out, "CtrlSum", cs, 3, opts);
    f = date_leaf(out, "ReqdExctnDt", pay.execution_year, pay.execution_month, pay.execution_day, 3, opts);
    if f.kind != F_NONE { return f; }
    f = party(out, "Dbtr", pay.debtor_name, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    f = account(out, "DbtrAcct", pay.debtor_iban, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    f = agent(out, "DbtrAgt", pay.debtor_bic, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    if pay.charge_bearer.len > 0 {
        if !charge_bearer_ok(pay.charge_bearer) { return fault(F_SYNTAX, 0, 0, "ChrgBr", "the charge bearer is not DEBT, CRED, SHAR or SLEV"); }
        f = text_leaf(out, "ChrgBr", pay.charge_bearer, 4, true, 3, opts, lim);
        if f.kind != F_NONE { return f; }
    }
    var i: i64 = start;
    while i < start + count {
        let tf = write_item(out, items[i], opts, lim);
        if tf.kind != F_NONE { return tf; }
        i += 1;
    }
    close(out, "PmtInf", 2, opts);
    return no_fault();
}

// write_item writes one credit transfer item.
fn write_item(out: u8[>..]&, t: CreditTransfer, opts: PainWriteOptions, lim: Limits&) -> Fault {
    var f = no_fault();
    open(out, "CdtTrfTxInf", 3, opts);
    open(out, "PmtId", 4, opts);
    if t.instruction_id.len > 0 {
        f = text_leaf(out, "InstrId", t.instruction_id, 35, true, 5, opts, lim);
        if f.kind != F_NONE { return f; }
    }
    f = text_leaf(out, "EndToEndId", t.end_to_end_id, 35, true, 5, opts, lim);
    if f.kind != F_NONE { return f; }
    close(out, "PmtId", 4, opts);
    open(out, "Amt", 4, opts);
    f = instd_amt(out, t.amount.minor, t.amount.code, 5, opts);
    if f.kind != F_NONE { return f; }
    close(out, "Amt", 4, opts);
    if t.creditor_bic.len > 0 {
        f = agent(out, "CdtrAgt", t.creditor_bic, 4, opts, lim);
        if f.kind != F_NONE { return f; }
    }
    f = party(out, "Cdtr", t.creditor_name, 4, opts, lim);
    if f.kind != F_NONE { return f; }
    f = account(out, "CdtrAcct", t.creditor_iban, 4, opts, lim);
    if f.kind != F_NONE { return f; }
    if t.purpose.len > 0 {
        open(out, "Purp", 4, opts);
        f = text_leaf(out, "Cd", t.purpose, 4, true, 5, opts, lim);
        if f.kind != F_NONE { return f; }
        close(out, "Purp", 4, opts);
    }
    if t.remittance.len > 0 || t.structured_ref.len > 0 {
        open(out, "RmtInf", 4, opts);
        if t.remittance.len > 0 {
            f = text_leaf(out, "Ustrd", t.remittance, 140, true, 5, opts, lim);
            if f.kind != F_NONE { return f; }
        }
        if t.structured_ref.len > 0 {
            open(out, "Strd", 5, opts);
            open(out, "CdtrRefInf", 6, opts);
            f = text_leaf(out, "Ref", t.structured_ref, 35, true, 7, opts, lim);
            if f.kind != F_NONE { return f; }
            close(out, "CdtrRefInf", 6, opts);
            close(out, "Strd", 5, opts);
        }
        close(out, "RmtInf", 4, opts);
    }
    close(out, "CdtTrfTxInf", 3, opts);
    return no_fault();
}

// put_dt writes the creation time of the header.
fn put_dt(out: u8[>..]&, h: GrpHeader) {
    put_day(out, h.creation_year, h.creation_month, h.creation_day);
    if h.has_creation {
        put(out, "T");
        put_two(out, h.creation_minutes / 60);
        put(out, ":");
        put_two(out, h.creation_minutes % 60);
        put(out, ":00");
        if h.creation_offset != 0 {
            if h.creation_offset > 0 { put(out, "+"); } else { put(out, "-"); }
            let a = if h.creation_offset > 0 { h.creation_offset } else { -h.creation_offset };
            put_two(out, a / 60);
            put(out, ":");
            put_two(out, a % 60);
        }
    }
}

// put_day writes a date as YYYY-MM-DD.
fn put_day(out: u8[>..]&, year: i32, month: i32, day: i32) {
    put_four(out, year as i64);
    out.push('-');
    put_two(out, month as i64);
    out.push('-');
    put_two(out, day as i64);
}

// put_count writes a number in decimal.
fn put_count(out: u8[>..]&, v: i64) {
    if v == 0 { out.push('0'); return; }
    var digits: u8[>..] = [];
    var x = v;
    while x > 0 { digits.push(('0' + (x % 10)) as u8); x = x / 10; }
    var k = digits.len;
    while k > 0 { k -= 1; out.push(digits[k]); }
}

fn put_two(out: u8[>..]&, v: i64) {
    out.push(('0' + (v / 10 % 10)) as u8);
    out.push(('0' + (v % 10)) as u8);
}

fn put_four(out: u8[>..]&, v: i64) {
    put_two(out, v / 100);
    put_two(out, v % 100);
}
