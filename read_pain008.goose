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
import model_party;
import charset;
import control;
import enums;
import read_pain;
import read_party;

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
    let cs, gf = parse_group(doc, msg, opts, lim, header, buf, true);
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

// read_original_agent reads an agent of a mandate amendment. The agent
// holds a BIC or an other identifier.
fn read_original_agent(doc: xml::Doc&, id: i32, tag: const u8[:], opts: PainOptions&, lim: Limits&,
                       buf: u8[>..]&) -> OriginalAgent, Fault {
    var a = new_original_agent();
    let fi, f0 = need(doc, id, "FinInstnId");
    if f0.kind != F_NONE { return a, f0; }
    a.present = true;
    a.bic = bic_of(doc, id, buf);
    let bf = check_bic(a.bic, opts, lim);
    if bf.kind != F_NONE { return a, bf; }
    let oth = child(doc, fi, "Othr");
    if oth >= 0 {
        let oid, of = opt_text(doc, child(doc, oth, "Id"), "Id", MAX_35, opts, lim, buf);
        if of.kind != F_NONE { return a, of; }
        a.other_id = oid;
    }
    if a.bic.len > 0 && a.other_id.len > 0 {
        return a, fault(F_SYNTAX, 0, 0, tag, "the agent holds a BIC and an other identifier");
    }
    return a, no_fault();
}

// read_original_party reads a party of a mandate amendment. The name
// is optional here, as in the writer.
fn read_original_party(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                       buf: u8[>..]&, d: PartyDetail&) -> const u8[:], Fault {
    let sf = single(doc, id, "Nm");
    if sf.kind != F_NONE { return "", sf; }
    let nm, f0 = opt_text(doc, child(doc, id, "Nm"), "Nm", MAX_140, opts, lim, buf);
    if f0.kind != F_NONE { return "", f0; }
    let f1 = read_detail(doc, id, opts, lim, buf, d);
    if f1.kind != F_NONE { return "", f1; }
    return nm, no_fault();
}

// read_original_account reads the IBAN of an account of a mandate
// amendment. An account with no IBAN gives an empty text.
fn read_original_account(doc: xml::Doc&, id: i32, tag: const u8[:], opts: PainOptions&, lim: Limits&,
                         buf: u8[>..]&) -> const u8[:], Fault {
    let ib = account_iban(doc, id);
    if ib < 0 { return "", no_fault(); }
    let iban = text_of(doc, ib, buf);
    let f = check_iban_text(iban, tag, opts, lim);
    if f.kind != F_NONE { return "", f; }
    return iban, no_fault();
}

