// The writer of the pain.008 direct debit.
//
// The writer emits the pain.008.001.02 form. The schema is a sequence,
// so the children follow its order. The count and the control sums come
// from the items, never from the caller. Every text passes the EPC set
// and its length limit, and every escape character becomes an entity.
namespace payment_file;

import std;
import finance from "rekanalar/goose-finance@v0.1.0";
import fault;
import model;
import model_debit;
import charset;
import control;
import enums;
import write_pain;

// scheme_leaf writes the creditor scheme id as a private identification
// with the scheme name SEPA.
fn scheme_leaf(out: u8[>..]&, id: const u8[:], depth: i64, opts: PainWriteOptions, lim: Limits&) -> Fault {
    open(out, "CdtrSchmeId", depth, opts);
    open(out, "Id", depth + 1, opts);
    open(out, "PrvtId", depth + 2, opts);
    open(out, "Othr", depth + 3, opts);
    let f = text_leaf(out, "Id", id, 35, true, depth + 4, opts, lim);
    if f.kind != F_NONE { return f; }
    open(out, "SchmeNm", depth + 4, opts);
    leaf(out, "Prtry", "SEPA", depth + 5, opts);
    close(out, "SchmeNm", depth + 4, opts);
    close(out, "Othr", depth + 3, opts);
    close(out, "PrvtId", depth + 2, opts);
    close(out, "Id", depth + 1, opts);
    close(out, "CdtrSchmeId", depth, opts);
    return no_fault();
}

// write_pain008 writes the direct debit initiation. The blocks and the
// items live in flat arrays. The control sum of the group header is the
// sum over every item.
fn write_pain008(header: GrpHeader, blocks: DebitInfo[>..]&, items: DirectDebit[>..]&,
                 opts: PainWriteOptions, lim: Limits&, out: u8[>..]&) -> Fault {
    if blocks.len > lim.max_payments {
        return fault(F_LIMIT, 0, 0, "PmtInf", "more payment blocks than the limits allow");
    }
    if items.len > lim.max_items {
        return fault(F_LIMIT, 0, 0, "DrctDbtTxInf", "more items than the limits allow");
    }
    if blocks.len == 0 {
        return fault(F_SYNTAX, 0, 0, "PmtInf", "the message holds no payment block");
    }
    if items.len == 0 {
        return fault(F_SYNTAX, 0, 0, "DrctDbtTxInf", "the message holds no direct debit item");
    }
    // The blocks must tile the items: each item sits in exactly one block.
    var next: i64 = 0;
    var q: i64 = 0;
    while q < blocks.len {
        if blocks[q].item_start as i64 != next {
            return fault(F_LIMIT, 0, 0, "PmtInf", "the item ranges of the blocks do not follow each other");
        }
        next += blocks[q].item_count as i64;
        q += 1;
    }
    if next != items.len { return fault(F_LIMIT, 0, 0, "PmtInf", "the blocks do not cover every item"); }
    // Check the whole message before the first byte goes out.
    let total, sf = sum_debits(items, 0, items.len);
    if sf.kind != F_NONE { return sf; }
    let gf = write_group(out, "pain.008.001.02", "CstmrDrctDbtInitn", header, items.len, total, items[0].amount.code, opts, lim);
    if gf.kind != F_NONE { return gf; }
    var b: i64 = 0;
    while b < blocks.len {
        let bf = write_debit_block(out, blocks[b], items, opts, lim);
        if bf.kind != F_NONE { return bf; }
        b += 1;
    }
    close(out, "CstmrDrctDbtInitn", 1, opts);
    close(out, "Document", 0, opts);
    return no_fault();
}

