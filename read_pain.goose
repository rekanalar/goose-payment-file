// The reader of the pain.001 credit transfer.
//
// The reader takes any schema version from .001.03 to .001.10. It
// matches every element by its local name, so the prefix and the
// schema version of the namespace play no role. An element it does
// not know is ignored. The reader checks the control sum, the IBANs,
// the character set and the lengths, each with a switch that turns
// it off.
namespace payment_file;

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import fault;
import model;
import charset;
import control;
import model_party;
import read_party;
import enums;

// PainOptions holds the switches of the reader.
struct PainOptions {
    skip_control_sum_check: bool,
    check_iban: bool,
    epc_charset: bool,
}

// child gives the first child element with the local name.
fn child(doc: xml::Doc&, id: i32, local: const u8[:]) -> i32 {
    if id < 0 { return -1; }
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT && n.local == local { return c; }
        c = n.next_sibling;
    }
    return -1;
}

// text_of gives the text of an element, trimmed. The text points into
// the buffer of the caller.
fn text_of(doc: xml::Doc&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let start = buf.len;
    xml::elem_text(buf, doc, id);
    return trim(buf[start..]);
}

// digits_value reads a decimal text. It gives false when the text is
// not a number or holds no digit.
fn digits_value(text: const u8[:]) -> i64, bool {
    var v: i64 = 0;
    if text.len == 0 { return 0, false; }
    var i: i64 = 0;
    while i < text.len {
        let c = text[i];
        if c < '0' || c > '9' { return 0, false; }
        let d = (c - '0') as i64;
        if !digit_fits(v, d) { return 0, false; }
        v = v * 10 + d;
        i += 1;
    }
    return v, true;
}

// parse_amount reads the text of an amount: a decimal with no minus
// sign, as the schema demands. Decimal places beyond the exponent of
// the currency must be zeros. It gives minor units.
fn parse_amount(text: const u8[:], ccy: const u8[:], tag: const u8[:]) -> i64, Fault {
    let z = 0;
    let exp = finance::currency_exponent(ccy) as i64;
    if exp < 0 { return z, fault(F_AMOUNT, 0, 0, tag, "the currency is not in the currency table"); }
    var t = text;
    if t.len > 0 && t[0] == '-' {
        return z, fault(F_AMOUNT, 0, 0, tag, "the schema allows no negative amount");
    }
    if t.len > 0 && t[0] == '+' { t = t[1..]; }
    var digits: u8[>..] = [];
    var frac: i64 = 0;
    var point = false;
    var i: i64 = 0;
    while i < t.len {
        let c = t[i];
        if c >= '0' && c <= '9' {
            // A digit beyond the exponent must be a zero and is dropped.
            if point && frac >= exp {
                if c != '0' {
                    return z, fault(F_AMOUNT, 0, 0, tag, "the amount holds more decimal places than the currency has");
                }
            } else {
                digits.push(c);
                if point { frac += 1; }
            }
        } else if c == '.' && !point {
            point = true;
        } else {
            return z, fault(F_AMOUNT, 0, 0, tag, "the amount holds a byte that is no digit");
        }
        i += 1;
    }
    if digits.len == 0 { return z, fault(F_AMOUNT, 0, 0, tag, "the amount is empty"); }
    while frac < exp { digits.push('0'); frac += 1; }
    var v: i64 = 0;
    i = 0;
    while i < digits.len {
        let d = (digits[i] - '0') as i64;
        if !digit_fits(v, d) {
            return z, fault(F_OVERFLOW, 0, 0, tag, "the amount does not fit in 64 bits");
        }
        v = v * 10 + d;
        i += 1;
    }
    return v, no_fault();
}

// check_claimed reads a control sum text and compares its value with
// the total of the items. The text holds no currency, so the decimal
// places are free. The switch turns the comparison off.
fn check_claimed(claimed: const u8[:], total: i64, ccy: const u8[:], tag: const u8[:], skip: bool) -> i64, Fault {
    let v, f = parse_amount(claimed, ccy, tag);
    if f.kind != F_NONE { return 0, f; }
    if !skip && v != total {
        return v, fault_sums(F_TOTAL, 0, tag, "the control sum differs from the items", total, v);
    }
    return v, no_fault();
}

