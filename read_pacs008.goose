// The reader of the pacs.008 customer credit transfer.
//
// The reader takes any version of the message. It reads the elements
// by their local names, so the namespace of the document does not
// matter. Every element it does not model is skipped.
namespace payment_file;

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import fault;
import model;
import model_pacs008;
import enums;
import charset;
import control;
import read_pain;

// read_party reads a party element: the name and the optional country.
// The country holds two capital letters, as the writer demands.
fn read_party(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
               buf: u8[>..]&) -> const u8[:], const u8[:], Fault {
    let name, nf = opt_text(doc, child(doc, id, "Nm"), "Nm", 140, opts, lim, buf);
    if nf.kind != F_NONE { return "", "", nf; }
    let adr = child(doc, id, "PstlAdr");
    let country, cf = opt_text(doc, child(doc, adr, "Ctry"), "Ctry", 2, opts, lim, buf);
    if cf.kind != F_NONE { return "", "", cf; }
    if country.len > 0 && !country_ok(country) {
        return "", "", fault(F_SYNTAX, 0, 0, "Ctry", "the country is not two capital letters");
    }
    return name, country, no_fault();
}

// account_holder gives the node that holds the account id. The Id
// element is optional, so the account itself is the holder when it is
// absent.
fn account_holder(doc: xml::Doc&, id: i32) -> i32 {
    let acct_id = child(doc, id, "Id");
    if acct_id >= 0 { return acct_id; }
    return id;
}

// read_account reads an account element. The account holds an IBAN or
// one other id. It never holds both. The IBAN passes the check digits
// unless the caller turned the check off.
fn read_account(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                buf: u8[>..]&) -> const u8[:], const u8[:], Fault {
    let holder = account_holder(doc, id);
    let iban, inf = opt_text(doc, child(doc, holder, "IBAN"), "IBAN", 34, opts, lim, buf);
    if inf.kind != F_NONE { return "", "", inf; }
    if iban.len > 0 {
        let vf = check_iban_text(iban, "IBAN", opts, lim);
        if vf.kind != F_NONE { return "", "", vf; }
    }
    let oth = child(doc, holder, "Othr");
    let other, of = opt_text(doc, child(doc, oth, "Id"), "Othr", 34, opts, lim, buf);
    if of.kind != F_NONE { return "", "", of; }
    if iban.len > 0 && other.len > 0 {
        return "", "", fault(F_SYNTAX, 0, 0, "Id", "the account holds an IBAN and an other id");
    }
    return iban, other, no_fault();
}

// read_agent reads an agent element: the BIC or the clearing system
// member id. It never holds both.
fn read_agent(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
               buf: u8[>..]&) -> const u8[:], const u8[:], Fault {
    let bic = bic_of(doc, id, buf);
    if bic.len > 0 {
        let bf = check_bic(bic, opts, lim);
        if bf.kind != F_NONE { return "", "", bf; }
    }
    let fi = child(doc, id, "FinInstnId");
    let mm = child(doc, fi, "ClrSysMmbId");
    let member, mf = opt_text(doc, child(doc, mm, "MmbId"), "MmbId", 35, opts, lim, buf);
    if mf.kind != F_NONE { return "", "", mf; }
    if bic.len > 0 && member.len > 0 {
        return "", "", fault(F_SYNTAX, 0, 0, "FinInstnId", "the agent holds a BIC and a member id");
    }
    return bic, member, no_fault();
}

