import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import payment_file from "..";

// Builds one SEPA direct debit that carries the postal addresses, the
// other identifiers, the ultimate parties, the purpose and the typed
// creditor reference. It reads the file back and prints the fields.
// Run with:
// goose run examples/pain008_parties.goose
fn main() {
    var items: payment_file::DirectDebit[>..] = [];
    var t = payment_file::new_direct_debit();
    t.end_to_end_id = "RENT-2026-06";
    let m, ok = finance::money(95000, "EUR");
    if !ok { return; }
    t.amount = m;
    t.mandate_id = "MANDAT-2024-017";
    t.signature_year = 2024; t.signature_month = 3; t.signature_day = 1;
    t.has_signature_date = true;
    t.debtor_name = "Braun Mieter GmbH";
    t.debtor_iban = "DE89370400440532013000";
    var daddr = payment_file::new_address();
    daddr.street_name = "Koenigsallee";
    daddr.building_number = "45";
    daddr.post_code = "40212";
    daddr.town_name = "Duesseldorf";
    daddr.country = "DE";
    t.debtor_detail.address = daddr;
    var dother = payment_file::new_other_id();
    dother.id = "HRB 654321";
    dother.issuer = "Registergericht";
    var dpid = payment_file::new_party_id();
    dpid.kind = payment_file::PARTY_PERSON;
    dpid.other = dother;
    t.debtor_detail.id = dpid;
    t.ultimate_creditor_name = "Braun Wohnen SE";
    var upid = payment_file::new_party_id();
    upid.kind = payment_file::PARTY_ORG;
    upid.bic = "ABNANL2A";
    t.ultimate_creditor_detail.id = upid;
    t.ultimate_debtor_name = "Braun Wohnung 4";
    t.purpose = "GDDS";
    t.remittance = "Rent June 2026";
    t.structured_type = "SCOR";
    t.structured_issuer = "Braun Wohnen SE";
    t.structured_ref = "RF45390007547034";
    items.push(t);
    var blocks: payment_file::DebitInfo[>..] = [];
    var b = payment_file::new_debit_info();
    b.id = "DD-RENT-1";
    b.creditor_name = "Grundstuecksverwaltung Meyer";
    b.creditor_iban = "NL91ABNA0417164300";
    b.creditor_bic = "ABNANL2A";
    var caddr = payment_file::new_address();
    caddr.street_name = "Dam";
    caddr.building_number = "1";
    caddr.post_code = "1012";
    caddr.town_name = "Amsterdam";
    caddr.country = "NL";
    b.creditor_detail.address = caddr;
    var cother = payment_file::new_other_id();
    cother.id = "KVKNL-8899";
    cother.issuer = "KVK";
    var cpid = payment_file::new_party_id();
    cpid.kind = payment_file::PARTY_ORG;
    cpid.other = cother;
    b.creditor_detail.id = cpid;
    b.ultimate_creditor_name = "Meyer Holding SE";
    b.scheme_id = "DE98ZZZ09999999999";
    b.charge_bearer = "SLEV";
    b.seq_type = "RCUR";
    b.instrument = "CORE";
    b.collection_year = 2026; b.collection_month = 6; b.collection_day = 1;
    b.has_collection_date = true;
    b.item_start = 0;
    b.item_count = items.len as i32;
    blocks.push(b);
    var h = payment_file::new_header();
    h.message_id = "DD-RENT-2026-06";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 6; h.creation_day = 1;
    h.creation_minutes = 8 * 60;
    h.initiator = "Grundstuecksverwaltung Meyer";
    var opts = payment_file::PainWriteOptions { epc_charset: true, indent: true };
    var lim = payment_file::default_limits();
    var out: u8[>..] = [];
    let f = payment_file::write_pain008(h, blocks, items, opts, lim, out);
    if f.kind != payment_file::F_NONE {
        print("write failed: ", payment_file::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n");
        return;
    }
    print(out);
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var h2 = payment_file::new_header();
    var blocks2: payment_file::DebitInfo[>..] = [];
    var items2: payment_file::DirectDebit[>..] = [];
    var buf: u8[>..] = [];
    let r = payment_file::parse_pain008(out, lim, ropts, h2, blocks2, items2, buf);
    if r.kind != payment_file::F_NONE {
        print("read failed: ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n");
        return;
    }
    print("creditor town: ", blocks2[0].creditor_detail.address.town_name, "\n");
    print("creditor id: ", blocks2[0].creditor_detail.id.other.id, "\n");
    print("block ultimate creditor: ", blocks2[0].ultimate_creditor_name, "\n");
    print("debtor id: ", items2[0].debtor_detail.id.other.id, "\n");
    print("item ultimate creditor: ", items2[0].ultimate_creditor_name, "\n");
    print("item ultimate debtor: ", items2[0].ultimate_debtor_name, "\n");
    print("purpose: ", items2[0].purpose, "\n");
    print("reference type: ", items2[0].structured_type, " ref: ", items2[0].structured_ref, "\n");
}
