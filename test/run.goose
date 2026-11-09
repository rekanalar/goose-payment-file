import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import payment_file from "..";

// The file that the writer produces, read back by a caller of another
// program. The fixture holds two items in one payment block.
fn sample(opts: payment_file::PainWriteOptions, out: u8[>..]&) -> i32 {
    var items: payment_file::CreditTransfer[>..] = [];
    var t1 = payment_file::new_transfer();
    t1.end_to_end_id = "E2E-1";
    t1.instruction_id = "INSTR-1";
    let m1, ok1 = finance::money(10050, "EUR");
    if !ok1 { return -1; }
    t1.amount = m1;
    t1.creditor_name = "Creditor One";
    t1.creditor_iban = "DE89370400440532013000";
    t1.remittance = "Invoice 42";
    items.push(t1);
    var t2 = payment_file::new_transfer();
    t2.end_to_end_id = "E2E-2";
    let m2, ok2 = finance::money(250, "EUR");
    if !ok2 { return -1; }
    t2.amount = m2;
    t2.creditor_name = "Creditor Two AG";
    t2.creditor_iban = "CH9300762011623852957";
    t2.purpose = "SALA";
    t2.structured_ref = "RF18539007547034";
    items.push(t2);
    var pays: payment_file::PaymentInfo[>..] = [];
    var p1 = payment_file::new_payment();
    p1.id = "PMT-1";
    p1.has_batch_booking = true;
    p1.batch_booking = false;
    p1.charge_bearer = "SLEV";
    p1.debtor_name = "Acme Trading Ltd";
    p1.debtor_iban = "NL91ABNA0417164300";
    p1.execution_year = 2026; p1.execution_month = 12; p1.execution_day = 1;
    p1.has_execution_date = true;
    p1.item_start = 0;
    p1.item_count = items.len as i32;
    pays.push(p1);
    var h = payment_file::new_header();
    h.message_id = "MSG-2026-0001";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.creation_minutes = 14 * 60 + 30;
    h.creation_offset = 60;
    h.initiator = "Acme Trading Ltd";
    var lim = payment_file::default_limits();
    let f = payment_file::write_pain001(h, pays, items, opts, lim, out);
    return f.kind;
}

// find tells where a pattern sits in a builder. It gives -1 when the
// pattern is absent.
fn find(out: u8[>..]&, pattern: const u8[:]) -> i64 {
    var i: i64 = 0;
    while i + pattern.len <= out.len {
        var j: i64 = 0;
        while j < pattern.len && out[i + j] == pattern[j] { j += 1; }
        if j == pattern.len { return i; }
        i += 1;
    }
    return -1;
}