// read_pacs008_tx reads one credit transfer between two banks.
fn read_pacs008_tx(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                    txs: Pacs008Tx[>..]&, cur: i64, buf: u8[>..]&) -> Fault {
    let pid = child(doc, id, "PmtId");
    if pid >= 0 {
        let iid = child(doc, pid, "InstrId");
        if iid >= 0 {
            txs[cur].instruction_id = text_of(doc, iid, buf);
            let f = check_text(txs[cur].instruction_id, 35, "InstrId", opts.epc_charset, lim);
            if f.kind != F_NONE { return f; }
        }
        let eid = child(doc, pid, "EndToEndId");
        if eid >= 0 {
            txs[cur].end_to_end_id = text_of(doc, eid, buf);
            let f = check_text(txs[cur].end_to_end_id, 35, "EndToEndId", opts.epc_charset, lim);
            if f.kind != F_NONE { return f; }
        }
        let tid = child(doc, pid, "TxId");
        if tid >= 0 {
            txs[cur].transaction_id = text_of(doc, tid, buf);
            let f = check_text(txs[cur].transaction_id, 35, "TxId", opts.epc_charset, lim);
            if f.kind != F_NONE { return f; }
        }
        let uid = child(doc, pid, "UETR");
        if uid >= 0 {
            txs[cur].uetr = text_of(doc, uid, buf);
            if !uetr_ok(txs[cur].uetr) {
                return fault(F_SYNTAX, 0, 0, "UETR", "the UETR is not a version 4 UUID");
            }
        }
    }
    let amt = child(doc, id, "IntrBkSttlmAmt");
    if amt >= 0 {
        let m, af = amount_of(doc, amt, "IntrBkSttlmAmt");
        if af.kind != F_NONE { return af; }
        txs[cur].amount = m;
    } else {
        return fault(F_SYNTAX, 0, 0, "IntrBkSttlmAmt", "the transaction holds no settlement amount");
    }
    let sdt = child(doc, id, "IntrBkSttlmDt");
    if sdt >= 0 {
        let y, m, d, df = parse_date(text_of(doc, sdt, buf), "IntrBkSttlmDt");
        if df.kind != F_NONE { return df; }
        txs[cur].has_settlement_date = true;
        txs[cur].settle_year = y;
        txs[cur].settle_month = m;
        txs[cur].settle_day = d;
    }
    if txs[cur].end_to_end_id.len == 0 {
        return fault(F_SYNTAX, 0, 0, "EndToEndId", "the end-to-end id is empty");
    }
    let chb = child(doc, id, "ChrgBr");
    if chb < 0 {
        return fault(F_SYNTAX, 0, 0, "ChrgBr", "the transaction holds no charge bearer");
    }
    txs[cur].charge_bearer = text_of(doc, chb, buf);
    let f = check_bearer(txs[cur].charge_bearer, opts, lim);
    if f.kind != F_NONE { return f; }
    let dbtr = child(doc, id, "Dbtr");
    if dbtr < 0 {
        return fault(F_SYNTAX, 0, 0, "Dbtr", "the transaction holds no debtor");
    }
    let nm, ctry, pf = read_party(doc, dbtr, opts, lim, buf);
    if pf.kind != F_NONE { return pf; }
    if nm.len == 0 {
        return fault(F_SYNTAX, 0, 0, "Dbtr", "the debtor name is empty");
    }
    txs[cur].debtor_name = nm;
    txs[cur].debtor_country = ctry;
    let dacct = child(doc, id, "DbtrAcct");
    if dacct >= 0 {
        let iban, other, f = read_account(doc, dacct, opts, lim, buf);
        if f.kind != F_NONE { return f; }
        txs[cur].debtor_iban = iban;
        txs[cur].debtor_other_id = other;
    }
    let dagt = child(doc, id, "DbtrAgt");
    if dagt < 0 {
        return fault(F_SYNTAX, 0, 0, "DbtrAgt", "the transaction holds no debtor agent");
    }
    let dbic, dmember, df = read_agent(doc, dagt, opts, lim, buf);
    if df.kind != F_NONE { return df; }
    if dbic.len == 0 && dmember.len == 0 {
        return fault(F_SYNTAX, 0, 0, "DbtrAgt", "the debtor agent holds no id");
    }
    txs[cur].debtor_bic = dbic;
    txs[cur].debtor_member_id = dmember;
    let cagt = child(doc, id, "CdtrAgt");
    if cagt < 0 {
        return fault(F_SYNTAX, 0, 0, "CdtrAgt", "the transaction holds no creditor agent");
    }
    let cbic, cmember, cf = read_agent(doc, cagt, opts, lim, buf);
    if cf.kind != F_NONE { return cf; }
    if cbic.len == 0 && cmember.len == 0 {
        return fault(F_SYNTAX, 0, 0, "CdtrAgt", "the creditor agent holds no id");
    }
    txs[cur].creditor_bic = cbic;
    txs[cur].creditor_member_id = cmember;
    let cdtr = child(doc, id, "Cdtr");
    if cdtr < 0 {
        return fault(F_SYNTAX, 0, 0, "Cdtr", "the transaction holds no creditor");
    }
    let cnm, cctry, cf2 = read_party(doc, cdtr, opts, lim, buf);
    if cf2.kind != F_NONE { return cf2; }
    if cnm.len == 0 {
        return fault(F_SYNTAX, 0, 0, "Cdtr", "the creditor name is empty");
    }
    txs[cur].creditor_name = cnm;
    txs[cur].creditor_country = cctry;
    let cacct = child(doc, id, "CdtrAcct");
    if cacct >= 0 {
        let iban, other, f = read_account(doc, cacct, opts, lim, buf);
        if f.kind != F_NONE { return f; }
        txs[cur].creditor_iban = iban;
        txs[cur].creditor_other_id = other;
    }
    let rmt = child(doc, id, "RmtInf");
    if rmt >= 0 {
        let u = child(doc, rmt, "Ustrd");
        if u >= 0 {
            txs[cur].remittance = text_of(doc, u, buf);
            let f = check_text(txs[cur].remittance, 140, "Ustrd", opts.epc_charset, lim);
            if f.kind != F_NONE { return f; }
        }
    }
    return no_fault();
}