// amount_of reads an amount element: the text is the decimal value and
// the Ccy attribute is the currency. The tag names the element in a fault.
fn amount_of(doc: xml::Doc&, node: i32, tag: const u8[:]) -> finance::Money, Fault {
    let none = finance::Money { minor: 0, code: "" };
    let ccy, has = xml::attr_lookup(doc, doc.nodes[node], "Ccy");
    if !has || ccy.len != 3 { return none, fault(F_AMOUNT, 0, 0, tag, "the amount names no currency"); }
    var mbuf: u8[>..] = [];
    let minor, af = parse_amount(text_of(doc, node, mbuf), ccy, tag);
    if af.kind != F_NONE { return none, af; }
    let m, ok = finance::money(minor, ccy);
    if !ok { return none, fault(F_AMOUNT, 0, 0, tag, "the currency table holds not the currency"); }
    return m, no_fault();
}

// bic_of gives the BIC of an agent element. The element name is BIC
// up to .001.08 and BICFI from .001.09 on.
fn bic_of(doc: xml::Doc&, agent: i32, buf: u8[>..]&) -> const u8[:] {
    let fi = child(doc, agent, "FinInstnId");
    if fi < 0 { return ""; }
    var b = child(doc, fi, "BIC");
    if b < 0 { b = child(doc, fi, "BICFI"); }
    if b < 0 { return ""; }
    return text_of(doc, b, buf);
}

// depth_ok tells whether no element sits deeper than the limit.
fn depth_ok(doc: xml::Doc&, max: i64) -> bool {
    if doc.nodes.len <= max { return true; }
    var depth: i32[>..] = [];
    var i: i64 = 0;
    while i < doc.nodes.len {
        let n = doc.nodes[i];
        var d: i32 = 0;
        if n.parent >= 0 && n.parent < i { d = depth[n.parent]; }
        if n.kind == xml::KIND_ELEMENT { d += 1; }
        if d as i64 > max { return false; }
        depth.push(d);
        i += 1;
    }
    return true;
}

// parse_date reads YYYY-MM-DD. A text of another form is a fault.
fn parse_date(text: const u8[:], tag: const u8[:]) -> i32, i32, i32, Fault {
    if text.len < 10 || text[4] != '-' || text[7] != '-' {
        return 0, 0, 0, fault(F_DATE, 0, 0, tag, "the date is not YYYY-MM-DD");
    }
    let y, ok1 = digits_value(text[0..4]);
    let m, ok2 = digits_value(text[5..7]);
    let d, ok3 = digits_value(text[8..10]);
    if !ok1 || !ok2 || !ok3 || !finance::date_ok(y, m, d) {
        return 0, 0, 0, fault(F_DATE, 0, 0, tag, "the date is not a civil date");
    }
    return y as i32, m as i32, d as i32, no_fault();
}

// parse_datetime reads the creation time: a date, an optional time,
// and an optional offset.
fn parse_datetime(text: const u8[:], h: GrpHeader&, buf: u8[>..]&) -> Fault {
    let y, m, d, f = parse_date(text, "CreDtTm");
    if f.kind != F_NONE { return f; }
    h.creation_year = y;
    h.creation_month = m;
    h.creation_day = d;
    if text.len >= 19 && (text[10] == 'T' || text[10] == ' ') {
        let hh, ok1 = digits_value(text[11..13]);
        let mm, ok2 = digits_value(text[14..16]);
        if !ok1 || !ok2 || text[13] != ':' || hh > 24 || mm > 59 {
            return fault(F_DATE, 0, 0, "CreDtTm", "the time is not hh:mm");
        }
        h.creation_minutes = (hh * 60 + mm) as i32;
        var p: i64 = 16;
        while p < text.len && text[p] != '+' && text[p] != '-' { p += 1; }
        if p < text.len && text.len >= p + 6 && text[p + 3] == ':' {
            let oh, ok3 = digits_value(text[p + 1..p + 3]);
            let om, ok4 = digits_value(text[p + 4..p + 6]);
            if !ok3 || !ok4 { return fault(F_DATE, 0, 0, "CreDtTm", "the offset is not +hh:mm"); }
            var off = (oh * 60 + om) as i32;
            if text[p] == '-' { off = -off; }
            h.creation_offset = off;
        }
        h.has_creation = true;
    }
    return no_fault();
}

