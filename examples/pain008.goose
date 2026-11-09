import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import payment_file from "..";

// Builds one SEPA direct debit with two collections and prints the
// file. Run with: goose run examples/pain008.goose
fn main() {
    var items: payment_file::DirectDebit[>..] = [];
    var t1 = payment_file::new_direct_debit();
    t1.end_to_end_id = "MEMBER-2026-001";
    let m1, ok1 = finance::money(3000, "EUR");
    if !ok1 { return; }
    t1.amount = m1;
    t1.mandate_id = "MANDATE-001";
    t1.signature_year = 2025; t1.signature_month = 3; t1.signature_day = 14;
    t1.has_signature_date = true;
    t1.debtor_name = "Anna Meyer";
    t1.debtor_iban = "DE89370400440532013000";
    t1.remittance = "Membership fee 2026";
    items.push(t1);
    var t2 = payment_file::new_direct_debit();
    t2.end_to_end_id = "MEMBER-2026-002";
    let m2, ok2 = finance::money(3000, "EUR");
    if !ok2 { return; }
    t2.amount = m2;
    t2.mandate_id = "MANDATE-002";
    t2.signature_year = 2024; t2.signature_month = 11; t2.signature_day = 2;
    t2.has_signature_date = true;
    t2.debtor_name = "Jan de Vries";
    t2.debtor_iban = "NL91ABNA0417164300";
    t2.remittance = "Membership fee 2026";
    items.push(t2);
    var blocks: payment_file::DebitInfo[>..] = [];
    var b = payment_file::new_debit_info();
    b.id = "FEES-2026";
    b.creditor_name = "Chess Club Berlin";
    b.creditor_iban = "DE02120300000000202051";
    b.scheme_id = "DE98ZZZ09999999999";
    b.charge_bearer = "SLEV";
    b.seq_type = "RCUR";
    b.instrument = "CORE";
    b.collection_year = 2026; b.collection_month = 12; b.collection_day = 1;
    b.has_collection_date = true;
    b.item_count = items.len as i32;
    blocks.push(b);
    var h = payment_file::new_header();
    h.message_id = "FEES-MSG-2026";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.creation_minutes = 9 * 60;
    h.initiator = "Chess Club Berlin";
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: true };
    var lim = payment_file::default_limits();
    var out: u8[>..] = [];
    let f = payment_file::write_pain008(h, blocks, items, wopts, lim, out);
    if f.kind != 0 {
        print("fault ", payment_file::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n");
        return;
    }
    print(out);
}
