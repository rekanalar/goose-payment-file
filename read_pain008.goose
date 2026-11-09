// The reader of the pain.008 direct debit.
//
// The reader takes the versions .001.02 to .001.08. It matches every
// element by its local name. An element it does not know is ignored.
// The checks and their switches are the ones of the credit transfer.
namespace payment_file;

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import fault;
import model;
import model_debit;
import charset;
import control;
import enums;
import read_pain;

// scheme_of gives the creditor scheme id under an element: the first
// identification of Id/PrvtId/Othr or Id/OrgId/Othr.
fn scheme_of(doc: xml::Doc&, id: i32, buf: u8[>..]&) -> const u8[:] {
    let ident = child(doc, id, "Id");
    if ident < 0 { return ""; }
    var kind = child(doc, ident, "PrvtId");
    if kind < 0 { kind = child(doc, ident, "OrgId"); }
    if kind < 0 { return ""; }
    let other = child(doc, kind, "Othr");
    if other < 0 { return ""; }
    let v = child(doc, other, "Id");
    if v < 0 { return ""; }
    return text_of(doc, v, buf);
}

// parse_pain008 reads the direct debit initiation. The blocks and the
// items go into the flat arrays of the caller. The texts point into the
// buffer of the caller, so the buffer must outlive them.
fn parse_pain008(input: const u8[:], lim: Limits&, opts: PainOptions&,
                 header: GrpHeader&, blocks: DebitInfo[>..]&, items: DirectDebit[>..]&,
                 buf: u8[>..]&) -> Fault {
    if input.len > lim.max_input {
        return fault(F_LIMIT, 0, 0, "", "the document is longer than max_input");
    }
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(input, nodes, attrs);
    if !ok { return fault(F_SYNTAX, 0, 0, "", "the document is not well formed XML"); }
    let msg, df = check_doc(doc, lim, "CstmrDrctDbtInitn");
    if df.kind != F_NONE { return df; }
    header = new_header();
    let cs, gf = parse_group(doc, msg, opts, lim, header, buf);
    if gf.kind != F_NONE { return gf; }
    var c = doc.nodes[msg].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT && n.local == "PmtInf" {
            if blocks.len >= lim.max_payments {
                return fault(F_LIMIT, 0, 0, "PmtInf", "more payment blocks than the limits allow");
            }
            blocks.push(new_debit_info());
            let cur = blocks.len - 1;
            blocks[cur].item_start = items.len as i32;
            let pf = parse_debit_block(doc, c, opts, lim, blocks, cur, items, buf);
            if pf.kind != F_NONE { return pf; }
            blocks[cur].item_count = (items.len - blocks[cur].item_start as i64) as i32;
        }
        c = n.next_sibling;
    }
    if blocks.len == 0 {
        return fault(F_SYNTAX, 0, 0, "CstmrDrctDbtInitn", "the message holds no payment block");
    }
    var total: i64 = 0;
    if cs >= 0 && items.len > 0 {
        let t, sf = sum_debits(items, 0, items.len);
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

// parse_debit_block reads one payment block.
fn parse_debit_block(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                     blocks: DebitInfo[>..]&, cur: i64, items: DirectDebit[>..]&,
                     buf: u8[>..]&) -> Fault {
    let pid = child(doc, id, "PmtInfId");
    if pid >= 0 { blocks[cur].id = text_of(doc, pid, buf); }
    let idf = check_text(blocks[cur].id, 35, "PmtInfId", opts.epc_charset, lim);
    if idf.kind != F_NONE { return idf; }
    let pm = child(doc, id, "PmtMtd");
    if pm >= 0 && text_of(doc, pm, buf) != "DD" {
        return fault(F_SYNTAX, 0, 0, "PmtMtd", "the payment method of a direct debit is not DD");
    }
    let bb = child(doc, id, "BtchBookg");
    if bb >= 0 {
        let v, ff = parse_flag(text_of(doc, bb, buf), "BtchBookg");
        if ff.kind != F_NONE { return ff; }
        blocks[cur].has_batch_booking = true;
        blocks[cur].batch_booking = v;
    }
    // The payment type: the local instrument and the sequence type.
    let tp = child(doc, id, "PmtTpInf");
    if tp >= 0 {
        let li = child(doc, tp, "LclInstrm");
        if li >= 0 {
            let cd = child(doc, li, "Cd");
            if cd >= 0 { blocks[cur].instrument = text_of(doc, cd, buf); }
            if blocks[cur].instrument.len > 0 && !instrument_ok(blocks[cur].instrument) {
                return fault(F_SYNTAX, 0, 0, "LclInstrm", "the local instrument is not CORE, COR1 or B2B");
            }
        }
        let sq = child(doc, tp, "SeqTp");
        if sq >= 0 {
            blocks[cur].seq_type = text_of(doc, sq, buf);
            if !seq_type_ok(blocks[cur].seq_type) {
                return fault(F_SYNTAX, 0, 0, "SeqTp", "the sequence type is not FRST, RCUR, OOFF or FNAL");
            }
        }
    }
    let rc = child(doc, id, "ReqdColltnDt");
    if rc >= 0 {
        let y, m, d, rf = parse_date(text_of(doc, rc, buf), "ReqdColltnDt");
        if rf.kind != F_NONE { return rf; }
        blocks[cur].collection_year = y;
        blocks[cur].collection_month = m;
        blocks[cur].collection_day = d;
        blocks[cur].has_collection_date = true;
    }
    let cdtr = child(doc, id, "Cdtr");
    if cdtr >= 0 {
        let nm = child(doc, cdtr, "Nm");
        if nm >= 0 { blocks[cur].creditor_name = text_of(doc, nm, buf); }
        let nf = check_text(blocks[cur].creditor_name, 140, "Nm", opts.epc_charset, lim);
        if nf.kind != F_NONE { return nf; }
    }
    let cacct = child(doc, id, "CdtrAcct");
    if cacct >= 0 {
        let ib = account_iban(doc, cacct);
        if ib >= 0 {
            blocks[cur].creditor_iban = text_of(doc, ib, buf);
            let ibf = check_iban_text(blocks[cur].creditor_iban, "CdtrAcct", opts, lim);
            if ibf.kind != F_NONE { return ibf; }
        }
    }
    let cagt = child(doc, id, "CdtrAgt");
    if cagt >= 0 {
        blocks[cur].creditor_bic = bic_of(doc, cagt, buf);
        let bf = check_bic(blocks[cur].creditor_bic, opts, lim);
        if bf.kind != F_NONE { return bf; }
    }
    let cb = child(doc, id, "ChrgBr");
    if cb >= 0 {
        blocks[cur].charge_bearer = text_of(doc, cb, buf);
        let cbf = check_bearer(blocks[cur].charge_bearer, opts, lim);
        if cbf.kind != F_NONE { return cbf; }
    }
    let sid = child(doc, id, "CdtrSchmeId");
    if sid >= 0 { blocks[cur].scheme_id = scheme_of(doc, sid, buf); }
    let sf0 = check_text(blocks[cur].scheme_id, 35, "CdtrSchmeId", opts.epc_charset, lim);
    if sf0.kind != F_NONE { return sf0; }
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT && n.local == "DrctDbtTxInf" {
            if items.len >= lim.max_items {
                return fault(F_LIMIT, 0, 0, "DrctDbtTxInf", "more items than the limits allow");
            }
            items.push(new_direct_debit());
            let tf = parse_debit(doc, c, opts, lim, blocks, cur, items, items.len - 1, buf);
            if tf.kind != F_NONE { return tf; }
        }
        c = n.next_sibling;
    }
    let start = blocks[cur].item_start as i64;
    let count = items.len - start;
    var sum: i64 = 0;
    if count > 0 && child(doc, id, "CtrlSum") >= 0 {
        let t, sf = sum_debits(items, start, count);
        if sf.kind != F_NONE { return sf; }
        sum = t;
    }
    if count > 0 { return check_block_totals(doc, id, count, sum, items[start].amount.code, opts, buf); }
    return check_block_totals(doc, id, count, sum, "", opts, buf);
}