// check_ibans_of checks one IBAN. The flag turns the check off. An
// empty IBAN is a fault, because the schema makes it required.
fn check_ibans_of(iban: const u8[:], tag: const u8[:], opts: PainOptions&) -> Fault {
    if !opts.check_iban { return no_fault(); }
    if !payment_identifier::iban_is_valid(iban) {
        return fault(F_IBAN, 0, 0, tag, "the IBAN does not pass the check digits");
    }
    return no_fault();
}

// account_iban gives the IBAN node of an account element. The IBAN sits
// in Id, or directly in the account.
fn account_iban(doc: xml::Doc&, acct: i32) -> i32 {
    var holder = acct;
    let idn = child(doc, acct, "Id");
    if idn >= 0 { holder = idn; }
    return child(doc, holder, "IBAN");
}

// check_iban_text checks the length, the character set and the check
// digits of an IBAN text.
fn check_iban_text(iban: const u8[:], tag: const u8[:], opts: PainOptions&, lim: Limits&) -> Fault {
    let f = check_text(iban, 34, "IBAN", opts.epc_charset, lim);
    if f.kind != F_NONE { return f; }
    return check_ibans_of(iban, tag, opts);
}

// opt_text reads the text of an element that may be absent. An absent
// element gives an empty text. A present text passes the length and
// character checks under its own name.
fn opt_text(doc: xml::Doc&, node: i32, tag: const u8[:], max: i64, opts: PainOptions&,
            lim: Limits&, buf: u8[>..]&) -> const u8[:], Fault {
    if node < 0 { return "", no_fault(); }
    let text = text_of(doc, node, buf);
    let f = check_text(text, max, tag, opts.epc_charset, lim);
    if f.kind != F_NONE { return "", f; }
    return text, no_fault();
}

// parse_flag reads a boolean text: true, 1, false or 0.
fn parse_flag(v: const u8[:], tag: const u8[:]) -> bool, Fault {
    if v == "true" || v == "1" { return true, no_fault(); }
    if v == "false" || v == "0" { return false, no_fault(); }
    return false, fault(F_SYNTAX, 0, 0, tag, "the value is not a flag");
}

// check_bic checks the length, the character set and the shape of a
// BIC text. An absent BIC is fine.
fn check_bic(bic: const u8[:], opts: PainOptions&, lim: Limits&) -> Fault {
    let f = check_text(bic, 11, "BIC", opts.epc_charset, lim);
    if f.kind != F_NONE { return f; }
    if bic.len > 0 && !bic_ok(bic) {
        return fault(F_SYNTAX, 0, 0, "BIC", "the BIC is not 8 or 11 capital letters and digits");
    }
    return no_fault();
}

// check_bearer checks a charge bearer text against the code list.
fn check_bearer(text: const u8[:], opts: PainOptions&, lim: Limits&) -> Fault {
    let f = check_text(text, 4, "ChrgBr", opts.epc_charset, lim);
    if f.kind != F_NONE { return f; }
    if !charge_bearer_ok(text) { return fault(F_SYNTAX, 0, 0, "ChrgBr", "the charge bearer is not DEBT, CRED, SHAR or SLEV"); }
    return no_fault();
}

// check_doc checks the root element and the nesting of a parsed
// document. It gives the node of the container element under the root.
fn check_doc(doc: xml::Doc&, lim: Limits&, container: const u8[:]) -> i32, Fault {
    if doc.root < 0 { return -1, fault(F_SYNTAX, 0, 0, "", "the document has no root element"); }
    if doc.nodes[doc.root].local != "Document" {
        return -1, fault(F_SYNTAX, 0, 0, "Document", "the root element is not a Document");
    }
    if !depth_ok(doc, lim.max_nesting) {
        return -1, fault(F_LIMIT, 0, 0, "", "the elements nest deeper than max_nesting");
    }
    let msg = child(doc, doc.root, container);
    if msg < 0 { return -1, fault(F_SYNTAX, 0, 0, "Document", "the document holds no initiation element"); }
    return msg, no_fault();
}

