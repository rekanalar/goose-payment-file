import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import payment_file from "..";

// Builds one NACHA file with one batch of PPD credits and prints it.
// Run with: goose run examples/ach.goose
fn main() {
    var entries: payment_file::AchEntry[>..] = [];
    var e1 = payment_file::new_ach_entry();
    e1.transaction_code = 22;
    e1.rdfi_routing = "121140399";
    e1.account = "00012345678";
    e1.amount = 100000;
    e1.individual_name = "Alice Doe";
    e1.trace_number = "121140390000001";
    entries.push(e1);
    var e2 = payment_file::new_ach_entry();
    e2.transaction_code = 22;
    e2.rdfi_routing = "021000021";
    e2.account = "9876543";
    e2.amount = 25000;
    e2.individual_name = "Bob Roe";
    e2.trace_number = "121140390000002";
    entries.push(e2);
    var batches: payment_file::AchBatch[>..] = [];
    var b1 = payment_file::new_ach_batch();
    b1.service_class = 220;
    b1.company_name = "Acme Corp";
    b1.company_id = "1234567890";
    b1.sec_code = "PPD";
    b1.description = "PAYROLL";
    b1.effective_year = 2026; b1.effective_month = 11; b1.effective_day = 10;
    b1.odfi_id = "12114039";
    b1.batch_number = 1;
    b1.entry_start = 0;
    b1.entry_count = entries.len as i32;
    batches.push(b1);
    var h = payment_file::new_ach_file_header();
    h.destination_routing = "121140399";
    h.origin_id = "1234567890";
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.creation_hour = 14; h.creation_minute = 30;
    h.id_modifier = "A";
    h.destination_name = "Acme Bank";
    h.origin_name = "Acme Corp";
    h.reference = "REF00001";
    var lim = payment_file::default_limits();
    var out: u8[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    let f = payment_file::write_ach(h, batches, entries, addenda, lim, out);
    if f.kind != 0 {
        print("fault ", payment_file::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n");
        return;
    }
    print(out);
}
