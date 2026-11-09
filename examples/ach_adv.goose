// Write and read a file with one ADV batch of automated accounting
// advice. The batch holds a credit and a debit advice entry.
import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import payment_file from "..";

fn main() {
    var entries: payment_file::AdvEntry[>..] = [];
    var e = payment_file::new_adv_entry();
    e.transaction_code = 81;
    e.rdfi_routing = "121140399";
    e.account = "00012345678";
    e.amount = 123456;
    e.advice_routing_number = "021000021";
    e.file_identification = "FILE1";
    e.individual_name = "Receiver";
    e.ach_operator_routing_number = "12114039";
    e.julian_day = 313;
    e.sequence_number = 1;
    entries.push(e);
    e.transaction_code = 84;
    e.amount = 5000;
    e.sequence_number = 2;
    entries.push(e);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = 280;
    b.company_name = "Acme Corp";
    b.company_id = "1234567890";
    b.sec_code = "ADV";
    b.description = "ADVICE";
    b.effective_year = 2026; b.effective_month = 11; b.effective_day = 10;
    b.originator_status = 0;
    b.odfi_id = "12114039";
    b.batch_number = 1;
    b.entry_count = 2;
    batches.push(b);
    var h = payment_file::new_ach_file_header();
    h.destination_routing = "121140399";
    h.origin_id = "1234567890";
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.creation_hour = 14; h.creation_minute = 30;
    h.id_modifier = "A";
    h.destination_name = "Bank";
    h.origin_name = "Corp";
    var lim = payment_file::default_limits();
    var out: u8[>..] = [];
    let w = payment_file::write_ach_adv(h, batches, entries, lim, out);
    if w.kind != 0 {
        print("write fault ", payment_file::kind_name(w.kind), " ", w.detail, "\n");
        return;
    }
    var h2 = payment_file::new_ach_file_header();
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AdvEntry[>..] = [];
    var opts = payment_file::new_ach_options();
    let r = payment_file::parse_ach_adv(out, opts, lim, h2, bs, es);
    if r.kind != 0 {
        print("read fault ", payment_file::kind_name(r.kind), " ", r.detail, "\n");
        return;
    }
    print("advice entries ", es.len as i64, ", first amount ", es[0].amount, "\n");
}