// read_pacs008_header reads the parts of the group header that the
// credit transfer header does not hold: the settlement method, the
// settlement date, the batch booking flag and the two agents. It gives
// the node of the control sum, or -1 when the header holds none.
fn read_pacs008_header(doc: xml::Doc&, msg: i32, opts: PainOptions&, lim: Limits&,
                        header: Pacs008Header&, buf: u8[>..]&) -> Fault {
    let grp = child(doc, msg, "GrpHdr");
    if grp < 0 { return fault(F_SYNTAX, 0, 0, "GrpHdr", "the message holds no group header"); }
    let bb = child(doc, grp, "BtchBookg");
    if bb >= 0 {
        let v, f = parse_flag(text_of(doc, bb, buf), "BtchBookg");
        if f.kind != F_NONE { return f; }
        header.has_batch_booking = true;
        header.batch_booking = v;
    }
    let sdt = child(doc, grp, "IntrBkSttlmDt");
    if sdt >= 0 {
        let y, m, d, df = parse_date(text_of(doc, sdt, buf), "IntrBkSttlmDt");
        if df.kind != F_NONE { return df; }
        header.has_settlement_date = true;
        header.settle_year = y;
        header.settle_month = m;
        header.settle_day = d;
    }
    let si = child(doc, grp, "SttlmInf");
    if si < 0 {
        return fault(F_SYNTAX, 0, 0, "SttlmInf", "the group header holds no settlement information");
    }
    let mtd = child(doc, si, "SttlmMtd");
    if mtd < 0 {
        return fault(F_SYNTAX, 0, 0, "SttlmMtd", "the group header holds no settlement method");
    }
    header.settlement_method = text_of(doc, mtd, buf);
    if !settle_method_ok(header.settlement_method) {
        return fault(F_SYNTAX, 0, 0, "SttlmMtd", "the settlement method is not a code of the list");
    }
    let ia = child(doc, grp, "InstgAgt");
    if ia >= 0 {
        let bic, member, f = read_agent(doc, ia, opts, lim, buf);
        if f.kind != F_NONE { return f; }
        header.instructing_bic = bic;
        if member.len > 0 {
            return fault(F_SYNTAX, 0, 0, "InstgAgt", "the instructing agent holds a member id");
        }
    }
    let id = child(doc, grp, "InstdAgt");
    if id >= 0 {
        let bic, member, f = read_agent(doc, id, opts, lim, buf);
        if f.kind != F_NONE { return f; }
        header.instructed_bic = bic;
        if member.len > 0 {
            return fault(F_SYNTAX, 0, 0, "InstdAgt", "the instructed agent holds a member id");
        }
    }
    return no_fault();
}

// pacs_ccy gives the currency of the transactions. It gives an empty
// text when the message holds no transaction or holds two currencies.
fn pacs_ccy(txs: Pacs008Tx[>..]&, count: i64, mixed: bool) -> const u8[:] {
    if count > 0 && !mixed { return txs[0].amount.code; }
    return "";
}

