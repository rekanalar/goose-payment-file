// The writer of the pacs.008 customer credit transfer.
//
// The message holds one group header and a flat array of
// transactions. The elements follow the order of the ISO schema, which
// is a sequence. The writer computes the count and the control sum
// from the transactions.
namespace payment_file;

import std;
import fault;
import model;
import model_pacs008;
import enums;
import charset;
import control;
import write_pain;

// party_ex writes a party element with its name and its optional
// country. The name limit is the limit of the EPC rulebook, not the
// one of the schema. The country holds two capital letters.
fn party_ex(out: u8[>..]&, tag: const u8[:], name: const u8[:], country: const u8[:],
            depth: i64, opts: PainWriteOptions, lim: Limits&) -> Fault {
    if country.len > 0 {
        if country.len != 2 || country[0] < 'A' || country[0] > 'Z'
           || country[1] < 'A' || country[1] > 'Z' {
            return fault(F_SYNTAX, 0, 0, "Ctry", "the country is not two capital letters");
        }
    }
    open(out, tag, depth, opts);
    let f = text_leaf(out, "Nm", name, 70, true, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    if country.len > 0 {
        open(out, "PstlAdr", depth + 1, opts);
        let cf = text_leaf(out, "Ctry", country, 2, true, depth + 2, opts, lim);
        if cf.kind != F_NONE { return cf; }
        close(out, "PstlAdr", depth + 1, opts);
    }
    close(out, tag, depth, opts);
    return no_fault();
}

// account_ex writes an account element. The account holds an IBAN that
// passes the check digits, or one other id. It never holds both.
fn account_ex(out: u8[>..]&, tag: const u8[:], iban: const u8[:], other_id: const u8[:],
              depth: i64, opts: PainWriteOptions, lim: Limits&) -> Fault {
    if iban.len > 0 && other_id.len > 0 {
        return fault(F_SYNTAX, 0, 0, tag, "the account holds an IBAN and an other id");
    }
    if iban.len == 0 && other_id.len == 0 {
        // The schema makes the account optional. An absent account is
        // no fault. The caller writes no account element then.
        return no_fault();
    }
    open(out, tag, depth, opts);
    open(out, "Id", depth + 1, opts);
    var f = no_fault();
    if iban.len > 0 {
        if !payment_identifier::iban_is_valid(iban) {
            return fault(F_IBAN, 0, 0, tag, "the IBAN does not pass the check digits");
        }
        f = text_leaf(out, "IBAN", iban, 34, true, depth + 2, opts, lim);
    } else {
        open(out, "Othr", depth + 2, opts);
        f = text_leaf(out, "Id", other_id, 34, true, depth + 3, opts, lim);
        close(out, "Othr", depth + 2, opts);
    }
    if f.kind != F_NONE { return f; }
    close(out, "Id", depth + 1, opts);
    close(out, tag, depth, opts);
    return no_fault();
}

// agent_ex writes an agent element. The agent holds a BIC, or one
// clearing system member id. It never holds both.
fn agent_ex(out: u8[>..]&, tag: const u8[:], bic: const u8[:], member_id: const u8[:],
            depth: i64, opts: PainWriteOptions, lim: Limits&) -> Fault {
    if bic.len > 0 && member_id.len > 0 {
        return fault(F_SYNTAX, 0, 0, tag, "the agent holds a BIC and a member id");
    }
    if bic.len == 0 && member_id.len == 0 {
        return fault(F_SYNTAX, 0, 0, tag, "the agent holds no id");
    }
    open(out, tag, depth, opts);
    open(out, "FinInstnId", depth + 1, opts);
    var f = no_fault();
    if bic.len > 0 {
        if !bic_ok(bic) { return fault(F_SYNTAX, 0, 0, "BICFI", "the BIC is not 8 or 11 capital letters and digits"); }
        f = text_leaf(out, "BICFI", bic, 11, true, depth + 2, opts, lim);
    } else {
        open(out, "ClrSysMmbId", depth + 2, opts);
        f = text_leaf(out, "MmbId", member_id, 35, true, depth + 3, opts, lim);
        close(out, "ClrSysMmbId", depth + 2, opts);
    }
    if f.kind != F_NONE { return f; }
    close(out, "FinInstnId", depth + 1, opts);
    close(out, tag, depth, opts);
    return no_fault();
}

// check_tx checks the facts of one transaction. The writer checks the
// whole message before the first byte goes out.
fn check_tx(t: Pacs008Tx, lim: Limits&) -> Fault {
    if t.amount.minor < 0 {
        return fault(F_AMOUNT, 0, 0, "IntrBkSttlmAmt", "the schema allows no negative amount");
    }
    if t.end_to_end_id.len == 0 {
        return fault(F_SYNTAX, 0, 0, "EndToEndId", "the end-to-end id is empty");
    }
    if t.uetr.len > 0 && !uetr_ok(t.uetr) {
        return fault(F_SYNTAX, 0, 0, "UETR", "the UETR is not a version 4 UUID");
    }
    if !charge_bearer_ok(t.charge_bearer) {
        return fault(F_SYNTAX, 0, 0, "ChrgBr", "the charge bearer is not a code of the list");
    }
    if t.debtor_name.len == 0 {
        return fault(F_SYNTAX, 0, 0, "Dbtr", "the debtor name is empty");
    }
    if t.creditor_name.len == 0 {
        return fault(F_SYNTAX, 0, 0, "Cdtr", "the creditor name is empty");
    }
    if t.has_settlement_date && !finance::date_ok(t.settle_year as i64, t.settle_month as i64, t.settle_day as i64) {
        return fault(F_DATE, 0, 0, "IntrBkSttlmDt", "the settlement date is missing or not valid");
    }
    return no_fault();
}

// write_pacs008_tx writes one credit transfer between two banks.
fn write_pacs008_tx(out: u8[>..]&, t: Pacs008Tx, opts: PainWriteOptions, lim: Limits&) -> Fault {
    var f = no_fault();
    open(out, "CdtTrfTxInf", 2, opts);
    open(out, "PmtId", 3, opts);
    if t.instruction_id.len > 0 {
        f = text_leaf(out, "InstrId", t.instruction_id, 35, true, 4, opts, lim);
        if f.kind != F_NONE { return f; }
    }
    f = text_leaf(out, "EndToEndId", t.end_to_end_id, 35, true, 4, opts, lim);
    if f.kind != F_NONE { return f; }
    if t.transaction_id.len > 0 {
        f = text_leaf(out, "TxId", t.transaction_id, 35, true, 4, opts, lim);
        if f.kind != F_NONE { return f; }
    }
    if t.uetr.len > 0 {
        f = text_leaf(out, "UETR", t.uetr, 36, true, 4, opts, lim);
        if f.kind != F_NONE { return f; }
    }
    close(out, "PmtId", 3, opts);
    f = amt_leaf(out, "IntrBkSttlmAmt", t.amount.minor, t.amount.code, 3, opts);
    if f.kind != F_NONE { return f; }
    if t.has_settlement_date {
        f = date_leaf(out, "IntrBkSttlmDt", t.settle_year, t.settle_month, t.settle_day, 3, opts);
        if f.kind != F_NONE { return f; }
    }
    f = text_leaf(out, "ChrgBr", t.charge_bearer, 4, true, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    f = party_ex(out, "Dbtr", t.debtor_name, t.debtor_country, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    f = account_ex(out, "DbtrAcct", t.debtor_iban, t.debtor_other_id, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    f = agent_ex(out, "DbtrAgt", t.debtor_bic, t.debtor_member_id, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    f = agent_ex(out, "CdtrAgt", t.creditor_bic, t.creditor_member_id, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    f = party_ex(out, "Cdtr", t.creditor_name, t.creditor_country, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    f = account_ex(out, "CdtrAcct", t.creditor_iban, t.creditor_other_id, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    if t.remittance.len > 0 {
        open(out, "RmtInf", 3, opts);
        f = text_leaf(out, "Ustrd", t.remittance, 140, true, 4, opts, lim);
        if f.kind != F_NONE { return f; }
        close(out, "RmtInf", 3, opts);
    }
    close(out, "CdtTrfTxInf", 2, opts);
    return no_fault();
}

// write_pacs008 writes the customer credit transfer. The transactions
// live in a flat array. The count and the control sum of the group
// header come from the transactions. The writer writes all or nothing:
// a fault leaves the buffer of the caller as it was.
fn write_pacs008(header: Pacs008Header, txs: Pacs008Tx[>..]&, opts: PainWriteOptions,
                 lim: Limits&, out: u8[>..]&) -> Fault {
    if txs.len > lim.max_items {
        return fault(F_LIMIT, 0, 0, "CdtTrfTxInf", "more transactions than the limits allow");
    }
    if txs.len == 0 {
        return fault(F_SYNTAX, 0, 0, "CdtTrfTxInf", "the message holds no transaction");
    }
    if !settle_method_ok(header.settlement_method) {
        return fault(F_SYNTAX, 0, 0, "SttlmMtd", "the settlement method is not a code of the list");
    }
    if !header.base.has_creation
       || !finance::date_ok(header.base.creation_year as i64, header.base.creation_month as i64,
                            header.base.creation_day as i64)
       || header.base.creation_minutes < 0 || header.base.creation_minutes >= 1440 {
        return fault(F_DATE, 0, 0, "CreDtTm", "the creation time is missing or not valid");
    }
    if !header.has_settlement_date
       || !finance::date_ok(header.settle_year as i64, header.settle_month as i64, header.settle_day as i64) {
        return fault(F_DATE, 0, 0, "IntrBkSttlmDt", "the settlement date is missing or not valid");
    }
    var p: i64 = 0;
    while p < txs.len {
        let cf = check_tx(txs[p], lim);
        if cf.kind != F_NONE { return cf; }
        p += 1;
    }
    let total, mixed, sf = sum_settle(txs, 0, txs.len);
    if sf.kind != F_NONE { return sf; }
    var body: u8[>..] = [];
    put(body, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
    if opts.indent { body.push('\n'); }
    put(body, "<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08\">");
    if opts.indent { body.push('\n'); }
    open(body, "FIToFICstmrCdtTrf", 1, opts);
    open(body, "GrpHdr", 2, opts);
    var f = text_leaf(body, "MsgId", header.base.message_id, 35, true, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    var dt: u8[>..] = [];
    put_dt(dt, header.base);
    leaf(body, "CreDtTm", dt, 3, opts);
    if header.has_batch_booking {
        flag_leaf(body, "BtchBookg", header.batch_booking, 3, opts);
    }
    var nb: u8[>..] = [];
    put_count(nb, txs.len);
    leaf(body, "NbOfTxs", nb, 3, opts);
    if !mixed {
        var cs: u8[>..] = [];
        let af = amount_text(cs, total, txs[0].amount.code);
        if af.kind != F_NONE { return af; }
        leaf(body, "CtrlSum", cs, 3, opts);
        let tf = amt_leaf(body, "TtlIntrBkSttlmAmt", total, txs[0].amount.code, 3, opts);
        if tf.kind != F_NONE { return tf; }
    }
    let df = date_leaf(body, "IntrBkSttlmDt", header.settle_year, header.settle_month, header.settle_day, 3, opts);
    if df.kind != F_NONE { return df; }
    open(body, "SttlmInf", 3, opts);
    let mf = text_leaf(body, "SttlmMtd", header.settlement_method, 4, true, 4, opts, lim);
    if mf.kind != F_NONE { return mf; }
    close(body, "SttlmInf", 3, opts);
    if header.instructing_bic.len > 0 {
        let iaf = agent_ex(&body, "InstgAgt", header.instructing_bic, "", 3, opts, lim);
        if iaf.kind != F_NONE { return iaf; }
    }
    if header.instructed_bic.len > 0 {
        let idf = agent_ex(&body, "InstdAgt", header.instructed_bic, "", 3, opts, lim);
        if idf.kind != F_NONE { return idf; }
    }
    close(body, "GrpHdr", 2, opts);
    var k: i64 = 0;
    while k < txs.len {
        let tf = write_pacs008_tx(&body, txs[k], opts, lim);
        if tf.kind != F_NONE { return tf; }
        k += 1;
    }
    close(body, "FIToFICstmrCdtTrf", 1, opts);
    close(body, "Document", 0, opts);
    put(out, body);
    return no_fault();
}
