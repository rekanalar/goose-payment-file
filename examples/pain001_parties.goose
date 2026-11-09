import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import payment_file from "..";

// Builds one SEPA credit transfer that carries the postal addresses,
// the other identifiers and the ultimate parties. It reads the file
// back and prints the fields. Run with:
// goose run examples/pain001_parties.goose
fn main() {
    var items: payment_file::CreditTransfer[>..] = [];
    var t1 = payment_file::new_transfer();
    t1.end_to_end_id = "INV-2026-0001";
    let m1, ok1 = finance::money(120000, "EUR");
    if !ok1 { return; }
    t1.amount = m1;
    t1.creditor_name = "Meyer GmbH";
    t1.creditor_iban = "DE89370400440532013000";
    t1.remittance = "Invoice 2026-0001";
    t1.structured_type = "SCOR";
    t1.structured_issuer = "Customer Corp";
    t1.structured_ref = "RF18539007547034";
    var addr = payment_file::new_address();
    addr.street_name = "Hauptstrasse";
    addr.building_number = "12";
    addr.post_code = "80331";
    addr.town_name = "Muenchen";
    addr.country = "DE";
    t1.creditor_detail.address = addr;
    var other = payment_file::new_other_id();
    other.id = "HRB 123456";
    other.scheme_code = "BANK";
    other.issuer = "Customer Corp";
    var pid = payment_file::new_party_id();
    pid.kind = payment_file::PARTY_ORG;
    pid.other = other;
    t1.creditor_detail.id = pid;
    t1.ultimate_creditor_name = "Meyer Holding SE";
    t1.ultimate_creditor_detail.address = addr;
    items.push(t1);
    var pays: payment_file::PaymentInfo[>..] = [];
    var p1 = payment_file::new_payment();
    p1.id = "PMTINFO-1";
    p1.charge_bearer = "SLEV";
    p1.debtor_name = "Customer Corp";
    p1.debtor_iban = "NL91ABNA0417164300";
    p1.execution_year = 2026;
    p1.execution_month = 12;
    p1.execution_day = 1;
    p1.has_execution_date = true;
    p1.item_start = 0;
    p1.item_count = items.len as i32;
    var daddr = payment_file::new_address();
    daddr.department = "Finance";
    daddr.street_name = "Dorpsstraat";
    daddr.post_code = "1234 AB";
    daddr.town_name = "Amsterdam";
    daddr.country = "NL";
    daddr.line_1 = "Building A";
    p1.debtor_detail.address = daddr;
    p1.ultimate_debtor_name = "Customer Holding BV";
    p1.ultimate_debtor_detail.address = daddr;
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
    // Read the file back and print the new fields.
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var rh = payment_file::new_header();
    var rp: payment_file::PaymentInfo[>..] = [];
    var ri: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    let text: const u8[:] = out[..];
    let rf = payment_file::parse_pain001(text, lim, ropts, rh, rp, ri, buf);
    if rf.kind != 0 {
        print("fault ", payment_file::kind_name(rf.kind), " ", rf.tag, " ", rf.detail, "\n");
        return;
    }
    print("debtor town: ", rp[0].debtor_detail.address.town_name, "\n");
    print("debtor country: ", rp[0].debtor_detail.address.country, "\n");
    print("ultimate debtor: ", rp[0].ultimate_debtor_name, "\n");
    print("creditor town: ", ri[0].creditor_detail.address.town_name, "\n");
    print("creditor id: ", ri[0].creditor_detail.id.other.id, "\n");
    print("ultimate creditor: ", ri[0].ultimate_creditor_name, "\n");
    print("reference type: ", ri[0].structured_type, "\n");
}