// parse_group reads the group header: the message id, the creation
// time, the count and the initiator. It gives the node of the control
// sum, or -1 when the header holds none.
fn parse_group(doc: xml::Doc&, msg: i32, opts: PainOptions&, lim: Limits&,
               header: GrpHeader&, buf: u8[>..]&) -> i32, Fault {
    let grp = child(doc, msg, "GrpHdr");
    if grp < 0 { return -1, fault(F_SYNTAX, 0, 0, "", "the message holds no group header"); }
    let mid = child(doc, grp, "MsgId");
    if mid < 0 { return -1, fault(F_SYNTAX, 0, 0, "GrpHdr", "the group header holds no message id"); }
    header.message_id = text_of(doc, mid, buf);
    let mf = check_text(header.message_id, 35, "MsgId", opts.epc_charset, lim);
    if mf.kind != F_NONE { return -1, mf; }
    let cdt = child(doc, grp, "CreDtTm");
    if cdt >= 0 {
        let cf = parse_datetime(text_of(doc, cdt, buf), header, buf);
        if cf.kind != F_NONE { return -1, cf; }
    }
    let nb = child(doc, grp, "NbOfTxs");
    if nb >= 0 {
        let n, okn = digits_value(text_of(doc, nb, buf));
        if !okn { return -1, fault(F_SYNTAX, 0, 0, "NbOfTxs", "the count of transactions is not a number"); }
        header.count = n;
        header.has_count = true;
    }
    let init = child(doc, grp, "InitgPty");
    if init >= 0 {
        let nm = child(doc, init, "Nm");
        if nm >= 0 { header.initiator = text_of(doc, nm, buf); }
        let inf = check_text(header.initiator, 140, "InitgPty", opts.epc_charset, lim);
        if inf.kind != F_NONE { return -1, inf; }
    }
    return child(doc, grp, "CtrlSum"), no_fault();
}

// finish_group checks the control sum and the count of the group
// header against the items. The caller computes the total.
fn finish_group(doc: xml::Doc&, cs: i32, count: i64, total: i64, ccy: const u8[:],
                header: GrpHeader&, opts: PainOptions&, buf: u8[>..]&) -> Fault {
    if cs >= 0 {
        if count == 0 {
            return fault(F_TOTAL, 0, 0, "CtrlSum", "the control sum stands but the message holds no item");
        }
        let claimed, cf = check_claimed(text_of(doc, cs, buf), total, ccy, "CtrlSum", opts.skip_control_sum_check);
        if cf.kind != F_NONE { return cf; }
        header.has_control_sum = true;
        header.control_sum = claimed;
    }
    if header.count > 0 && header.count != count {
        return fault_sums(F_TOTAL, 0, "NbOfTxs", "the count of transactions differs from the items", count, header.count);
    }
    return no_fault();
}

// check_block_totals checks the count and the control sum of one
// payment block against its items. The caller computes the sum.
fn check_block_totals(doc: xml::Doc&, id: i32, count: i64, sum: i64, ccy: const u8[:],
                      opts: PainOptions&, buf: u8[>..]&) -> Fault {
    let nb = child(doc, id, "NbOfTxs");
    if nb >= 0 {
        let n, okn = digits_value(text_of(doc, nb, buf));
        if !okn { return fault(F_SYNTAX, 0, 0, "NbOfTxs", "the count of transactions is not a number"); }
        if n != count {
            return fault_sums(F_TOTAL, 0, "NbOfTxs", "the count of the block differs from its items", count, n);
        }
    }
    let cs = child(doc, id, "CtrlSum");
    if cs >= 0 {
        if count == 0 { return fault(F_TOTAL, 0, 0, "CtrlSum", "the control sum stands but the block holds no item"); }
        let _, cf = check_claimed(text_of(doc, cs, buf), sum, ccy, "CtrlSum", opts.skip_control_sum_check);
        if cf.kind != F_NONE { return cf; }
    }
    return no_fault();
}