fn test_round_trip() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    let w = sample(wopts, out);
    if w != 0 { print("FAIL write ", w, "\n"); }
    assert(w == 0);
    assert(find(out, "pain.001.001.03") >= 0);
    assert(find(out, "<CtrlSum>103.00</CtrlSum>") >= 0);
    assert(find(out, "<InstdAmt Ccy=\"EUR\">100.50</InstdAmt>") >= 0);
    assert(find(out, "<NbOfTxs>2</NbOfTxs>") >= 0);
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var h: payment_file::GrpHeader = payment_file::new_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    let text: const u8[:] = out[..];
    var lim = payment_file::default_limits();
    let r = payment_file::parse_pain001(text, lim, ropts, h, pays, items, buf);
    if r.kind != 0 { print("FAIL read ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == 0);
    assert(h.message_id == "MSG-2026-0001");
    assert(h.has_creation && h.creation_year == 2026 && h.creation_minutes == 14 * 60 + 30 && h.creation_offset == 60);
    assert(h.count == 2 && h.has_control_sum && h.control_sum == 10300);
    assert(h.initiator == "Acme Trading Ltd");
    assert(pays.len == 1 && items.len == 2);
    assert(pays[0].id == "PMT-1" && pays[0].debtor_iban == "NL91ABNA0417164300");
    assert(pays[0].has_batch_booking && !pays[0].batch_booking);
    assert(pays[0].charge_bearer == "SLEV");
    assert(pays[0].has_execution_date && pays[0].execution_day == 1);
    assert(pays[0].item_start == 0 && pays[0].item_count == 2);
    assert(items[0].end_to_end_id == "E2E-1" && items[0].instruction_id == "INSTR-1");
    assert(items[0].amount.minor == 10050 && items[0].amount.code == "EUR");
    assert(items[0].creditor_name == "Creditor One" && items[0].creditor_iban == "DE89370400440532013000");
    assert(items[0].remittance == "Invoice 42");
    assert(items[1].end_to_end_id == "E2E-2" && items[1].amount.minor == 250);
    assert(items[1].creditor_iban == "CH9300762011623852957");
    assert(items[1].purpose == "SALA" && items[1].structured_ref == "RF18539007547034");
}

fn test_newer_schema() {
    var lim = payment_file::default_limits();
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var h: payment_file::GrpHeader = payment_file::new_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    let doc = """
<?xml version="1.0" encoding="UTF-8"?>
<p:Document xmlns:p="urn:iso:std:iso:20022:tech:xsd:pain.001.001.08">
<CstmrCdtTrfInitn><GrpHdr><MsgId>MSG-8</MsgId><CreDtTm>2026-02-03T08:00:00+02:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>10.00</CtrlSum><InitgPty><Nm>Initiator SA</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P-8</PmtInfId><PmtMtd>TRF</PmtMtd><Dbtr><Nm>Debtor SA</Nm></Dbtr>
<DbtrAcct><Id><IBAN>ES9121000418450200051332</IBAN></Id></DbtrAcct>
<CdtTrfTxInf><PmtId><EndToEndId>E-8</EndToEndId></PmtId>
<Amt><InstdAmt Ccy="EUR">10.00</InstdAmt></Amt>
<Cdtr><Nm>Creditor BV</Nm></Cdtr><CdtrAcct><Id><IBAN>BE68539007547034</IBAN></Id></CdtrAcct>
</CdtTrfTxInf></PmtInf></CstmrCdtTrfInitn></p:Document>
""";
    let r = payment_file::parse_pain001(doc, lim, ropts, h, pays, items, buf);
    if r.kind != 0 { print("FAIL read8 ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == 0);
    assert(h.message_id == "MSG-8" && h.initiator == "Initiator SA");
    assert(pays.len == 1 && items.len == 1);
    assert(items[0].end_to_end_id == "E-8" && items[0].amount.minor == 1000);
    assert(h.control_sum == 1000);
}

fn test_faults() {
    var lim = payment_file::default_limits();
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var h: payment_file::GrpHeader = payment_file::new_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    // A wrong control sum faults, and the switch lets it through.
    let bad_sum = """
<?xml version="1.0"?><Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.03">
<CstmrCdtTrfInitn><GrpHdr><MsgId>M1</MsgId><CtrlSum>99.00</CtrlSum><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P1</PmtInfId><Dbtr><Nm>Debtor</Nm></Dbtr>
<CdtTrfTxInf><PmtId><EndToEndId>E1</EndToEndId></PmtId><Amt><InstdAmt Ccy="EUR">1.00</InstdAmt></Amt>
<Cdtr><Nm>Cred</Nm></Cdtr><CdtrAcct><Id><IBAN>BE68539007547034</IBAN></Id></CdtrAcct></CdtTrfTxInf>
</PmtInf></CstmrCdtTrfInitn></Document>
""";
    let r1 = payment_file::parse_pain001(bad_sum, lim, ropts, h, pays, items, buf);
    assert(r1.kind == payment_file::F_TOTAL && r1.have == 100 && r1.want == 9900);
    var sropts = payment_file::PainOptions { skip_control_sum_check: true, check_iban: true, epc_charset: true };
    var h2: payment_file::GrpHeader = payment_file::new_header();
    var pays2: payment_file::PaymentInfo[>..] = [];
    var items2: payment_file::CreditTransfer[>..] = [];
    var buf2: u8[>..] = [];
    assert(payment_file::parse_pain001(bad_sum, lim, sropts, h2, pays2, items2, buf2).kind == 0);
    // A bad IBAN faults, and the switch turns it off.
    let bad_iban = """
<?xml version="1.0"?><Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.03">
<CstmrCdtTrfInitn><GrpHdr><MsgId>M1</MsgId><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P1</PmtInfId><Dbtr><Nm>Debtor</Nm></Dbtr>
<CdtTrfTxInf><PmtId><EndToEndId>E1</EndToEndId></PmtId><Amt><InstdAmt Ccy="EUR">1.00</InstdAmt></Amt>
<Cdtr><Nm>Cred</Nm></Cdtr><CdtrAcct><Id><IBAN>DE89370400440532013001</IBAN></Id></CdtrAcct></CdtTrfTxInf>
</PmtInf></CstmrCdtTrfInitn></Document>
""";
    var h3: payment_file::GrpHeader = payment_file::new_header();
    var pays3: payment_file::PaymentInfo[>..] = [];
    var items3: payment_file::CreditTransfer[>..] = [];
    var buf3: u8[>..] = [];
    let r3 = payment_file::parse_pain001(bad_iban, lim, sropts, h3, pays3, items3, buf3);
    assert(r3.kind == payment_file::F_IBAN);
    var nropts = payment_file::PainOptions { skip_control_sum_check: true, check_iban: false, epc_charset: true };
    var h4: payment_file::GrpHeader = payment_file::new_header();
    var pays4: payment_file::PaymentInfo[>..] = [];
    var items4: payment_file::CreditTransfer[>..] = [];
    var buf4: u8[>..] = [];
    assert(payment_file::parse_pain001(bad_iban, lim, nropts, h4, pays4, items4, buf4).kind == 0);
    // A text outside the EPC set faults, and the switch turns it off.
    let hostile = """
<?xml version="1.0"?><Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.03">
<CstmrCdtTrfInitn><GrpHdr><MsgId>M1</MsgId><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P1</PmtInfId><Dbtr><Nm>Deb*tor</Nm></Dbtr>
<CdtTrfTxInf><PmtId><EndToEndId>E1</EndToEndId></PmtId><Amt><InstdAmt Ccy="EUR">1.00</InstdAmt></Amt>
<Cdtr><Nm>Cred</Nm></Cdtr><CdtrAcct><Id><IBAN>BE68539007547034</IBAN></Id></CdtrAcct></CdtTrfTxInf>
</PmtInf></CstmrCdtTrfInitn></Document>
""";
    var h5: payment_file::GrpHeader = payment_file::new_header();
    var pays5: payment_file::PaymentInfo[>..] = [];
    var items5: payment_file::CreditTransfer[>..] = [];
    var buf5: u8[>..] = [];
    let r5 = payment_file::parse_pain001(hostile, lim, nropts, h5, pays5, items5, buf5);
    assert(r5.kind == payment_file::F_CHARSET);
}

fn test_escape() {
    // A remittance with markup cannot break out of the element.
    var wopts = payment_file::PainWriteOptions { epc_charset: false, indent: false };
    var items: payment_file::CreditTransfer[>..] = [];
    var t = payment_file::new_transfer();
    t.end_to_end_id = "E1";
    let m, ok = finance::money(100, "EUR");
    if !ok { return; }
    t.amount = m;
    t.creditor_name = "Cred";
    t.creditor_iban = "BE68539007547034";
    t.remittance = "a<b>&c>d";
    items.push(t);
    var pays: payment_file::PaymentInfo[>..] = [];
    var p = payment_file::new_payment();
    p.id = "P1";
    p.debtor_name = "Debtor & Sons";
    p.debtor_iban = "ES9121000418450200051332";
    p.execution_year = 2026; p.execution_month = 12; p.execution_day = 1;
    p.has_execution_date = true;
    p.item_start = 0;
    p.item_count = items.len as i32;
    pays.push(p);
    var h = payment_file::new_header();
    h.message_id = "M1";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.initiator = "Init <Tag>";
    var out: u8[>..] = [];
    var lim = payment_file::default_limits();
    let w = payment_file::write_pain001(h, pays, items, wopts, lim, out);
    assert(w.kind == 0);
    assert(find(out, "a&lt;b&gt;&amp;c&gt;d") >= 0);
    assert(find(out, "Debtor &amp; Sons") >= 0);
    assert(find(out, "Init &lt;Tag&gt;") >= 0);
    assert(find(out, "<b>") < 0);
    // A control byte in a name faults.
    items[0].creditor_name = "bad\x01name";
    var out2: u8[>..] = [];
    let w2 = payment_file::write_pain001(h, pays, items, wopts, lim, out2);
    assert(w2.kind == payment_file::F_CHARSET);
}

// replace_all copies src into dst and swaps every pattern for the text.
fn replace_all(src: u8[>..]&, pattern: const u8[:], text: const u8[:], dst: u8[>..]&) {
    var i: i64 = 0;
    while i < src.len {
        var j: i64 = 0;
        while j < pattern.len && i + j < src.len && src[i + j] == pattern[j] { j += 1; }
        if j == pattern.len {
            var k: i64 = 0;
            while k < text.len { dst.push(text[k]); k += 1; }
            i += pattern.len;
        } else {
            dst.push(src[i]);
            i += 1;
        }
    }
}

// read_fault reads a document and gives the fault of the reader.
fn read_fault(doc: const u8[:], skip: bool, lim: payment_file::Limits&) -> i32 {
    var ropts = payment_file::PainOptions { skip_control_sum_check: skip, check_iban: true, epc_charset: true };
    var h = payment_file::new_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    let f = payment_file::parse_pain001(doc, lim, ropts, h, pays, items, buf);
    return f.kind;
}

fn test_schema_order() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample(wopts, out) == 0);
    // The schema is a sequence, so the order of the children is part of validity.
    var at: i64 = -1;
    let tags = ["<PmtInfId>", "<PmtMtd>", "<BtchBookg>", "<NbOfTxs>", "<CtrlSum>", "<ReqdExctnDt>",
                "<Dbtr>", "<DbtrAcct>", "<DbtrAgt>", "<ChrgBr>", "<CdtTrfTxInf>"];
    var base = find(out, "<PmtInf>");
    var i: i64 = 0;
    while i < tags.len {
        var j: i64 = 0;
        // Search after the block start.
        var pos: i64 = -1;
        var k = base;
        while k + tags[i].len <= out.len && pos < 0 {
            var m: i64 = 0;
            while m < tags[i].len && out[k + m] == tags[i][m] { m += 1; }
            if m == tags[i].len { pos = k; }
            k += 1;
        }
        assert(pos > at);
        at = pos;
        i += 1;
    }
    assert(find(out, "<Ustrd>") < find(out, "<Strd>") || find(out, "<Ustrd>") < 0 || find(out, "<Strd>") < 0);
    assert(find(out, "<PmtMtd>TRF</PmtMtd>") >= 0);
    assert(find(out, "<DbtrAgt><FinInstnId></FinInstnId></DbtrAgt>") >= 0);
}

fn test_bic_both_names() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample(wopts, out) == 0);
    var withbic: u8[>..] = [];
    replace_all(out, "<DbtrAgt><FinInstnId></FinInstnId></DbtrAgt>", "<DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>", withbic);
    var lim = payment_file::default_limits();
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var h = payment_file::new_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    let r = payment_file::parse_pain001(withbic, lim, ropts, h, pays, items, buf);
    assert(r.kind == payment_file::F_NONE);
    assert(pays[0].debtor_bic == "ABNANL2A");
    assert(pays[0].method == "TRF");
}

