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

// PainOptions holds the switches of the reader.
struct PainOptions {
    skip_control_sum_check: bool,
    check_iban: bool,
    epc_charset: bool,
}

// child gives the first child element with the local name.
fn child(doc: xml::Doc&, id: i32, local: const u8[:]) -> i32 {
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
        if v > 922337203685477580 { return 0, false; }
        v = v * 10 + (c - '0') as i64;
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
        if v > 922337203685477580 {
            return z, fault(F_OVERFLOW, 0, 0, tag, "the amount does not fit in 64 bits");
        }
        v = v * 10 + (digits[i] - '0') as i64;
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
    if doc.root < 0 { return fault(F_SYNTAX, 0, 0, "", "the document has no root element"); }
    if doc.nodes[doc.root].local != "Document" {
        return fault(F_SYNTAX, 0, 0, doc.nodes[doc.root].local, "the root element is not a pain.001 document");
    }
    if !depth_ok(doc, lim.max_nesting) {
        return fault(F_LIMIT, 0, 0, "", "the elements nest deeper than max_nesting");
    }
    let msg = child(doc, doc.root, "CstmrCdtTrfInitn");
    if msg < 0 { return fault(F_SYNTAX, 0, 0, "Document", "the document holds no credit transfer initiation"); }
    header = new_header();
    // The group header.
    let grp = child(doc, msg, "GrpHdr");
    if grp < 0 { return fault(F_SYNTAX, 0, 0, "CstmrCdtTrfInitn", "the message holds no group header"); }
    let mid = child(doc, grp, "MsgId");
    if mid < 0 { return fault(F_SYNTAX, 0, 0, "GrpHdr", "the group header holds no message id"); }
    header.message_id = text_of(doc, mid, buf);
    let mf = check_text(header.message_id, 35, "MsgId", opts.epc_charset, lim);
    if mf.kind != F_NONE { return mf; }
    let cdt = child(doc, grp, "CreDtTm");
    if cdt >= 0 {
        let cf = parse_datetime(text_of(doc, cdt, buf), header, buf);
        if cf.kind != F_NONE { return cf; }
    }
    let nb = child(doc, grp, "NbOfTxs");
    if nb >= 0 {
        let n, okn = digits_value(text_of(doc, nb, buf));
        if !okn { return fault(F_SYNTAX, 0, 0, "NbOfTxs", "the count of transactions is not a number"); }
        header.count = n;
    }
    let cs = child(doc, grp, "CtrlSum");
    let init = child(doc, grp, "InitgPty");
    if init >= 0 {
        let nm = child(doc, init, "Nm");
        if nm >= 0 { header.initiator = text_of(doc, nm, buf); }
        let inf = check_text(header.initiator, 140, "InitgPty", opts.epc_charset, lim);
        if inf.kind != F_NONE { return inf; }
    }
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
    if cs >= 0 {
        if items.len == 0 {
            return fault(F_TOTAL, 0, 0, "CtrlSum", "the control sum stands but the message holds no item");
        }
        let total, sf = sum_range(items, 0, items.len);
        if sf.kind != F_NONE { return sf; }
        let ccy = items[0].amount.code;
        let claimed, cf = check_claimed(text_of(doc, cs, buf), total, ccy, "CtrlSum", opts.skip_control_sum_check);
        if cf.kind != F_NONE { return cf; }
        header.has_control_sum = true;
        header.control_sum = claimed;
        header.control_currency = items[0].amount.code;
    }
    // The claimed count of transactions against the items.
    if header.count > 0 && header.count != items.len as i64 {
        return fault_sums(F_TOTAL, 0, "NbOfTxs", "the count of transactions differs from the items", items.len as i64, header.count);
    }
    return no_fault();
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
    }
    let bb = child(doc, id, "BtchBookg");
    if bb >= 0 {
        let v = text_of(doc, bb, buf);
        payments[cur].has_batch_booking = true;
        if v == "true" || v == "1" { payments[cur].batch_booking = true; }
        else if v != "false" && v != "0" {
            return fault(F_SYNTAX, 0, 0, "BtchBookg", "the batch booking flag is not a flag");
        }
    }
    let cb = child(doc, id, "ChrgBr");
    if cb >= 0 {
        payments[cur].charge_bearer = text_of(doc, cb, buf);
        let cbf = check_text(payments[cur].charge_bearer, 35, "ChrgBr", opts.epc_charset, lim);
        if cbf.kind != F_NONE { return cbf; }
    }
    let dbtr = child(doc, id, "Dbtr");
    if dbtr >= 0 {
        let nm = child(doc, dbtr, "Nm");
        if nm >= 0 { payments[cur].debtor_name = text_of(doc, nm, buf); }
        let dbf = check_text(payments[cur].debtor_name, 140, "Nm", opts.epc_charset, lim);
        if dbf.kind != F_NONE { return dbf; }
        if payments[cur].debtor_name.len == 0 {
            return fault(F_SYNTAX, 0, 0, "Dbtr", "the debtor name is empty");
        }
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
        let bf = check_text(payments[cur].debtor_bic, 11, "BIC", opts.epc_charset, lim);
        if bf.kind != F_NONE { return bf; }
    }
    let rex = child(doc, id, "ReqdExctnDt");
    if rex >= 0 {
        let y, m, d, rf = parse_date(text_of(doc, rex, buf), "ReqdExctnDt");
        if rf.kind != F_NONE { return rf; }
        payments[cur].execution_year = y;
        payments[cur].execution_month = m;
        payments[cur].execution_day = d;
        payments[cur].has_execution_date = true;
    }
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
        let sum, sf = sum_range(items, start, count);
        if sf.kind != F_NONE { return sf; }
        if count == 0 { return fault(F_TOTAL, 0, 0, "CtrlSum", "the control sum stands but the block holds no item"); }
        let ccy = items[start].amount.code;
        let _, cf = check_claimed(text_of(doc, cs, buf), sum, ccy, "CtrlSum", opts.skip_control_sum_check);
        if cf.kind != F_NONE { return cf; }
    }
    return no_fault();
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
            let ccy, has = xml::attr_lookup(doc, doc.nodes[inst], "Ccy");
            if !has || ccy.len != 3 {
                return fault(F_AMOUNT, 0, 0, "InstdAmt", "the amount names no currency");
            }
            var mbuf: u8[>..] = [];
            let text = text_of(doc, inst, mbuf);
            let minor, af = parse_amount(text, ccy, "InstdAmt");
            if af.kind != F_NONE { return af; }
            let m, ok = finance::money(minor, ccy);
            if !ok {
                return fault(F_AMOUNT, 0, 0, "InstdAmt", "the currency table holds not the currency");
            }
            items[cur].amount = m;
        }
    }
    let cdtr = child(doc, id, "Cdtr");
    if cdtr >= 0 {
        let nm = child(doc, cdtr, "Nm");
        if nm >= 0 { items[cur].creditor_name = text_of(doc, nm, buf); }
        let cf = check_text(items[cur].creditor_name, 140, "Nm", opts.epc_charset, lim);
        if cf.kind != F_NONE { return cf; }
        if items[cur].creditor_name.len == 0 {
            return fault(F_SYNTAX, 0, 0, "Cdtr", "the creditor name is empty");
        }
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
        let bf = check_text(items[cur].creditor_bic, 11, "BIC", opts.epc_charset, lim);
        if bf.kind != F_NONE { return bf; }
    }
    let purp = child(doc, id, "Purp");
    if purp >= 0 {
        let cd = child(doc, purp, "Cd");
        if cd >= 0 {
            items[cur].purpose = text_of(doc, cd, buf);
            let pf = check_text(items[cur].purpose, 4, "Purp", opts.epc_charset, lim);
            if pf.kind != F_NONE { return pf; }
        }
    }
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
                let rf = child(doc, refi, "Ref");
                if rf >= 0 {
                    items[cur].structured_ref = text_of(doc, rf, buf);
                    let rff = check_text(items[cur].structured_ref, 35, "Ref", opts.epc_charset, lim);
                    if rff.kind != F_NONE { return rff; }
                }
            }
        }
    }
    return no_fault();
}