// parse_pain001 reads the credit transfer initiation. The payments
// and the items go into the flat arrays of the caller. The texts
// point into the buffer of the caller, so the buffer must outlive
// them. The input may go away after the call.
fn parse_pain001(input: const u8[:], lim: Limits&, opts: PainOptions&,
                 header: GrpHeader&, payments: PaymentInfo[>..]&, items: CreditTransfer[>..]&,
                 buf: u8[>..]&) -> Fault {
    if input.len > lim.max_input {
        return fault(F_LIMIT, 0, 0, "", "the document is longer than max_input");
    }
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(input, nodes, attrs);
    if !ok { return fault(F_SYNTAX, 0, 0, "", "the document is not well formed XML"); }
    let msg, df = check_doc(doc, lim, "CstmrCdtTrfInitn");
    if df.kind != F_NONE { return df; }
    header = new_header();
    let cs, gf = parse_group(doc, msg, opts, lim, header, buf);
    if gf.kind != F_NONE { return gf; }
    // The payment blocks.
    var c = doc.nodes[msg].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT && n.local == "PmtInf" {
            if payments.len >= lim.max_payments {
                return fault(F_LIMIT, 0, 0, "PmtInf", "more payment blocks than the limits allow");
            }
            payments.push(new_payment());
            let cur = payments.len - 1;
            payments[cur].item_start = items.len as i32;
            let pf = parse_pmt_inf(doc, c, opts, lim, payments, cur, items, buf);
            if pf.kind != F_NONE { return pf; }
            payments[cur].item_count = (items.len - payments[cur].item_start as i64) as i32;
        }
        c = n.next_sibling;
    }
    if payments.len == 0 {
        return fault(F_SYNTAX, 0, 0, "CstmrCdtTrfInitn", "the message holds no payment block");
    }
    // The control sum of the group header against the items.
    var total: i64 = 0;
    if cs >= 0 && items.len > 0 {
        let t, sf = sum_range(items, 0, items.len);
        if sf.kind != F_NONE { return sf; }
        total = t;
    }
    var fin = no_fault();
    if items.len > 0 { fin = finish_group(doc, cs, items.len, total, items[0].amount.code, header, opts, buf); }
    else { fin = finish_group(doc, cs, items.len, total, "", header, opts, buf); }
    if fin.kind != F_NONE { return fin; }
    if header.has_control_sum { header.control_currency = items[0].amount.code; }
    return no_fault();
}

// has_child_element tells whether an element holds a child element.
// The parser keeps the text nodes, so a text alone is no child
// element.
fn has_child_element(doc: xml::Doc&, id: i32) -> bool {
    if id < 0 { return false; }
    var k = doc.nodes[id].first_child;
    while k >= 0 {
        if doc.nodes[k].kind == xml::KIND_ELEMENT { return true; }
        k = doc.nodes[k].next_sibling;
    }
    return false;
}

// read_code_or_prtry reads a choice that holds a code or a proprietary
// text. Both together are a fault. A second copy of either is a fault
// too. An empty choice gives two empty texts and no fault. The tag
// names the element in a fault.
fn read_code_or_prtry(doc: xml::Doc&, id: i32, tag: const u8[:], opts: PainOptions&,
                      lim: Limits&, buf: u8[>..]&) -> const u8[:], const u8[:], Fault {
    var cds: i64 = 0;
    var prtries: i64 = 0;
    var k = doc.nodes[id].first_child;
    while k >= 0 {
        let m = doc.nodes[k];
        if m.kind == xml::KIND_ELEMENT {
            if m.local == "Cd" { cds += 1; }
            else if m.local == "Prtry" { prtries += 1; }
        }
        k = m.next_sibling;
    }
    if cds > 1 { return "", "", fault(F_SYNTAX, 0, 0, tag, "the element holds two codes"); }
    if prtries > 1 { return "", "", fault(F_SYNTAX, 0, 0, tag, "the element holds two proprietary texts"); }
    let cd = child(doc, id, "Cd");
    let prtry = child(doc, id, "Prtry");
    if cd >= 0 && prtry >= 0 {
        return "", "", fault(F_SYNTAX, 0, 0, tag, "the element holds a code and a proprietary text");
    }
    if cd >= 0 {
        let t, f = opt_text(doc, cd, "Cd", MAX_4, opts, lim, buf);
        if f.kind != F_NONE { return "", "", f; }
        return t, "", no_fault();
    }
    if prtry >= 0 {
        let t, f = opt_text(doc, prtry, "Prtry", MAX_35, opts, lim, buf);
        if f.kind != F_NONE { return "", "", f; }
        return "", t, no_fault();
    }
    return "", "", no_fault();
}