fn test_sums_as_numbers() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample(wopts, out) == 0);
    var lim = payment_file::default_limits();
    var more: u8[>..] = [];
    replace_all(out, "<CtrlSum>103.00</CtrlSum>", "<CtrlSum>103.0000</CtrlSum>", more);
    assert(read_fault(more, false, lim) == payment_file::F_NONE);
    var neg: u8[>..] = [];
    replace_all(out, "<CtrlSum>103.00</CtrlSum>", "<CtrlSum>-103.00</CtrlSum>", neg);
    assert(read_fault(neg, false, lim) == payment_file::F_AMOUNT);
    var bad: u8[>..] = [];
    replace_all(out, "<CtrlSum>103.00</CtrlSum>", "<CtrlSum>104.00</CtrlSum>", bad);
    assert(read_fault(bad, false, lim) == payment_file::F_TOTAL);
    assert(read_fault(bad, true, lim) == payment_file::F_NONE);
    var cnt: u8[>..] = [];
    replace_all(out, "<NbOfTxs>2</NbOfTxs>", "<NbOfTxs>3</NbOfTxs>", cnt);
    assert(read_fault(cnt, false, lim) == payment_file::F_TOTAL);
}

fn test_limits_and_names() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample(wopts, out) == 0);
    var lim = payment_file::default_limits();
    lim.max_nesting = 3;
    assert(read_fault(out, false, lim) == payment_file::F_LIMIT);
    lim = payment_file::default_limits();
    // The reader takes a name of 100 bytes: the schema allows 140.
    var long: u8[>..] = [];
    var n: i64 = 0;
    while n < 100 { long.push('a'); n += 1; }
    var wide: u8[>..] = [];
    replace_all(out, "Creditor One", long, wide);
    assert(read_fault(wide, false, lim) == payment_file::F_NONE);
    // The writer holds to the limit of the EPC rulebook, 70.
    var items: payment_file::CreditTransfer[>..] = [];
    var t = payment_file::new_transfer();
    t.end_to_end_id = "E1";
    let m, ok = finance::money(100, "EUR");
    assert(ok);
    t.amount = m;
    t.creditor_name = long;
    t.creditor_iban = "BE68539007547034";
    items.push(t);
    var pays: payment_file::PaymentInfo[>..] = [];
    var p = payment_file::new_payment();
    p.id = "P1"; p.debtor_name = "D"; p.debtor_iban = "ES9121000418450200051332";
    p.execution_year = 2026; p.execution_month = 12; p.execution_day = 1;
    p.has_execution_date = true;
    p.item_count = 1;
    pays.push(p);
    var h = payment_file::new_header();
    h.message_id = "M1"; h.initiator = "I";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    var o2: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o2).kind == payment_file::F_LIMIT);
    // A negative amount and a missing creation time fault.
    items[0].creditor_name = "Cred";
    items[0].amount.minor = -5;
    var o3: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o3).kind == payment_file::F_AMOUNT);
    items[0].amount.minor = 5;
    h.has_creation = false;
    var o4: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o4).kind == payment_file::F_DATE);
}

fn main() {
    test_round_trip();
    test_newer_schema();
    test_faults();
    test_escape();
    test_schema_order();
    test_bic_both_names();
    test_sums_as_numbers();
    test_limits_and_names();
    print("ok");
}
