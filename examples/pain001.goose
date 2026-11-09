import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import payment_file from "..";

// Builds one SEPA credit transfer with two payments and prints the
// file. Run with: goose run examples/pain001.goose
fn main() {
    var items: payment_file::CreditTransfer[>..] = [];
    var t1 = payment_file::new_transfer();
    t1.end_to_end_id = "INV-2026-0001";
    t1.instruction_id = "0001";
    let m1, ok1 = finance::money(120000, "EUR");
    if !ok1 { return; }
    t1.amount = m1;
    t1.creditor_name = "Meyer GmbH";
    t1.creditor_iban = "DE89370400440532013000";
    t1.remittance = "Invoice 2026-0001";
    items.push(t1);
    var t2 = payment_file::new_transfer();
    t2.end_to_end_id = "INV-2026-0002";
    let m2, ok2 = finance::money(4500, "EUR");
    if !ok2 { return; }
    t2.amount = m2;
    t2.creditor_name = "Bern and Sons AG";
    t2.creditor_iban = "CH9300762011623852957";
    t2.purpose = "SALA";
    items.push(t2);
    var pays: payment_file::PaymentInfo[>..] = [];
    var p1 = payment_file::new_payment();
    p1.id = "PMTINFO-1";
    p1.has_batch_booking = true;
    p1.batch_booking = false;
    p1.charge_bearer = "SLEV";
    p1.debtor_name = "Customer Corp";
    p1.debtor_iban = "NL91ABNA0417164300";
    p1.execution_year = 2026;
    p1.execution_month = 12;
    p1.execution_day = 1;
    p1.has_execution_date = true;
    p1.item_start = 0;
    p1.item_count = items.len as i32;
    pays.push(p1);
    var h = payment_file::new_header();
    h.message_id = "PAIN-2026-0001";
    h.has_creation = true;
    h.creation_year = 2026;
    h.creation_month = 11;
    h.creation_day = 9;
    h.creation_minutes = 14 * 60 + 30;
    h.creation_offset = 60;
    h.initiator = "Customer Corp";
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: true };
    var lim = payment_file::default_limits();
    var out: u8[>..] = [];
    let f = payment_file::write_pain001(h, pays, items, wopts, lim, out);
    if f.kind != 0 {
        print("fault ", payment_file::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n");
        return;
    }
    print(out);
}