// write_debit_block writes one payment block and its items.
fn write_debit_block(out: u8[>..]&, blk: DebitInfo, items: DirectDebit[>..]&,
                     opts: PainWriteOptions, lim: Limits&) -> Fault {
    let start = blk.item_start as i64;
    let count = blk.item_count as i64;
    let sum, sf = sum_debits(items, start, count);
    if sf.kind != F_NONE { return sf; }
    if count == 0 { return fault(F_SYNTAX, 0, 0, "PmtInf", "the payment block holds no item"); }
    var cs: u8[>..] = [];
    let cf = amount_text(cs, sum, items[start].amount.code);
    if cf.kind != F_NONE { return cf; }
    if !seq_type_ok(blk.seq_type) { return fault(F_SYNTAX, 0, 0, "SeqTp", "the sequence type is not FRST, RCUR, OOFF or FNAL"); }
    if !instrument_ok(blk.instrument) { return fault(F_SYNTAX, 0, 0, "LclInstrm", "the local instrument is not CORE, COR1 or B2B"); }
    open(out, "PmtInf", 2, opts);
    var f = text_leaf(out, "PmtInfId", blk.id, 35, true, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    leaf(out, "PmtMtd", "DD", 3, opts);
    if blk.has_batch_booking {
        flag_leaf(out, "BtchBookg", blk.batch_booking, 3, opts);
    }
    var nb: u8[>..] = [];
    put_count(nb, count);
    leaf(out, "NbOfTxs", nb, 3, opts);
    leaf(out, "CtrlSum", cs, 3, opts);
    open(out, "PmtTpInf", 3, opts);
    open(out, "SvcLvl", 4, opts);
    leaf(out, "Cd", "SEPA", 5, opts);
    close(out, "SvcLvl", 4, opts);
    open(out, "LclInstrm", 4, opts);
    leaf(out, "Cd", blk.instrument, 5, opts);
    close(out, "LclInstrm", 4, opts);
    leaf(out, "SeqTp", blk.seq_type, 4, opts);
    close(out, "PmtTpInf", 3, opts);
    if !blk.has_collection_date { return fault(F_DATE, 0, 0, "ReqdColltnDt", "the collection date is missing or not valid"); }
    f = date_leaf(out, "ReqdColltnDt", blk.collection_year, blk.collection_month, blk.collection_day, 3, opts);
    if f.kind != F_NONE { return f; }
    f = party(out, "Cdtr", blk.creditor_name, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    f = account(out, "CdtrAcct", blk.creditor_iban, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    f = agent(out, "CdtrAgt", blk.creditor_bic, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    if blk.charge_bearer.len > 0 {
        if !charge_bearer_ok(blk.charge_bearer) { return fault(F_SYNTAX, 0, 0, "ChrgBr", "the charge bearer is not DEBT, CRED, SHAR or SLEV"); }
        f = text_leaf(out, "ChrgBr", blk.charge_bearer, 4, true, 3, opts, lim);
        if f.kind != F_NONE { return f; }
    }
    f = scheme_leaf(out, blk.scheme_id, 3, opts, lim);
    if f.kind != F_NONE { return f; }
    var i: i64 = start;
    while i < start + count {
        let tf = write_debit(out, items[i], opts, lim);
        if tf.kind != F_NONE { return tf; }
        i += 1;
    }
    close(out, "PmtInf", 2, opts);
    return no_fault();
}

// write_debit writes one collection.
fn write_debit(out: u8[>..]&, t: DirectDebit, opts: PainWriteOptions, lim: Limits&) -> Fault {
    if !t.has_signature_date { return fault(F_DATE, 0, 0, "DtOfSgntr", "the mandate signature date is missing or not valid"); }
    open(out, "DrctDbtTxInf", 3, opts);
    open(out, "PmtId", 4, opts);
    var f = text_leaf(out, "EndToEndId", t.end_to_end_id, 35, true, 5, opts, lim);
    if f.kind != F_NONE { return f; }
    close(out, "PmtId", 4, opts);
    f = instd_amt(out, t.amount.minor, t.amount.code, 4, opts);
    if f.kind != F_NONE { return f; }
    open(out, "DrctDbtTx", 4, opts);
    open(out, "MndtRltdInf", 5, opts);
    f = text_leaf(out, "MndtId", t.mandate_id, 35, true, 6, opts, lim);
    if f.kind != F_NONE { return f; }
    f = date_leaf(out, "DtOfSgntr", t.signature_year, t.signature_month, t.signature_day, 6, opts);
    if f.kind != F_NONE { return f; }
    if t.has_amendment {
        flag_leaf(out, "AmdmntInd", t.amendment, 6, opts);
    }
    close(out, "MndtRltdInf", 5, opts);
    close(out, "DrctDbtTx", 4, opts);
    f = agent(out, "DbtrAgt", t.debtor_bic, 4, opts, lim);
    if f.kind != F_NONE { return f; }
    f = party(out, "Dbtr", t.debtor_name, 4, opts, lim);
    if f.kind != F_NONE { return f; }
    f = account(out, "DbtrAcct", t.debtor_iban, 4, opts, lim);
    if f.kind != F_NONE { return f; }
    if t.remittance.len > 0 {
        open(out, "RmtInf", 4, opts);
        f = text_leaf(out, "Ustrd", t.remittance, 140, true, 5, opts, lim);
        if f.kind != F_NONE { return f; }
        close(out, "RmtInf", 4, opts);
    }
    close(out, "DrctDbtTxInf", 3, opts);
    return no_fault();
}