// read_amendment reads the details of a mandate amendment. A second
// copy of an element is a fault, so the first never hides a later one.
fn read_amendment(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                  buf: u8[>..]&, a: MandateAmendment&) -> Fault {
    var sg = single(doc, id, "OrgnlMndtId");
    if sg.kind == F_NONE { sg = single(doc, id, "OrgnlCdtrSchmeId"); }
    if sg.kind == F_NONE { sg = single(doc, id, "OrgnlCdtrAgt"); }
    if sg.kind == F_NONE { sg = single(doc, id, "OrgnlCdtrAgtAcct"); }
    if sg.kind == F_NONE { sg = single(doc, id, "OrgnlDbtr"); }
    if sg.kind == F_NONE { sg = single(doc, id, "OrgnlDbtrAcct"); }
    if sg.kind == F_NONE { sg = single(doc, id, "OrgnlDbtrAgt"); }
    if sg.kind == F_NONE { sg = single(doc, id, "OrgnlDbtrAgtAcct"); }
    if sg.kind == F_NONE { sg = single(doc, id, "OrgnlFnlColltnDt"); }
    if sg.kind != F_NONE { return sg; }
    let mid, f0 = opt_text(doc, child(doc, id, "OrgnlMndtId"), "OrgnlMndtId", MAX_35, opts, lim, buf);
    if f0.kind != F_NONE { return f0; }
    a.mandate_id = mid;
    let cs = child(doc, id, "OrgnlCdtrSchmeId");
    if cs >= 0 {
        let nm, f1 = read_original_party(doc, cs, opts, lim, buf, a.creditor_detail);
        if f1.kind != F_NONE { return f1; }
        a.creditor_name = nm;
    }
    let ca = child(doc, id, "OrgnlCdtrAgt");
    if ca >= 0 {
        let ag, f2 = read_original_agent(doc, ca, "OrgnlCdtrAgt", opts, lim, buf);
        if f2.kind != F_NONE { return f2; }
        a.creditor_agent = ag;
    }
    let cac = child(doc, id, "OrgnlCdtrAgtAcct");
    if cac >= 0 {
        let ib, f3 = read_original_account(doc, cac, "OrgnlCdtrAgtAcct", opts, lim, buf);
        if f3.kind != F_NONE { return f3; }
        a.creditor_agent_iban = ib;
    }
    let db = child(doc, id, "OrgnlDbtr");
    if db >= 0 {
        let nm, f4 = read_original_party(doc, db, opts, lim, buf, a.debtor_detail);
        if f4.kind != F_NONE { return f4; }
        a.debtor_name = nm;
    }
    let dac = child(doc, id, "OrgnlDbtrAcct");
    if dac >= 0 {
        let ib, f5 = read_original_account(doc, dac, "OrgnlDbtrAcct", opts, lim, buf);
        if f5.kind != F_NONE { return f5; }
        a.debtor_iban = ib;
    }
    let da = child(doc, id, "OrgnlDbtrAgt");
    if da >= 0 {
        let ag, f6 = read_original_agent(doc, da, "OrgnlDbtrAgt", opts, lim, buf);
        if f6.kind != F_NONE { return f6; }
        a.debtor_agent = ag;
    }
    let dag = child(doc, id, "OrgnlDbtrAgtAcct");
    if dag >= 0 {
        let ib, f7 = read_original_account(doc, dag, "OrgnlDbtrAgtAcct", opts, lim, buf);
        if f7.kind != F_NONE { return f7; }
        a.debtor_agent_iban = ib;
    }
    let fd = child(doc, id, "OrgnlFnlColltnDt");
    if fd >= 0 {
        let y, m, d, f8 = parse_date(text_of(doc, fd, buf), "OrgnlFnlColltnDt");
        if f8.kind != F_NONE { return f8; }
        a.final_year = y; a.final_month = m; a.final_day = d; a.has_final_date = true;
    }
    return no_fault();
}

