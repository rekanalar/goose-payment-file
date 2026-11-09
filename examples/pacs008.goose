import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import payment_file from "..";

// Builds one pacs.008 message with two transactions, writes it and
// reads it back. Run with: goose run examples/pacs008.goose
fn main() {
    var txs: payment_file::Pacs008Tx[>..] = [];
    var t1 = payment_file::new_pacs008_tx();
    t1.end_to_end_id = "E2E-1";
    t1.instruction_id = "INSTR-1";
    t1.uetr = "123e4567-e89b-42d3-a456-426614174000";
    let m1, ok1 = finance::money(10050, "EUR");
    if !ok1 { print("the currency table holds not the currency\n"); return; }
    t1.amount = m1;
    t1.has_settlement_date = true;
    t1.settle_year = 2026; t1.settle_month = 12; t1.settle_day = 1;
    t1.charge_bearer = "SLEV";
    t1.debtor_name = "Acme Trading Ltd";
    t1.debtor_country = "NL";
    t1.debtor_iban = "NL91ABNA0417164300";
    t1.debtor_bic = "ABNANL2A";
    t1.creditor_name = "Creditor One";
    t1.creditor_country = "DE";
    t1.creditor_iban = "DE89370400440532013000";
    t1.creditor_bic = "COBADEFFXXX";
    t1.remittance = "Invoice 42";
    txs.push(t1);
    var t2 = payment_file::new_pacs008_tx();
    t2.end_to_end_id = "E2E-2";
    let m2, ok2 = finance::money(250, "EUR");
    if !ok2 { print("the currency table holds not the currency\n"); return; }
    t2.amount = m2;
    t2.has_settlement_date = true;
    t2.settle_year = 2026; t2.settle_month = 12; t2.settle_day = 1;
    t2.charge_bearer = "SLEV";
    t2.debtor_name = "Acme Trading Ltd";
    t2.debtor_iban = "NL91ABNA0417164300";
    t2.debtor_bic = "ABNANL2A";
    t2.creditor_name = "Creditor Two AG";
    t2.creditor_iban = "CH9300762011623852957";
    t2.creditor_bic = "POFICHBEXXX";
    txs.push(t2);
    var h = payment_file::new_pacs008_header();
    h.base.message_id = "MSG-2026-0002";
    h.base.has_creation = true;
    h.base.creation_year = 2026; h.base.creation_month = 11; h.base.creation_day = 9;
    h.base.creation_minutes = 14 * 60 + 30;
    h.base.creation_offset = 60;
    h.settlement_method = "INDA";
    h.has_settlement_date = true;
    h.settle_year = 2026; h.settle_month = 12; h.settle_day = 1;
    h.instructing_bic = "ABNANL2A";
    h.instructed_bic = "COBADEFFXXX";
    var lim = payment_file::default_limits();
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var out: u8[>..] = [];
    let f = payment_file::write_pacs008(h, txs, wopts, lim, out);
    if f.kind != 0 {
        print("fault ", payment_file::kind_name(f.kind), " ", f.tag, " ", f.detail, "\n");
        return;
    }
    print(out);
    var rh = payment_file::new_pacs008_header();
    var rtxs: payment_file::Pacs008Tx[>..] = [];
    var buf: u8[>..] = [];
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    let text: const u8[:] = out[..];
    let r = payment_file::parse_pacs008(text, lim, ropts, rh, rtxs, buf);
    if r.kind != 0 {
        print("fault ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n");
        return;
    }
    print("method ", rh.settlement_method, " transactions ", rtxs.len, " total ", rh.base.control_sum, "\n");
}