// read_date_element reads a date that the schema holds as a text or as
// a Dt or a DtTm child. The later forms of the pain.001 hold the
// execution date as a child element. A text and a child together, and
// a second child, are faults, so no value is lost in silence.
fn read_date_element(doc: xml::Doc&, id: i32, tag: const u8[:], buf: u8[>..]&) -> i32, i32, i32, Fault {
    var dts: i64 = 0;
    var dtms: i64 = 0;
    var text_len: i64 = 0;
    var k = doc.nodes[id].first_child;
    while k >= 0 {
        let m = doc.nodes[k];
        if m.kind == xml::KIND_ELEMENT {
            if m.local == "Dt" { dts += 1; }
            else if m.local == "DtTm" { dtms += 1; }
        } else if m.kind == xml::KIND_TEXT || m.kind == xml::KIND_CDATA {
            var j: i64 = 0;
            while j < m.content.len {
                let b = m.content[j];
                if b != ' ' && b != '\n' && b != '\r' && b != '\t' { text_len += 1; }
                j += 1;
            }
        }
        k = m.next_sibling;
    }
    if dts > 1 || dtms > 1 {
        return 0, 0, 0, fault(F_SYNTAX, 0, 0, tag, "the date holds two child elements");
    }
    if dts + dtms > 0 && text_len > 0 {
        return 0, 0, 0, fault(F_SYNTAX, 0, 0, tag, "the date holds a text and a child element");
    }
    let dt = child(doc, id, "Dt");
    if dt >= 0 { return parse_date(text_of(doc, dt, buf), tag); }
    let dtm = child(doc, id, "DtTm");
    if dtm >= 0 { return parse_date(text_of(doc, dtm, buf), tag); }
    return parse_date(text_of(doc, id, buf), tag);
}

// read_service_level reads the service level of a payment block. The
// block holds the service level in its payment type element. A block
// with no payment type element holds no service level. A second
// payment type element, a second service level and a code with a child
// element are faults, so no value is lost in silence. A service level
// with a proprietary text and no code is a fault, because the model
// names the element and holds the code only.
fn read_service_level(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                      buf: u8[>..]&) -> const u8[:], Fault {
    var tps: i64 = 0;
    var k = doc.nodes[id].first_child;
    while k >= 0 {
        let m = doc.nodes[k];
        if m.kind == xml::KIND_ELEMENT && m.local == "PmtTpInf" { tps += 1; }
        k = m.next_sibling;
    }
    if tps > 1 {
        return "", fault(F_SYNTAX, 0, 0, "PmtTpInf", "the block holds two payment type elements");
    }
    let tp = child(doc, id, "PmtTpInf");
    if tp < 0 { return "", no_fault(); }
    var sls: i64 = 0;
    k = doc.nodes[tp].first_child;
    while k >= 0 {
        let m = doc.nodes[k];
        if m.kind == xml::KIND_ELEMENT && m.local == "SvcLvl" { sls += 1; }
        k = m.next_sibling;
    }
    if sls > 1 {
        return "", fault(F_SYNTAX, 0, 0, "SvcLvl", "the payment type holds two service levels");
    }
    let sl = child(doc, tp, "SvcLvl");
    if sl < 0 { return "", no_fault(); }
    let cd = child(doc, sl, "Cd");
    if cd < 0 {
        return "", fault(F_SYNTAX, 0, 0, "SvcLvl", "the service level holds no code");
    }
    // A code that holds a child element reads as no text. That is a
    // fault, because an empty code means the default service level.
    if has_child_element(doc, cd) {
        return "", fault(F_SYNTAX, 0, 0, "Cd", "the service level holds a child element");
    }
    let t, f = opt_text(doc, cd, "Cd", MAX_4, opts, lim, buf);
    if f.kind != F_NONE { return "", f; }
    return t, no_fault();
}