// parse_debit_block reads one payment block.
fn parse_debit_block(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                     blocks: DebitInfo[>..]&, cur: i64, items: DirectDebit[>..]&,
                     buf: u8[>..]&) -> Fault {
    let nf0 = need_block(doc, id, "ReqdColltnDt", "Cdtr", "CdtrAcct", "CdtrAgt");
    if nf0.kind != F_NONE { return nf0; }
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
    // The payment type: the service level, the local instrument and
    // the sequence type.
    let sl, slf = read_service_level(doc, id, opts, lim, buf);
    if slf.kind != F_NONE { return slf; }
    blocks[cur].service_level = sl;
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
        let nm, cf = read_party_full(doc, cdtr, MAX_140, true, opts, lim, buf, blocks[cur].creditor_detail, "Cdtr");
        if cf.kind != F_NONE { return cf; }
        blocks[cur].creditor_name = nm;
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
    let uc = child(doc, id, "UltmtCdtr");
    if uc >= 0 {
        let nm, uf = read_party_full(doc, uc, MAX_140, false, opts, lim, buf, blocks[cur].ultimate_creditor_detail, "UltmtCdtr");
        if uf.kind != F_NONE { return uf; }
        blocks[cur].ultimate_creditor_name = nm;
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
    let tf0 = check_block_totals(doc, id, count, sum, "", opts, buf);
    if tf0.kind != F_NONE { return tf0; }
    return missing_items("DrctDbtTxInf");
}

// parse_debit reads one collection.
fn parse_debit(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
               blocks: DebitInfo[>..]&, cur: i64, items: DirectDebit[>..]&, at: i64,
               buf: u8[>..]&) -> Fault {
    let nf0 = need_pmt_id(doc, id);
    if nf0.kind != F_NONE { return nf0; }
    let nf1 = need_parties(doc, id, "Dbtr", "DbtrAcct", "DbtrAgt");
    if nf1.kind != F_NONE { return nf1; }
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
        let m, af = amount_of(doc, inst, "InstdAmt");
        if af.kind != F_NONE { return af; }
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
            var sg = single(doc, mi, "AmdmntInfDtls");
            if sg.kind == F_NONE { sg = single(doc, mi, "ElctrncSgntr"); }
            if sg.kind != F_NONE { return sg; }
            let ad = child(doc, mi, "AmdmntInfDtls");
            if ad >= 0 {
                let af = read_amendment(doc, ad, opts, lim, buf, items[at].amendment_details);
                if af.kind != F_NONE { return af; }
                if !amendment_empty(items[at].amendment_details) && !(items[at].has_amendment && items[at].amendment) {
                    return fault(F_SYNTAX, 0, 0, "AmdmntInfDtls", "the amendment details need the amendment indicator set to true");
                }
            }
            let es, ef = opt_text(doc, child(doc, mi, "ElctrncSgntr"), "ElctrncSgntr", 1025, opts, lim, buf);
            if ef.kind != F_NONE { return ef; }
            items[at].electronic_signature = es;
        }
        var sg = single(doc, tx, "PreNtfctnId");
        if sg.kind == F_NONE { sg = single(doc, tx, "PreNtfctnDt"); }
        if sg.kind != F_NONE { return sg; }
        let pnid, pnf = opt_text(doc, child(doc, tx, "PreNtfctnId"), "PreNtfctnId", MAX_35, opts, lim, buf);
        if pnf.kind != F_NONE { return pnf; }
        items[at].pre_notification_id = pnid;
        let pnd = child(doc, tx, "PreNtfctnDt");
        if pnd >= 0 {
            let y, m, d, pdf = parse_date(text_of(doc, pnd, buf), "PreNtfctnDt");
            if pdf.kind != F_NONE { return pdf; }
            items[at].pre_notification_year = y;
            items[at].pre_notification_month = m;
            items[at].pre_notification_day = d;
            items[at].has_pre_notification_date = true;
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
    let uc2 = child(doc, id, "UltmtCdtr");
    if uc2 >= 0 {
        let nm, uf2 = read_party_full(doc, uc2, MAX_140, false, opts, lim, buf, items[at].ultimate_creditor_detail, "UltmtCdtr");
        if uf2.kind != F_NONE { return uf2; }
        items[at].ultimate_creditor_name = nm;
    }
    let dagt = child(doc, id, "DbtrAgt");
    if dagt >= 0 {
        items[at].debtor_bic = bic_of(doc, dagt, buf);
        let bf = check_bic(items[at].debtor_bic, opts, lim);
        if bf.kind != F_NONE { return bf; }
    }
    let dbtr = child(doc, id, "Dbtr");
    if dbtr >= 0 {
        let nm, df2 = read_party_full(doc, dbtr, MAX_140, true, opts, lim, buf, items[at].debtor_detail, "Dbtr");
        if df2.kind != F_NONE { return df2; }
        items[at].debtor_name = nm;
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
    let ud = child(doc, id, "UltmtDbtr");
    if ud >= 0 {
        let nm, uf3 = read_party_full(doc, ud, MAX_140, false, opts, lim, buf, items[at].ultimate_debtor_detail, "UltmtDbtr");
        if uf3.kind != F_NONE { return uf3; }
        items[at].ultimate_debtor_name = nm;
    }
    let purp_code, pf = read_purpose(doc, id, opts, lim, buf);
    if pf.kind != F_NONE { return pf; }
    items[at].purpose = purp_code;
    let rmt = child(doc, id, "RmtInf");
    if rmt >= 0 {
        let u = child(doc, rmt, "Ustrd");
        if u >= 0 {
            items[at].remittance = text_of(doc, u, buf);
            let uf4 = check_text(items[at].remittance, MAX_140, "Ustrd", opts.epc_charset, lim);
            if uf4.kind != F_NONE { return uf4; }
        }
        let strd = child(doc, rmt, "Strd");
        if strd >= 0 {
            let refi = child(doc, strd, "CdtrRefInf");
            if refi >= 0 {
                let r, cf2 = read_cdtr_ref(doc, refi, opts, lim, buf);
                if cf2.kind != F_NONE { return cf2; }
                items[at].structured_type = r.code;
                items[at].structured_proprietary_type = r.proprietary_type;
                items[at].structured_issuer = r.issuer;
                items[at].structured_ref = r.ref;
            }
        }
    }
    return no_fault();
}