// parse_debit reads one collection.
fn parse_debit(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
               blocks: DebitInfo[>..]&, cur: i64, items: DirectDebit[>..]&, at: i64,
               buf: u8[>..]&) -> Fault {
    let pid = child(doc, id, "PmtId");
    if pid >= 0 {
        let eid = child(doc, pid, "EndToEndId");
        if eid >= 0 {
            items[at].end_to_end_id = text_of(doc, eid, buf);
            let ef = check_text(items[at].end_to_end_id, 35, "EndToEndId", opts.epc_charset, lim);
            if ef.kind != F_NONE { return ef; }
        }
    }
    let inst = child(doc, id, "InstdAmt");
    if inst >= 0 {
        let ccy, has = xml::attr_lookup(doc, doc.nodes[inst], "Ccy");
        if !has || ccy.len != 3 { return fault(F_AMOUNT, 0, 0, "InstdAmt", "the amount names no currency"); }
        var mbuf: u8[>..] = [];
        let minor, af = parse_amount(text_of(doc, inst, mbuf), ccy, "InstdAmt");
        if af.kind != F_NONE { return af; }
        let m, okm = finance::money(minor, ccy);
        if !okm { return fault(F_AMOUNT, 0, 0, "InstdAmt", "the currency table holds not the currency"); }
        items[at].amount = m;
    } else {
        return fault(F_SYNTAX, 0, 0, "InstdAmt", "the item holds no amount");
    }
    let tx = child(doc, id, "DrctDbtTx");
    if tx >= 0 {
        let mi = child(doc, tx, "MndtRltdInf");
        if mi >= 0 {
            let mid = child(doc, mi, "MndtId");
            if mid >= 0 {
                items[at].mandate_id = text_of(doc, mid, buf);
                let mf = check_text(items[at].mandate_id, 35, "MndtId", opts.epc_charset, lim);
                if mf.kind != F_NONE { return mf; }
            }
            let ds = child(doc, mi, "DtOfSgntr");
            if ds >= 0 {
                let y, m, d, df = parse_date(text_of(doc, ds, buf), "DtOfSgntr");
                if df.kind != F_NONE { return df; }
                items[at].signature_year = y;
                items[at].signature_month = m;
                items[at].signature_day = d;
                items[at].has_signature_date = true;
            }
            let am = child(doc, mi, "AmdmntInd");
            if am >= 0 {
                let v, ff = parse_flag(text_of(doc, am, buf), "AmdmntInd");
                if ff.kind != F_NONE { return ff; }
                items[at].has_amendment = true;
                items[at].amendment = v;
            }
        }
        // Later schema versions place the scheme id in the transaction.
        var sid: i32 = -1;
        if blocks[cur].scheme_id.len == 0 { sid = child(doc, tx, "CdtrSchmeId"); }
        if sid >= 0 {
            blocks[cur].scheme_id = scheme_of(doc, sid, buf);
            let sf = check_text(blocks[cur].scheme_id, 35, "CdtrSchmeId", opts.epc_charset, lim);
            if sf.kind != F_NONE { return sf; }
        }
    }
    let dagt = child(doc, id, "DbtrAgt");
    if dagt >= 0 {
        items[at].debtor_bic = bic_of(doc, dagt, buf);
        let bf = check_bic(items[at].debtor_bic, opts, lim);
        if bf.kind != F_NONE { return bf; }
    }
    let dbtr = child(doc, id, "Dbtr");
    if dbtr >= 0 {
        let nm = child(doc, dbtr, "Nm");
        if nm >= 0 { items[at].debtor_name = text_of(doc, nm, buf); }
        let nf = check_text(items[at].debtor_name, 140, "Nm", opts.epc_charset, lim);
        if nf.kind != F_NONE { return nf; }
    }
    let dacct = child(doc, id, "DbtrAcct");
    if dacct >= 0 {
        let ib = account_iban(doc, dacct);
        if ib >= 0 {
            items[at].debtor_iban = text_of(doc, ib, buf);
            let ibf = check_iban_text(items[at].debtor_iban, "DbtrAcct", opts, lim);
            if ibf.kind != F_NONE { return ibf; }
        }
    }
    let rmt = child(doc, id, "RmtInf");
    if rmt >= 0 {
        let u = child(doc, rmt, "Ustrd");
        if u >= 0 {
            items[at].remittance = text_of(doc, u, buf);
            let uf = check_text(items[at].remittance, 140, "Ustrd", opts.epc_charset, lim);
            if uf.kind != F_NONE { return uf; }
        }
    }
    return no_fault();
}