// parse_pmt_inf reads one payment block.
fn parse_pmt_inf(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                 payments: PaymentInfo[>..]&, cur: i64, items: CreditTransfer[>..]&,
                 buf: u8[>..]&) -> Fault {
    let pid = child(doc, id, "PmtInfId");
    if pid >= 0 { payments[cur].id = text_of(doc, pid, buf); }
    let idf = check_text(payments[cur].id, 35, "PmtInfId", opts.epc_charset, lim);
    if idf.kind != F_NONE { return idf; }
    let pm = child(doc, id, "PmtMtd");
    if pm >= 0 {
        payments[cur].method = text_of(doc, pm, buf);
        let mf = check_text(payments[cur].method, 3, "PmtMtd", opts.epc_charset, lim);
        if mf.kind != F_NONE { return mf; }
        if !pay_method_ok(payments[cur].method) {
            return fault(F_SYNTAX, 0, 0, "PmtMtd", "the payment method is not TRF, CHK or TRA");
        }
    }
    let bb = child(doc, id, "BtchBookg");
    if bb >= 0 {
        let v, ff = parse_flag(text_of(doc, bb, buf), "BtchBookg");
        if ff.kind != F_NONE { return ff; }
        payments[cur].has_batch_booking = true;
        payments[cur].batch_booking = v;
    }
    let cb = child(doc, id, "ChrgBr");
    if cb >= 0 {
        payments[cur].charge_bearer = text_of(doc, cb, buf);
        let cbf = check_bearer(payments[cur].charge_bearer, opts, lim);
        if cbf.kind != F_NONE { return cbf; }
    }
    let dbtr = child(doc, id, "Dbtr");
    if dbtr >= 0 {
        let nm, nf = read_party_full(doc, dbtr, MAX_140, true, opts, lim, buf, payments[cur].debtor_detail, "Dbtr");
        if nf.kind != F_NONE { return nf; }
        payments[cur].debtor_name = nm;
    }
    let dacct = child(doc, id, "DbtrAcct");
    if dacct >= 0 {
        var holder = dacct;
        let dacct_id = child(doc, dacct, "Id");
        if dacct_id >= 0 { holder = dacct_id; }
        let ib = child(doc, holder, "IBAN");
        if ib >= 0 {
            payments[cur].debtor_iban = text_of(doc, ib, buf);
            let ibf = check_text(payments[cur].debtor_iban, 34, "IBAN", opts.epc_charset, lim);
            if ibf.kind != F_NONE { return ibf; }
            let vf = check_ibans_of(payments[cur].debtor_iban, "DbtrAcct", opts);
            if vf.kind != F_NONE { return vf; }
        }
    }
    let dbic = child(doc, id, "DbtrAgt");
    if dbic >= 0 {
        payments[cur].debtor_bic = bic_of(doc, dbic, buf);
        let bf = check_bic(payments[cur].debtor_bic, opts, lim);
        if bf.kind != F_NONE { return bf; }
    }
    let udbtr = child(doc, id, "UltmtDbtr");
    if udbtr >= 0 {
        let nm, nf = read_party_full(doc, udbtr, MAX_140, false, opts, lim, buf, payments[cur].ultimate_debtor_detail, "UltmtDbtr");
        if nf.kind != F_NONE { return nf; }
        payments[cur].ultimate_debtor_name = nm;
    }
    let rex = child(doc, id, "ReqdExctnDt");
    if rex >= 0 {
        let y, m, d, rf = read_date_element(doc, rex, "ReqdExctnDt", buf);
        if rf.kind != F_NONE { return rf; }
        payments[cur].execution_year = y;
        payments[cur].execution_month = m;
        payments[cur].execution_day = d;
        payments[cur].has_execution_date = true;
    }
    let sl, slf = read_service_level(doc, id, opts, lim, buf);
    if slf.kind != F_NONE { return slf; }
    payments[cur].service_level = sl;
    // The items.
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT && n.local == "CdtTrfTxInf" {
            if items.len >= lim.max_items {
                return fault(F_LIMIT, 0, 0, "CdtTrfTxInf", "more items than the limits allow");
            }
            items.push(new_transfer());
            let tf = parse_item(doc, c, opts, lim, items, items.len - 1, buf);
            if tf.kind != F_NONE { return tf; }
        }
        c = n.next_sibling;
    }
    // The count and the control sum of the block against its items.
    let start = payments[cur].item_start as i64;
    let count = items.len - start;
    var sum: i64 = 0;
    if count > 0 && child(doc, id, "CtrlSum") >= 0 {
        let t, sf = sum_range(items, start, count);
        if sf.kind != F_NONE { return sf; }
        sum = t;
    }
    if count > 0 { return check_block_totals(doc, id, count, sum, items[start].amount.code, opts, buf); }
    return check_block_totals(doc, id, count, sum, "", opts, buf);
}

