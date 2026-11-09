import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import payment_file from "..";

// Builds small NACHA batches of the newer SEC codes and prints the
// counts of the file it reads back.
// Run with: goose run examples/ach_sec_codes.goose
fn build_one(sec: const u8[:], tc: i64, amount: i64, svc: i64) -> i32 {
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var e = payment_file::new_ach_entry();
    e.transaction_code = tc;
    e.rdfi_routing = "121140399";
    e.account = "00012345678";
    e.amount = amount;
    e.individual_name = "Receiver";
    e.individual_id = "12280000000001";
    e.discretionary = "21";
    e.trace_number = "121140390000001";
    if sec == "ATX" || sec == "TRX" || sec == "COR" || sec == "DNE" || sec == "ENR" {
        e.individual_name = "0001Receiver";
        e.addenda_start = 0;
        e.addenda_count = 1;
        var ad = payment_file::new_ach_addenda();
        if sec == "COR" {
            ad.kind = 98;
            ad.change_code = "C01";
            ad.original_trace = "121140390000001";
            ad.original_dfi = "12114039";
            ad.corrected_data = "A";
        } else {
            ad.text = "Payment data";
        }
        addenda.push(ad);
    }
    if sec == "SHR" || sec == "MTE" {
        e.addenda_start = 0;
        e.addenda_count = 1;
        var t = payment_file::new_ach_addenda();
        t.kind = 2;
        t.ref_one = "REF";
        t.ref_two = "AB";
        t.terminal_id = "TERM01";
        t.serial = "000001";
        t.date_month = 11;
        t.date_day = 9;
        t.auth_code = "AUTH01";
        t.location = "1 Main St";
        t.city = "New York";
        t.state = "NY";
        addenda.push(t);
    }
    entries.push(e);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = svc;
    b.company_name = "Acme Corp";
    b.company_id = "1234567890";
    b.sec_code = sec;
    b.description = "PAY";
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
    var lim = payment_file::default_limits();
    var out: u8[>..] = [];
    let f = payment_file::write_ach(h, batches, entries, addenda, lim, out);
    if f.kind != 0 {
        print(sec, " fault ", payment_file::kind_name(f.kind), " ", f.detail, "\n");
        return 1;
    }
    var h2 = payment_file::new_ach_file_header();
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var opts = payment_file::new_ach_options();
    let r = payment_file::parse_ach(out, opts, lim, h2, bs, es, ads);
    if r.kind != 0 {
        print(sec, " read fault ", payment_file::kind_name(r.kind), " ", r.detail, "\n");
        return 1;
    }
    print(sec, ": entries ", es.len as i64, " addenda ", ads.len as i64, "\n");
    return 0;
}

fn main() {
    var bad: i32 = 0;
    bad += build_one("ACK", 23, 0, 220);
    bad += build_one("ATX", 23, 0, 220);
    bad += build_one("CIE", 22, 100, 220);
    bad += build_one("COR", 21, 0, 220);
    bad += build_one("DNE", 23, 0, 220);
    bad += build_one("ENR", 23, 0, 220);
    bad += build_one("SHR", 22, 100, 220);
    bad += build_one("TRC", 27, 100, 225);
    bad += build_one("TRX", 27, 100, 225);
    bad += build_one("XCK", 27, 100, 225);
    bad += build_one("MTE", 27, 100, 225);
    if bad != 0 { return; }
    print("all eleven wrote and read clean\n");
}