// check_pacs008_totals checks the count and the sum of the group
// header against the transactions. The count must stand. A message
// with two currencies has no sum to check, so only the count is
// checked. The total of the group names its currency, and that
// currency must be the currency of the transactions.
fn check_pacs008_totals(doc: xml::Doc&, grp: i32, cs: i32, txs: Pacs008Tx[>..]&,
                         header: Pacs008Header&, opts: PainOptions&, lim: Limits&,
                         buf: u8[>..]&) -> Fault {
    let count = txs.len;
    let total, mixed, sf = sum_settle(txs, 0, count);
    if sf.kind != F_NONE { return sf; }
    let ccy = pacs_ccy(txs, count, mixed);
    if !header.base.has_count {
        return fault(F_SYNTAX, 0, 0, "NbOfTxs", "the group header holds no count of transactions");
    }
    if header.base.count != count {
        return fault_sums(F_TOTAL, 0, "NbOfTxs", "the count of transactions differs from the items", count, header.base.count);
    }
    let tt = child(doc, grp, "TtlIntrBkSttlmAmt");
    if mixed {
        if cs >= 0 {
            return fault(F_TOTAL, 0, 0, "CtrlSum", "the control sum stands but the transactions hold two currencies");
        }
        if tt >= 0 {
            return fault(F_TOTAL, 0, 0, "TtlIntrBkSttlmAmt", "the total stands but the transactions hold two currencies");
        }
        return no_fault();
    }
    if cs >= 0 {
        let claimed, cf = check_claimed(text_of(doc, cs, buf), total, ccy, "CtrlSum", opts.skip_control_sum_check);
        if cf.kind != F_NONE { return cf; }
        header.base.has_control_sum = true;
        header.base.control_sum = claimed;
        header.base.control_currency = ccy;
    }
    if tt >= 0 {
        // The total of the group names its currency. The amounts of the
        // transactions hold one currency, so the two must match. The
        // total is the sum of the settlement amounts, so the values
        // must match too.
        let m, af = amount_of(doc, tt, "TtlIntrBkSttlmAmt");
        if af.kind != F_NONE { return af; }
        if !finance::money_same(m, txs[0].amount) {
            return fault(F_AMOUNT, 0, 0, "TtlIntrBkSttlmAmt", "the total names another currency than the transactions");
        }
        if !opts.skip_control_sum_check && m.minor != total {
            return fault_sums(F_TOTAL, 0, "TtlIntrBkSttlmAmt", "the total differs from the transactions", total, m.minor);
        }
        if cs < 0 {
            header.base.has_control_sum = true;
            header.base.control_sum = m.minor;
            header.base.control_currency = ccy;
        }
    }
    if cs < 0 && tt < 0 && !opts.skip_control_sum_check {
        return fault(F_TOTAL, 0, 0, "GrpHdr", "the group header holds no sum of the transactions");
    }
    return no_fault();
}

// parse_pacs008 reads the customer credit transfer. The transactions
// go into the flat array of the caller. The texts point into the
// buffer of the caller, so the buffer must outlive them. The input may
// go away after the call.
fn parse_pacs008(input: const u8[:], lim: Limits&, opts: PainOptions&,
                 header: Pacs008Header&, txs: Pacs008Tx[>..]&, buf: u8[>..]&) -> Fault {
    if input.len > lim.max_input {
        return fault(F_LIMIT, 0, 0, "", "the document is longer than max_input");
    }
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(input, nodes, attrs);
    if !ok { return fault(F_SYNTAX, 0, 0, "", "the document is not well formed XML"); }
    let msg, df = check_doc(doc, lim, "FIToFICstmrCdtTrf");
    if df.kind != F_NONE { return df; }
    header = new_pacs008_header();
    let cs, gf = parse_group(doc, msg, opts, lim, header.base, buf);
    if gf.kind != F_NONE { return gf; }
    let grp = child(doc, msg, "GrpHdr");
    let hf = read_pacs008_header(doc, msg, opts, lim, header, buf);
    if hf.kind != F_NONE { return hf; }
    // The transactions.
    var c = doc.nodes[msg].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT && n.local == "CdtTrfTxInf" {
            if txs.len >= lim.max_items {
                return fault(F_LIMIT, 0, 0, "CdtTrfTxInf", "more transactions than the limits allow");
            }
            txs.push(new_pacs008_tx());
            let cur = txs.len - 1;
            let tf = read_pacs008_tx(doc, c, opts, lim, txs, cur, buf);
            if tf.kind != F_NONE { return tf; }
        }
        c = n.next_sibling;
    }
    if txs.len == 0 {
        return fault(F_SYNTAX, 0, 0, "FIToFICstmrCdtTrf", "the message holds no transaction");
    }
    return check_pacs008_totals(doc, grp, cs, txs, header, opts, lim, buf);
}