// parse_item reads one credit transfer item.
fn parse_item(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
              items: CreditTransfer[>..]&, cur: i64, buf: u8[>..]&) -> Fault {
    let pid = child(doc, id, "PmtId");
    if pid >= 0 {
        let iid = child(doc, pid, "InstrId");
        if iid >= 0 {
            items[cur].instruction_id = text_of(doc, iid, buf);
            let iif = check_text(items[cur].instruction_id, 35, "InstrId", opts.epc_charset, lim);
            if iif.kind != F_NONE { return iif; }
        }
        let eid = child(doc, pid, "EndToEndId");
        if eid >= 0 {
            items[cur].end_to_end_id = text_of(doc, eid, buf);
            let eef = check_text(items[cur].end_to_end_id, 35, "EndToEndId", opts.epc_charset, lim);
            if eef.kind != F_NONE { return eef; }
        }
    }
    let amt = child(doc, id, "Amt");
    if amt >= 0 {
        let inst = child(doc, amt, "InstdAmt");
        if inst >= 0 {
            let m, af = amount_of(doc, inst, "InstdAmt");
            if af.kind != F_NONE { return af; }
            items[cur].amount = m;
        } else {
            return fault(F_SYNTAX, 0, 0, "InstdAmt", "the item holds no instructed amount");
        }
    } else {
        return fault(F_SYNTAX, 0, 0, "Amt", "the item holds no amount");
    }
    let cdtr = child(doc, id, "Cdtr");
    if cdtr >= 0 {
        let nm, nf = read_party_full(doc, cdtr, MAX_140, true, opts, lim, buf, items[cur].creditor_detail, "Cdtr");
        if nf.kind != F_NONE { return nf; }
        items[cur].creditor_name = nm;
    }
    let cacct = child(doc, id, "CdtrAcct");
    if cacct >= 0 {
        var cholder = cacct;
        let cacct_id = child(doc, cacct, "Id");
        if cacct_id >= 0 { cholder = cacct_id; }
        let ib = child(doc, cholder, "IBAN");
        if ib >= 0 {
            items[cur].creditor_iban = text_of(doc, ib, buf);
            let ibf = check_text(items[cur].creditor_iban, 34, "IBAN", opts.epc_charset, lim);
            if ibf.kind != F_NONE { return ibf; }
            let vf = check_ibans_of(items[cur].creditor_iban, "CdtrAcct", opts);
            if vf.kind != F_NONE { return vf; }
        }
    }
    let cbic = child(doc, id, "CdtrAgt");
    if cbic >= 0 {
        items[cur].creditor_bic = bic_of(doc, cbic, buf);
        let bf = check_bic(items[cur].creditor_bic, opts, lim);
        if bf.kind != F_NONE { return bf; }
    }
    let udbtr = child(doc, id, "UltmtDbtr");
    if udbtr >= 0 {
        let nm, nf = read_party_full(doc, udbtr, MAX_140, false, opts, lim, buf, items[cur].ultimate_debtor_detail, "UltmtDbtr");
        if nf.kind != F_NONE { return nf; }
        items[cur].ultimate_debtor_name = nm;
    }
    let ucdtr = child(doc, id, "UltmtCdtr");
    if ucdtr >= 0 {
        let nm, nf = read_party_full(doc, ucdtr, MAX_140, false, opts, lim, buf, items[cur].ultimate_creditor_detail, "UltmtCdtr");
        if nf.kind != F_NONE { return nf; }
        items[cur].ultimate_creditor_name = nm;
    }
    let purp_code, pf = read_purpose(doc, id, opts, lim, buf);
    if pf.kind != F_NONE { return pf; }
    items[cur].purpose = purp_code;
    let rmt = child(doc, id, "RmtInf");
    if rmt >= 0 {
        let u = child(doc, rmt, "Ustrd");
        if u >= 0 {
            items[cur].remittance = text_of(doc, u, buf);
            let uf = check_text(items[cur].remittance, 140, "Ustrd", opts.epc_charset, lim);
            if uf.kind != F_NONE { return uf; }
        }
        let strd = child(doc, rmt, "Strd");
        if strd >= 0 {
            let refi = child(doc, strd, "CdtrRefInf");
            if refi >= 0 {
                let r, cf = read_cdtr_ref(doc, refi, opts, lim, buf);
                if cf.kind != F_NONE { return cf; }
                items[cur].structured_type = r.code;
                items[cur].structured_proprietary_type = r.proprietary_type;
                items[cur].structured_issuer = r.issuer;
                items[cur].structured_ref = r.ref;
            }
        }
    }
    return no_fault();
}
