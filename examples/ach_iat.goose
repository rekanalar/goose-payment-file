import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import payment_file from "..";

// Builds one NACHA file with one IAT batch and prints it.
// The batch holds one entry of 123.45 US dollars.
// The entry carries the seven mandatory addenda records.
// Run with: goose run examples/ach_iat.goose
fn main() {
    var addenda: payment_file::IatAddenda[>..] = [];
    var a10 = payment_file::new_iat_addenda(10);
    a10.txn_type_code = "BUS";
    a10.foreign_amount = 11000;
    a10.foreign_trace = "FX123";
    a10.name = "Hans Mueller";
    addenda.push(a10);
    var a11 = payment_file::new_iat_addenda(11);
    a11.name = "Acme Corp";
    a11.street = "1 Main St";
    addenda.push(a11);
    var a12 = payment_file::new_iat_addenda(12);
    a12.city_state = "New York*NY\\";
    a12.country_postal = "US*10001\\";
    addenda.push(a12);
    var a13 = payment_file::new_iat_addenda(13);
    a13.name = "Acme Bank";
    a13.id_qualifier = "01";
    a13.id_number = "121140399";
    a13.branch_country = "US";
    addenda.push(a13);
    var a14 = payment_file::new_iat_addenda(14);
    a14.name = "Deutsche Bank";
    a14.id_qualifier = "02";
    a14.id_number = "DEUTDEFF";
    a14.branch_country = "DE";
    addenda.push(a14);
    var a15 = payment_file::new_iat_addenda(15);
    a15.receiver_id = "R-123";
    a15.street = "Hauptstr 5";
    addenda.push(a15);
    var a16 = payment_file::new_iat_addenda(16);
    a16.city_state = "Berlin*BE\\";
    a16.country_postal = "DE*10115\\";
    a16.date_of_birth = "1980-01-02";
    addenda.push(a16);
    var entries: payment_file::IatEntry[>..] = [];
    var e = payment_file::new_iat_entry();
    e.transaction_code = 22;
    e.rdfi_routing = "021000021";
    e.amount = 12345;
    e.dfi_account = "DE89370400440532013000";
    e.addenda_start = 0;
    e.addenda_count = addenda.len as i32;
    entries.push(e);
    var batches: payment_file::IatBatch[>..] = [];
    var b = payment_file::new_iat_batch();
    b.service_class = 220;
    b.fx_indicator = "FF";
    b.fx_ref_indicator = 3;
    b.dest_country = "DE";
    b.originator_id = "1234567890";
    b.description = "PAYMENT";
    b.origin_currency = "USD";
    b.dest_currency = "EUR";
    b.effective_year = 2026; b.effective_month = 11; b.effective_day = 10;
    b.odfi_id = "12114039";
    b.batch_number = 1;
    b.entry_start = 0;
    b.entry_count = 1;
    batches.push(b);
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
    let f = payment_file::write_ach_iat(h, batches, entries, addenda, lim, out);
    if f.kind != 0 {
        print("fault ", payment_file::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n");
        return;
    }
    print(out);
    // Read the file back and print the counts.
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var ib: payment_file::IatBatch[>..] = [];
    var ie: payment_file::IatEntry[>..] = [];
    var ia: payment_file::IatAddenda[>..] = [];
    var opts = payment_file::new_ach_options();
    var h2 = payment_file::new_ach_file_header();
    let rf = payment_file::parse_ach_iat(out, opts, lim, h2, bs, es, ads, ib, ie, ia);
    if rf.kind != 0 {
        print("fault ", payment_file::kind_name(rf.kind), " ", rf.tag, " ", rf.detail, "\n");
        return;
    }
    print("iat batches: ", ib.len as i64, "\n");
    print("iat entries: ", ie.len as i64, "\n");
    print("iat addenda: ", ia.len as i64, "\n");
    print("amount: ", ie[0].amount, "\n");
    print("destination country: ", ib[0].dest_country, "\n");
}
