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

// sample_debit writes a direct debit with two items in one block.
fn sample_debit(opts: payment_file::PainWriteOptions, out: u8[>..]&) -> i32 {
    var items: payment_file::DirectDebit[>..] = [];
    var t1 = payment_file::new_direct_debit();
    t1.end_to_end_id = "E2E-D1";
    let m1, ok1 = finance::money(1000, "EUR");
    if !ok1 { return -1; }
    t1.amount = m1;
    t1.mandate_id = "MANDATE-1";
    t1.signature_year = 2025; t1.signature_month = 3; t1.signature_day = 14;
    t1.has_signature_date = true;
    t1.debtor_name = "Debtor One";
    t1.debtor_iban = "DE89370400440532013000";
    t1.remittance = "Membership 2026";
    items.push(t1);
    var t2 = payment_file::new_direct_debit();
    t2.end_to_end_id = "E2E-D2";
    let m2, ok2 = finance::money(2550, "EUR");
    if !ok2 { return -1; }
    t2.amount = m2;
    t2.mandate_id = "MANDATE-2";
    t2.signature_year = 2024; t2.signature_month = 11; t2.signature_day = 2;
    t2.has_signature_date = true;
    t2.has_amendment = true;
    t2.amendment = false;
    t2.debtor_name = "Debtor Two";
    t2.debtor_iban = "CH9300762011623852957";
    t2.debtor_bic = "UBSWCHZH80A";
    items.push(t2);
    var blocks: payment_file::DebitInfo[>..] = [];
    var b = payment_file::new_debit_info();
    b.id = "DD-1";
    b.creditor_name = "Club Treasurer";
    b.creditor_iban = "NL91ABNA0417164300";
    b.creditor_bic = "ABNANL2A";
    b.scheme_id = "DE98ZZZ09999999999";
    b.charge_bearer = "SLEV";
    b.seq_type = "RCUR";
    b.instrument = "CORE";
    b.collection_year = 2026; b.collection_month = 12; b.collection_day = 1;
    b.has_collection_date = true;
    b.item_count = items.len as i32;
    blocks.push(b);
    var h = payment_file::new_header();
    h.message_id = "DD-MSG-1";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.creation_minutes = 9 * 60;
    h.initiator = "Club Treasurer";
    var lim = payment_file::default_limits();
    let f = payment_file::write_pain008(h, blocks, items, opts, lim, out);
    return f.kind;
}

// read_debit_kind reads a direct debit and gives the fault kind.
fn read_debit_kind(doc: const u8[:], skip: bool, lim: payment_file::Limits&) -> i32 {
    var ropts = payment_file::PainOptions { skip_control_sum_check: skip, check_iban: true, epc_charset: true };
    var h = payment_file::new_header();
    var blocks: payment_file::DebitInfo[>..] = [];
    var items: payment_file::DirectDebit[>..] = [];
    var buf: u8[>..] = [];
    let f = payment_file::parse_pain008(doc, lim, ropts, h, blocks, items, buf);
    return f.kind;
}

fn test_debit_round_trip() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    let w = sample_debit(wopts, out);
    if w != 0 { print("FAIL write debit ", w, "\n"); }
    assert(w == 0);
    assert(find(out, "pain.008.001.02") >= 0);
    // The schema is a sequence: pin the order of the block and of the item.
    let order = ["<PmtInfId>", "<PmtMtd>DD</PmtMtd>", "<NbOfTxs>", "<CtrlSum>", "<PmtTpInf>", "<ReqdColltnDt>",
                 "<Cdtr>", "<CdtrAcct>", "<CdtrAgt>", "<ChrgBr>", "<CdtrSchmeId>", "<DrctDbtTxInf>",
                 "<PmtId>", "<InstdAmt", "<DrctDbtTx>", "<DbtrAgt>", "<Dbtr>", "<DbtrAcct>", "<RmtInf>"];
    var at: i64 = find(out, "<PmtInf>");
    var i: i64 = 0;
    while i < order.len {
        var pos: i64 = -1;
        var k = at;
        while k + order[i].len <= out.len && pos < 0 {
            var m: i64 = 0;
            while m < order[i].len && out[k + m] == order[i][m] { m += 1; }
            if m == order[i].len { pos = k; }
            k += 1;
        }
        assert(pos >= at);
        at = pos;
        i += 1;
    }
    assert(find(out, "<CtrlSum>35.50</CtrlSum>") >= 0);
    assert(find(out, "<SeqTp>RCUR</SeqTp>") >= 0);
    // The reader gives back what the writer wrote.
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var lim = payment_file::default_limits();
    var h = payment_file::new_header();
    var blocks: payment_file::DebitInfo[>..] = [];
    var items: payment_file::DirectDebit[>..] = [];
    var buf: u8[>..] = [];
    let r = payment_file::parse_pain008(out, lim, ropts, h, blocks, items, buf);
    assert(r.kind == payment_file::F_NONE);
    assert(h.message_id == "DD-MSG-1" && h.count == 2 && h.control_sum == 3550);
    assert(blocks.len == 1 && blocks[0].item_count == 2);
    assert(blocks[0].seq_type == "RCUR" && blocks[0].instrument == "CORE");
    assert(blocks[0].scheme_id == "DE98ZZZ09999999999" && blocks[0].creditor_bic == "ABNANL2A");
    assert(blocks[0].collection_year == 2026 && blocks[0].collection_day == 1);
    assert(items.len == 2);
    assert(items[0].mandate_id == "MANDATE-1" && items[0].amount.minor == 1000);
    assert(items[0].signature_year == 2025 && items[0].signature_month == 3);
    assert(items[1].debtor_bic == "UBSWCHZH80A" && items[1].has_amendment && !items[1].amendment);
    assert(items[0].remittance == "Membership 2026");
}

fn test_debit_newer_schema() {
    // .001.08 names: BICFI, and the scheme id inside the transaction.
    let doc = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.008.001.08"><CstmrDrctDbtInitn>
<GrpHdr><MsgId>M8</MsgId><CreDtTm>2026-11-09T09:00:00</CreDtTm><NbOfTxs>1</NbOfTxs><CtrlSum>10.00</CtrlSum><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P8</PmtInfId><PmtMtd>DD</PmtMtd><PmtTpInf><LclInstrm><Cd>B2B</Cd></LclInstrm><SeqTp>OOFF</SeqTp></PmtTpInf>
<ReqdColltnDt>2026-12-02</ReqdColltnDt><Cdtr><Nm>Cred</Nm></Cdtr><CdtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></CdtrAcct>
<CdtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></CdtrAgt>
<DrctDbtTxInf><PmtId><EndToEndId>E8</EndToEndId></PmtId><InstdAmt Ccy="EUR">10.00</InstdAmt>
<DrctDbtTx><MndtRltdInf><MndtId>MD8</MndtId><DtOfSgntr>2025-01-31</DtOfSgntr></MndtRltdInf>
<CdtrSchmeId><Id><OrgId><Othr><Id>DE98ZZZ09999999999</Id></Othr></OrgId></Id></CdtrSchmeId></DrctDbtTx>
<Dbtr><Nm>Deb</Nm></Dbtr><DbtrAcct><Id><IBAN>DE89370400440532013000</IBAN></Id></DbtrAcct>
</DrctDbtTxInf></PmtInf></CstmrDrctDbtInitn></Document>
""";
    var lim = payment_file::default_limits();
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var h = payment_file::new_header();
    var blocks: payment_file::DebitInfo[>..] = [];
    var items: payment_file::DirectDebit[>..] = [];
    var buf: u8[>..] = [];
    let r = payment_file::parse_pain008(doc, lim, ropts, h, blocks, items, buf);
    if r.kind != 0 { print("FAIL debit .08 ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == payment_file::F_NONE);
    assert(blocks[0].creditor_bic == "ABNANL2A" && blocks[0].instrument == "B2B");
    assert(blocks[0].scheme_id == "DE98ZZZ09999999999");
    assert(items[0].debtor_name == "Deb" && items[0].amount.minor == 1000);
}

fn test_debit_faults() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample_debit(wopts, out) == 0);
    var lim = payment_file::default_limits();
    var a: u8[>..] = [];
    replace_all(out, "<SeqTp>RCUR</SeqTp>", "<SeqTp>XXXX</SeqTp>", a);
    assert(read_debit_kind(a, false, lim) == payment_file::F_SYNTAX);
    var b: u8[>..] = [];
    replace_all(out, "<Cd>CORE</Cd>", "<Cd>FAST</Cd>", b);
    assert(read_debit_kind(b, false, lim) == payment_file::F_SYNTAX);
    var c: u8[>..] = [];
    replace_all(out, "<CtrlSum>35.50</CtrlSum>", "<CtrlSum>35.51</CtrlSum>", c);
    assert(read_debit_kind(c, false, lim) == payment_file::F_TOTAL);
    assert(read_debit_kind(c, true, lim) == payment_file::F_NONE);
    var d: u8[>..] = [];
    replace_all(out, "<CtrlSum>35.50</CtrlSum>", "<CtrlSum>35.5000</CtrlSum>", d);
    assert(read_debit_kind(d, false, lim) == payment_file::F_NONE);
    var e: u8[>..] = [];
    replace_all(out, "<NbOfTxs>2</NbOfTxs>", "<NbOfTxs>5</NbOfTxs>", e);
    assert(read_debit_kind(e, false, lim) == payment_file::F_TOTAL);
    var f: u8[>..] = [];
    replace_all(out, "DE89370400440532013000", "DE89370400440532013001", f);
    assert(read_debit_kind(f, false, lim) == payment_file::F_IBAN);
    var g: u8[>..] = [];
    replace_all(out, "MANDATE-1", "MANDATE*1", g);
    assert(read_debit_kind(g, false, lim) == payment_file::F_CHARSET);
    lim.max_nesting = 3;
    assert(read_debit_kind(out, false, lim) == payment_file::F_LIMIT);
    // The writer refuses what the reader refuses, and what the rulebook needs.
    lim = payment_file::default_limits();
    var items: payment_file::DirectDebit[>..] = [];
    var t = payment_file::new_direct_debit();
    t.end_to_end_id = "E1";
    let m, okm = finance::money(100, "EUR");
    assert(okm);
    t.amount = m;
    t.mandate_id = "M1";
    t.signature_year = 2025; t.signature_month = 2; t.signature_day = 30;
    t.has_signature_date = true;
    t.debtor_name = "D";
    t.debtor_iban = "DE89370400440532013000";
    items.push(t);
    var blocks: payment_file::DebitInfo[>..] = [];
    var bl = payment_file::new_debit_info();
    bl.id = "B1"; bl.creditor_name = "C"; bl.creditor_iban = "NL91ABNA0417164300";
    bl.scheme_id = "DE98ZZZ09999999999"; bl.seq_type = "FRST"; bl.instrument = "CORE";
    bl.collection_year = 2026; bl.collection_month = 12; bl.collection_day = 1;
    bl.has_collection_date = true;
    bl.item_count = 1;
    blocks.push(bl);
    var h = payment_file::new_header();
    h.message_id = "M"; h.initiator = "I"; h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    var o1: u8[>..] = [];
    // 30 February is no date.
    assert(payment_file::write_pain008(h, blocks, items, wopts, lim, o1).kind == payment_file::F_DATE);
    items[0].signature_day = 28;
    blocks[0].seq_type = "";
    var o2: u8[>..] = [];
    assert(payment_file::write_pain008(h, blocks, items, wopts, lim, o2).kind == payment_file::F_SYNTAX);
    blocks[0].seq_type = "FRST";
    items[0].mandate_id = "M<1>";
    var o3: u8[>..] = [];
    assert(payment_file::write_pain008(h, blocks, items, wopts, lim, o3).kind == payment_file::F_CHARSET);
    // With the set check off the markup is escaped, not written raw.
    var wraw = payment_file::PainWriteOptions { epc_charset: false, indent: false };
    var o4: u8[>..] = [];
    assert(payment_file::write_pain008(h, blocks, items, wraw, lim, o4).kind == payment_file::F_NONE);
    assert(find(o4, "M&lt;1&gt;") >= 0 && find(o4, "<1>") < 0);
    items[0].mandate_id = "M1";
    items[0].amount.minor = -1;
    var o5: u8[>..] = [];
    assert(payment_file::write_pain008(h, blocks, items, wopts, lim, o5).kind == payment_file::F_AMOUNT);
}


fn test_code_lists() {
    var lim = payment_file::default_limits();
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var dd: u8[>..] = [];
    assert(sample_debit(wopts, dd) == 0);
    var a: u8[>..] = [];
    replace_all(dd, "<PmtMtd>DD</PmtMtd>", "<PmtMtd>TRF</PmtMtd>", a);
    assert(read_debit_kind(a, false, lim) == payment_file::F_SYNTAX);
    var b: u8[>..] = [];
    replace_all(dd, "<ChrgBr>SLEV</ChrgBr>", "<ChrgBr>XXXX</ChrgBr>", b);
    assert(read_debit_kind(b, false, lim) == payment_file::F_SYNTAX);
    var c: u8[>..] = [];
    replace_all(dd, "<BIC>ABNANL2A</BIC>", "<BIC>AB</BIC>", c);
    assert(read_debit_kind(c, false, lim) == payment_file::F_SYNTAX);
    var d: u8[>..] = [];
    replace_all(dd, "<BIC>ABNANL2A</BIC>", "<BIC>abnanl2a</BIC>", d);
    assert(read_debit_kind(d, false, lim) == payment_file::F_SYNTAX);
    var cr: u8[>..] = [];
    assert(sample(wopts, cr) == 0);
    var e: u8[>..] = [];
    replace_all(cr, "<PmtMtd>TRF</PmtMtd>", "<PmtMtd>XYZ</PmtMtd>", e);
    assert(read_fault(e, false, lim) == payment_file::F_SYNTAX);
    var f: u8[>..] = [];
    replace_all(cr, "<ChrgBr>SLEV</ChrgBr>", "<ChrgBr>NONE</ChrgBr>", f);
    assert(read_fault(f, false, lim) == payment_file::F_SYNTAX);
    var g: u8[>..] = [];
    replace_all(cr, "<Cd>SALA</Cd>", "<Cd></Cd>", g);
    assert(read_fault(g, false, lim) == payment_file::F_SYNTAX);
    // The writers refuse the same values.
    var items: payment_file::DirectDebit[>..] = [];
    var t = payment_file::new_direct_debit();
    t.end_to_end_id = "E1";
    let m, okm = finance::money(100, "EUR");
    assert(okm);
    t.amount = m;
    t.mandate_id = "M1";
    t.signature_year = 2025; t.signature_month = 2; t.signature_day = 28;
    t.has_signature_date = true;
    t.debtor_name = "D";
    t.debtor_iban = "DE89370400440532013000";
    items.push(t);
    var blocks: payment_file::DebitInfo[>..] = [];
    var bl = payment_file::new_debit_info();
    bl.id = "B1"; bl.creditor_name = "C"; bl.creditor_iban = "NL91ABNA0417164300";
    bl.scheme_id = "DE98ZZZ09999999999"; bl.seq_type = "FRST"; bl.instrument = "CORE";
    bl.collection_year = 2026; bl.collection_month = 12; bl.collection_day = 1;
    bl.has_collection_date = true;
    bl.item_count = 1;
    blocks.push(bl);
    var h = payment_file::new_header();
    h.message_id = "M"; h.initiator = "I"; h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    var o1: u8[>..] = [];
    assert(payment_file::write_pain008(h, blocks, items, wopts, lim, o1).kind == payment_file::F_NONE);
    blocks[0].charge_bearer = "BOTH";
    var o2: u8[>..] = [];
    assert(payment_file::write_pain008(h, blocks, items, wopts, lim, o2).kind == payment_file::F_SYNTAX);
    blocks[0].charge_bearer = "";
    blocks[0].creditor_bic = "abc";
    var o3: u8[>..] = [];
    assert(payment_file::write_pain008(h, blocks, items, wopts, lim, o3).kind == payment_file::F_SYNTAX);
}

fn test_missing_amount() {
    var lim = payment_file::default_limits();
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var dd: u8[>..] = [];
    assert(sample_debit(wopts, dd) == 0);
    var c: u8[>..] = [];
    replace_all(dd, "InstdAmt", "Gone", c);
    assert(read_debit_kind(c, false, lim) == payment_file::F_SYNTAX);
    var cr: u8[>..] = [];
    assert(sample(wopts, cr) == 0);
    var d: u8[>..] = [];
    replace_all(cr, "InstdAmt", "Gone", d);
    assert(read_fault(d, false, lim) == payment_file::F_SYNTAX);
}

fn test_amount_overflow() {
    // The largest i64 is the last value that fits; one more must fault.
    let big, f1 = payment_file::parse_amount("92233720368547758.07", "EUR", "InstdAmt");
    assert(f1.kind == payment_file::F_NONE && big == 9223372036854775807);
    let _, f2 = payment_file::parse_amount("92233720368547758.08", "EUR", "InstdAmt");
    assert(f2.kind == payment_file::F_OVERFLOW);
    let _, f3 = payment_file::parse_amount("92233720368547759.99", "EUR", "InstdAmt");
    assert(f3.kind == payment_file::F_OVERFLOW);
    // A count that does not fit is no number.
    var lim = payment_file::default_limits();
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var out: u8[>..] = [];
    assert(sample_debit(wopts, out) == 0);
    var c: u8[>..] = [];
    replace_all(out, "<NbOfTxs>2</NbOfTxs>", "<NbOfTxs>9223372036854775808</NbOfTxs>", c);
    assert(read_debit_kind(c, false, lim) == payment_file::F_SYNTAX);
}

fn test_blocks_tile_items() {
    var lim = payment_file::default_limits();
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    // The debit sample holds two items in one block. A block that covers
    // one of them leaves an item out of every block.
    var items: payment_file::DirectDebit[>..] = [];
    var blocks: payment_file::DebitInfo[>..] = [];
    var out: u8[>..] = [];
    assert(sample_debit(wopts, out) == 0);
    var t = payment_file::new_direct_debit();
    t.end_to_end_id = "E1";
    let m, okm = finance::money(100, "EUR");
    assert(okm);
    t.amount = m;
    t.mandate_id = "M1";
    t.signature_year = 2025; t.signature_month = 2; t.signature_day = 28;
    t.has_signature_date = true;
    t.debtor_name = "D";
    t.debtor_iban = "DE89370400440532013000";
    items.push(t);
    items.push(t);
    var bl = payment_file::new_debit_info();
    bl.id = "B1"; bl.creditor_name = "C"; bl.creditor_iban = "NL91ABNA0417164300";
    bl.scheme_id = "DE98ZZZ09999999999"; bl.seq_type = "FRST"; bl.instrument = "CORE";
    bl.collection_year = 2026; bl.collection_month = 12; bl.collection_day = 1;
    bl.has_collection_date = true;
    bl.item_count = 1;
    blocks.push(bl);
    var h = payment_file::new_header();
    h.message_id = "M"; h.initiator = "I"; h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    var o1: u8[>..] = [];
    assert(payment_file::write_pain008(h, blocks, items, wopts, lim, o1).kind == payment_file::F_LIMIT);
    blocks[0].item_count = 2;
    var o2: u8[>..] = [];
    assert(payment_file::write_pain008(h, blocks, items, wopts, lim, o2).kind == payment_file::F_NONE);
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
    test_debit_round_trip();
    test_debit_newer_schema();
    test_debit_faults();
    test_code_lists();
    test_missing_amount();
    test_amount_overflow();
    test_blocks_tile_items();
    test_ach_round_trip();
    test_ach_writer_faults();
    test_ach_reader_faults();
    test_ach_switches();
    test_ach_consistency_details();
    test_ach_writer_agrees_with_reader();
    test_ach_empty_batch();
    test_ach_many_entries();
    test_ach_sec_rules();
    test_ach_reader_sec_and_order();
    test_ach_empty_batch_read();
    test_ach_entry_limit();
    test_ach_overlapping_addenda();
    test_ach_fixture();
    print("ok");
}

// ach_sample builds the base file: one batch of PPD credits and one
// batch of WEB debits with one addendum. The writer writes 10
// records: the header, the two batches with their controls, the file
// control and one record of nines.
fn ach_sample(out: u8[>..]&) -> i32 {
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var e1 = payment_file::new_ach_entry();
    e1.transaction_code = 22;
    e1.rdfi_routing = "121140399";
    e1.account = "00012345678";
    e1.amount = 10000;
    e1.individual_name = "Alice Doe";
    e1.trace_number = "121140390000001";
    entries.push(e1);
    var e2 = payment_file::new_ach_entry();
    e2.transaction_code = 37;
    e2.rdfi_routing = "021000021";
    e2.account = "9876543";
    e2.amount = 500;
    e2.individual_name = "Bob Roe";
    e2.trace_number = "021000020000001";
    e2.addenda_start = 0;
    e2.addenda_count = 1;
    entries.push(e2);
    var a1 = payment_file::new_ach_addenda();
    a1.text = "Payment for invoice 12";
    addenda.push(a1);
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
    b1.entry_count = 1;
    batches.push(b1);
    var b2 = payment_file::new_ach_batch();
    b2.service_class = 225;
    b2.company_name = "Acme Corp";
    b2.company_id = "1234567890";
    b2.sec_code = "WEB";
    b2.description = "DUES";
    b2.effective_year = 2026; b2.effective_month = 11; b2.effective_day = 10;
    b2.odfi_id = "02100002";
    b2.batch_number = 2;
    b2.entry_start = 1;
    b2.entry_count = 1;
    batches.push(b2);
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
    let f = payment_file::write_ach(h, batches, entries, addenda, lim, out);
    return f.kind;
}

// ach_read_kind parses a file and gives the fault kind.
fn ach_read_kind(input: const u8[:]) -> i32 {
    var h = payment_file::new_ach_file_header();
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    return payment_file::parse_ach(input, opts, lim, h, bs, es, ads).kind;
}

// ach_case builds a file of one batch and one entry from the values
// the caller gives, and gives the fault kind of the writer.
fn ach_case(out: u8[>..]&, tc: i64, amount: i64, routing: const u8[:], trace: const u8[:],
            svc: i64, cname: const u8[:], with_addenda: bool) -> i32 {
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var e = payment_file::new_ach_entry();
    e.transaction_code = tc;
    e.rdfi_routing = routing;
    e.account = "1";
    e.amount = amount;
    e.individual_name = "A";
    e.trace_number = trace;
    e.addenda_count = 0;
    if with_addenda {
        e.addenda_count = 1;
        var a = payment_file::new_ach_addenda();
        a.text = "x";
        addenda.push(a);
    }
    entries.push(e);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = svc;
    b.company_name = cname;
    b.company_id = "1234567890";
    b.sec_code = "PPD";
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
    h.destination_name = "Bank";
    h.origin_name = "Corp";
    var lim = payment_file::default_limits();
    return payment_file::write_ach(h, batches, entries, addenda, lim, out).kind;
}

fn test_ach_round_trip() {
    var out: u8[>..] = [];
    assert(ach_sample(out) == payment_file::F_NONE);
    // Every line holds 94 columns: 10 records of 95 bytes each.
    assert(out.len == 10 * 95);
    var h = payment_file::new_ach_file_header();
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    let r = payment_file::parse_ach(out, opts, lim, h, bs, es, ads);
    assert(r.kind == payment_file::F_NONE);
    assert(bs.len == 2);
    assert(es.len == 2);
    assert(ads.len == 1);
    assert(h.destination_routing == "121140399");
    assert(h.creation_year == 2026 && h.creation_hour == 14);
    assert(bs[0].sec_code == "PPD" && bs[0].service_class == 220);
    assert(bs[1].sec_code == "WEB" && bs[1].service_class == 225);
    assert(es[0].amount == 10000 && es[1].amount == 500);
    assert(es[0].transaction_code == 22 && es[1].transaction_code == 37);
    assert(es[1].addenda_count == 1);
    assert(ads[0].text == "Payment for invoice 12");
    assert(es[0].individual_name == "Alice Doe");
    assert(bs[1].batch_number == 2);
    // The writer computed the hash of the two routing prefixes:
    // 12114039 + 2100002 = 14214041.
    assert(find(out, "0014214041") >= 0);
}

fn test_ach_writer_faults() {
    var out: u8[>..] = [];
    // A prenote holds an amount of zero.
    assert(ach_case(out, 23, 5, "121140399", "121140390000001", 220, "C", false) == payment_file::F_AMOUNT);
    // The transaction code is in the NACHA set.
    assert(ach_case(out, 60, 5, "121140399", "121140390000001", 220, "C", false) == payment_file::F_SYNTAX);
    // A batch of credits only holds no debit.
    assert(ach_case(out, 27, 5, "121140399", "121140390000001", 220, "C", false) == payment_file::F_TOTAL);
    // A batch of debits only holds no credit.
    assert(ach_case(out, 22, 5, "121140399", "121140390000001", 225, "C", false) == payment_file::F_TOTAL);
    // The routing number passes the check digit.
    assert(ach_case(out, 22, 5, "121140391", "121140390000001", 220, "C", false) == payment_file::F_SYNTAX);
    // The trace number starts with the ODFI id.
    assert(ach_case(out, 22, 5, "121140399", "999999990000001", 220, "C", false) == payment_file::F_TOTAL);
    // No text is truncated: a long company name is a fault.
    assert(ach_case(out, 22, 5, "121140399", "121140390000001", 220, "0123456789abcdefg", false) == payment_file::F_LIMIT);
    // A fault leaves the output untouched.
    assert(out.len == 0);
    // A long addendum text is a fault.
    var long: u8[>..] = [];
    var i: i64 = 0;
    while i < 81 { long.push('x'); i += 1; }
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var e = payment_file::new_ach_entry();
    e.transaction_code = 22;
    e.rdfi_routing = "121140399";
    e.amount = 1;
    e.trace_number = "121140390000001";
    e.addenda_count = 1;
    entries.push(e);
    var a = payment_file::new_ach_addenda();
    a.text = long;
    addenda.push(a);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = 220;
    b.company_name = "C";
    b.company_id = "1234567890";
    b.sec_code = "PPD";
    b.description = "PAY";
    b.effective_year = 2026; b.effective_month = 11; b.effective_day = 10;
    b.odfi_id = "12114039";
    b.batch_number = 1;
    b.entry_count = 1;
    batches.push(b);
    var h = payment_file::new_ach_file_header();
    h.destination_routing = "121140399";
    h.origin_id = "1234567890";
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.id_modifier = "A";
    var lim = payment_file::default_limits();
    assert(payment_file::write_ach(h, batches, entries, addenda, lim, out).kind == payment_file::F_LIMIT);
    // A file with no batch is a fault.
    var bs2: payment_file::AchBatch[>..] = [];
    var es2: payment_file::AchEntry[>..] = [];
    var ad2: payment_file::AchAddenda[>..] = [];
    var out2: u8[>..] = [];
    assert(payment_file::write_ach(h, bs2, es2, ad2, lim, out2).kind == payment_file::F_SYNTAX);
}

fn test_ach_reader_faults() {
    var out: u8[>..] = [];
    assert(ach_sample(out) == payment_file::F_NONE);
    // A short last record is a fault with the line number.
    var short = out[0..940];
    assert(ach_read_kind(short) == payment_file::F_LIMIT);
    // A control byte in a text is a fault.
    out[42] = 1;
    assert(ach_read_kind(out) == payment_file::F_CHARSET);
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // A wrong entry count in the batch control is a fault.
    out[3 * 95 + 4] = '1';
    assert(ach_read_kind(out) == payment_file::F_TOTAL);
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // A wrong hash is a fault.
    out[3 * 95 + 10] = '1';
    assert(ach_read_kind(out) == payment_file::F_TOTAL);
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // A wrong debit total is a fault.
    out[7 * 95 + 20] = '1';
    assert(ach_read_kind(out) == payment_file::F_TOTAL);
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // A wrong routing check digit is a fault.
    out[2 * 95 + 11] = '8';
    assert(ach_read_kind(out) == payment_file::F_SYNTAX);
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // A wrong first record is a fault.
    out[0] = '5';
    assert(ach_read_kind(out) == payment_file::F_UNKNOWN_TAG);
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // A trace number from another ODFI is a fault.
    out[2 * 95 + 79] = '2';
    assert(ach_read_kind(out) == payment_file::F_TOTAL);
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // An entry that declares no addendum but holds one is a fault.
    out[5 * 95 + 78] = '0';
    assert(ach_read_kind(out) == payment_file::F_TOTAL);
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // An entry that declares an addendum it does not hold is a fault.
    out[2 * 95 + 78] = '1';
    assert(ach_read_kind(out) == payment_file::F_TOTAL);
}

// ach_read_detail parses a file and gives the fault detail.
fn ach_read_detail(input: const u8[:], want: const u8[:]) -> bool {
    var h = payment_file::new_ach_file_header();
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    let r = payment_file::parse_ach(input, opts, lim, h, bs, es, ads);
    return r.detail == want;
}

fn test_ach_consistency_details() {
    var out: u8[>..] = [];
    assert(ach_sample(out) == payment_file::F_NONE);
    out[3 * 95 + 4] = '1';
    assert(ach_read_detail(out, "the entry count of the control differs"));
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    out[3 * 95 + 10] = '1';
    assert(ach_read_detail(out, "the entry hash of the control differs"));
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    out[2 * 95 + 79] = '2';
    assert(ach_read_detail(out, "the trace number does not start with the ODFI id"));
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    out[5 * 95 + 78] = '0';
    assert(ach_read_detail(out, "the entry declares no addendum"));
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // A bad constant column of the file header.
    out[36] = '5';
    assert(ach_read_detail(out, "the record size, blocking factor or format code is wrong"));
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // A bad destination routing digit of the file header.
    out[12] = '8';
    assert(ach_read_detail(out, "the routing number does not pass the check digit"));
    out.clear();
    assert(ach_sample(out) == payment_file::F_NONE);
    // A control byte in a reserved column.
    out[2 * 95 + 93] = 1;
    assert(ach_read_detail(out, "the record holds a byte outside printable ASCII"));
}

fn test_ach_writer_agrees_with_reader() {
    var out: u8[>..] = [];
    // A year before 2000 is a fault: the file holds two digits.
    assert(ach_case_year(out, 1999) == payment_file::F_DATE);
    assert(ach_case_year(out, 2100) == payment_file::F_DATE);
    assert(ach_case_year(out, 2099) == payment_file::F_NONE);
    // A non-digit in the trace number is a fault.
    var out2: u8[>..] = [];
    assert(ach_case(out2, 22, 5, "121140399", "12114039000000A", 220, "C", false) == payment_file::F_SYNTAX);
}

// ach_case_year builds a one batch file with the given effective year.
fn ach_case_year(out: u8[>..]&, year: i32) -> i32 {
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var e = payment_file::new_ach_entry();
    e.transaction_code = 22;
    e.rdfi_routing = "121140399";
    e.amount = 1;
    e.trace_number = "121140390000001";
    entries.push(e);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = 220;
    b.company_name = "C";
    b.company_id = "1234567890";
    b.sec_code = "PPD";
    b.description = "PAY";
    b.effective_year = year; b.effective_month = 11; b.effective_day = 10;
    b.odfi_id = "12114039";
    b.batch_number = 1;
    b.entry_count = 1;
    batches.push(b);
    var h = payment_file::new_ach_file_header();
    h.destination_routing = "121140399";
    h.origin_id = "1234567890";
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.id_modifier = "A";
    var lim = payment_file::default_limits();
    return payment_file::write_ach(h, batches, entries, addenda, lim, out).kind;
}

fn test_ach_empty_batch() {
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = 220;
    b.company_name = "C";
    b.company_id = "1234567890";
    b.sec_code = "PPD";
    b.effective_year = 2026; b.effective_month = 11; b.effective_day = 10;
    b.odfi_id = "12114039";
    b.batch_number = 1;
    batches.push(b);
    var h = payment_file::new_ach_file_header();
    h.destination_routing = "121140399";
    h.origin_id = "1234567890";
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.id_modifier = "A";
    var lim = payment_file::default_limits();
    var out: u8[>..] = [];
    assert(payment_file::write_ach(h, batches, entries, addenda, lim, out).kind == payment_file::F_SYNTAX);
}

// ach_two builds a file of one batch with two entries. The second entry
// holds the given count of addenda. The traces are the ones the caller gives.
fn ach_two(out: u8[>..]&, sec: const u8[:], desc: const u8[:], tc1: i64, amt1: i64, tr1: const u8[:],
           tc2: i64, amt2: i64, tr2: const u8[:], adds: i64) -> i32 {
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var e1 = payment_file::new_ach_entry();
    e1.transaction_code = tc1;
    e1.rdfi_routing = "121140399";
    e1.account = "1";
    e1.amount = amt1;
    e1.individual_name = "A";
    e1.trace_number = tr1;
    entries.push(e1);
    var e2 = payment_file::new_ach_entry();
    e2.transaction_code = tc2;
    e2.rdfi_routing = "021000021";
    e2.account = "2";
    e2.amount = amt2;
    e2.individual_name = "B";
    e2.trace_number = tr2;
    e2.addenda_count = adds as i32;
    var k: i64 = 0;
    while k < adds {
        var a = payment_file::new_ach_addenda();
        a.text = "note";
        addenda.push(a);
        k += 1;
    }
    entries.push(e2);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = 200;
    b.company_name = "C";
    b.company_id = "1234567890";
    b.sec_code = sec;
    b.description = desc;
    b.effective_year = 2026; b.effective_month = 11; b.effective_day = 10;
    b.odfi_id = "12114039";
    b.batch_number = 1;
    b.entry_count = 2;
    batches.push(b);
    var h = payment_file::new_ach_file_header();
    h.destination_routing = "121140399";
    h.origin_id = "1234567890";
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.id_modifier = "A";
    var lim = payment_file::default_limits();
    return payment_file::write_ach(h, batches, entries, addenda, lim, out).kind;
}

fn test_ach_many_entries() {
    var out: u8[>..] = [];
    assert(ach_two(out, "PPD", "PAY", 22, 100, "121140390000001", 22, 250, "121140390000002", 1) == payment_file::F_NONE);
    var h = payment_file::new_ach_file_header();
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    let r = payment_file::parse_ach(out, opts, lim, h, bs, es, ads);
    assert(r.kind == payment_file::F_NONE);
    assert(bs.len == 1 && bs[0].entry_count == 2);
    assert(es.len == 2 && ads.len == 1);
    assert(es[0].amount == 100 && es[1].amount == 250);
    assert(es[0].addenda_count == 0 && es[1].addenda_count == 1);
    assert(es[1].addenda_start == 0);
}

fn test_ach_sec_rules() {
    var o: u8[>..] = [];
    // PPD, CCD and WEB hold one addendum, not two.
    assert(ach_two(o, "PPD", "PAY", 22, 1, "121140390000001", 22, 1, "121140390000002", 2) == payment_file::F_LIMIT);
    assert(ach_two(o, "CCD", "PAY", 22, 1, "121140390000001", 22, 1, "121140390000002", 2) == payment_file::F_LIMIT);
    assert(ach_two(o, "WEB", "PAY", 27, 1, "121140390000001", 27, 1, "121140390000002", 2) == payment_file::F_LIMIT);
    // TEL, ARC, BOC, POP and RCK hold debits only and no addenda.
    assert(ach_two(o, "TEL", "PAY", 27, 1, "121140390000001", 22, 1, "121140390000002", 0) == payment_file::F_TOTAL);
    assert(ach_two(o, "POP", "PAY", 27, 1, "121140390000001", 27, 1, "121140390000002", 1) == payment_file::F_LIMIT);
    // A reversal batch holds the opposite direction.
    assert(ach_two(o, "TEL", "REVERSAL", 22, 1, "121140390000001", 22, 1, "121140390000002", 0) == payment_file::F_NONE);
    assert(ach_two(o, "TEL", "REVERSAL", 27, 1, "121140390000001", 22, 1, "121140390000002", 0) == payment_file::F_TOTAL);
    // The amount caps of ARC and RCK.
    assert(ach_two(o, "ARC", "PAY", 27, 2500000, "121140390000001", 27, 1, "121140390000002", 0) == payment_file::F_NONE);
    assert(ach_two(o, "ARC", "PAY", 27, 2500001, "121140390000001", 27, 1, "121140390000002", 0) == payment_file::F_AMOUNT);
    assert(ach_two(o, "RCK", "PAY", 27, 250001, "121140390000001", 27, 1, "121140390000002", 0) == payment_file::F_AMOUNT);
    // The traces of a batch ascend.
    assert(ach_two(o, "PPD", "PAY", 22, 1, "121140390000002", 22, 1, "121140390000001", 0) == payment_file::F_TOTAL);
    assert(ach_two(o, "PPD", "PAY", 22, 1, "121140390000001", 22, 1, "121140390000001", 0) == payment_file::F_TOTAL);
}

fn test_ach_reader_sec_and_order() {
    var out: u8[>..] = [];
    assert(ach_two(out, "PPD", "PAY", 22, 100, "121140390000001", 22, 250, "121140390000002", 0) == payment_file::F_NONE);
    // The first trace changes to a larger number: the order breaks.
    out[2 * 95 + 93] = '5';
    assert(ach_read_detail(out, "the trace numbers of the batch do not ascend"));
    out.clear();
    assert(ach_two(out, "TEL", "PAY", 27, 100, "121140390000001", 27, 250, "121140390000002", 0) == payment_file::F_NONE);
    // The SEC code changes from TEL to PPD at columns 51 to 53 of the batch header.
    out[95 + 50] = 'P'; out[95 + 51] = 'P'; out[95 + 52] = 'D';
    assert(ach_read_kind(out) == payment_file::F_NONE);
    out[95 + 50] = 'A'; out[95 + 51] = 'R'; out[95 + 52] = 'C';
    assert(ach_read_kind(out) == payment_file::F_NONE);
    // A credit entry in a TEL batch: change the first transaction code to 22.
    out[95 + 50] = 'T'; out[95 + 51] = 'E'; out[95 + 52] = 'L';
    out[2 * 95 + 1] = '2';
    out[2 * 95 + 2] = '2';
    assert(ach_read_detail(out, "this SEC code holds debits only"));
}

// ach_overlap gives the fault kind of a file whose two entries claim the same addendum.
fn ach_overlap(out: u8[>..]&) -> i32 {
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var a0 = payment_file::new_ach_addenda();
    a0.text = "INVOICE 1";
    addenda.push(a0);
    var a1 = payment_file::new_ach_addenda();
    a1.text = "INVOICE 2";
    addenda.push(a1);
    var e0 = payment_file::new_ach_entry();
    e0.transaction_code = 22;
    e0.rdfi_routing = "121140399";
    e0.amount = 1;
    e0.trace_number = "121140390000001";
    e0.addenda_start = 0;
    e0.addenda_count = 1;
    entries.push(e0);
    var e1 = payment_file::new_ach_entry();
    e1.transaction_code = 22;
    e1.rdfi_routing = "121140399";
    e1.amount = 1;
    e1.trace_number = "121140390000002";
    e1.addenda_start = 0;
    e1.addenda_count = 1;
    entries.push(e1);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = 220;
    b.company_name = "C";
    b.company_id = "1234567890";
    b.sec_code = "PPD";
    b.description = "PAY";
    b.effective_year = 2026; b.effective_month = 11; b.effective_day = 10;
    b.odfi_id = "12114039";
    b.batch_number = 1;
    b.entry_count = 2;
    batches.push(b);
    var h = payment_file::new_ach_file_header();
    h.destination_routing = "121140399";
    h.origin_id = "1234567890";
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.id_modifier = "A";
    var lim = payment_file::default_limits();
    return payment_file::write_ach(h, batches, entries, addenda, lim, out).kind;
}

fn test_ach_overlapping_addenda() {
    var out: u8[>..] = [];
    assert(ach_overlap(out) == payment_file::F_LIMIT);
    assert(out.len == 0);
}

fn test_ach_entry_limit() {
    var out: u8[>..] = [];
    assert(ach_two(out, "PPD", "PAY", 22, 100, "121140390000001", 22, 250, "121140390000002", 0) == payment_file::F_NONE);
    var h = payment_file::new_ach_file_header();
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var lim = payment_file::default_limits();
    lim.max_entries = 1;
    var opts = payment_file::new_ach_options();
    assert(payment_file::parse_ach(out, opts, lim, h, bs, es, ads).kind == payment_file::F_LIMIT);
    var h2 = payment_file::new_ach_file_header();
    var bs2: payment_file::AchBatch[>..] = [];
    var es2: payment_file::AchEntry[>..] = [];
    var ads2: payment_file::AchAddenda[>..] = [];
    var lim2 = payment_file::default_limits();
    lim2.max_entries = 2;
    assert(payment_file::parse_ach(out, opts, lim2, h2, bs2, es2, ads2).kind == payment_file::F_NONE);
}

fn test_ach_empty_batch_read() {
    var out: u8[>..] = [];
    assert(ach_sample(out) == payment_file::F_NONE);
    // Keep the file header, the first batch header and the first batch control.
    var f: u8[>..] = [];
    var i: i64 = 0;
    while i < 190 { f.push(out[i]); i += 1; }
    i = 3 * 95;
    while i < 4 * 95 { f.push(out[i]); i += 1; }
    assert(ach_read_detail(f, "the batch holds no entry"));
}

fn test_ach_switches() {
    var out: u8[>..] = [];
    assert(ach_sample(out) == payment_file::F_NONE);
    // The wrong count passes with the total check off.
    out[3 * 95 + 4] = '1';
    var h = payment_file::new_ach_file_header();
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var lim = payment_file::default_limits();
    var opts = payment_file::AchOptions { skip_total_check: true, check_routing: true };
    assert(payment_file::parse_ach(out, opts, lim, h, bs, es, ads).kind == payment_file::F_NONE);
    var out2: u8[>..] = [];
    assert(ach_sample(out2) == payment_file::F_NONE);
    // The wrong routing digit passes with the routing check off.
    out2[2 * 95 + 11] = '8';
    var h2 = payment_file::new_ach_file_header();
    var bs2: payment_file::AchBatch[>..] = [];
    var es2: payment_file::AchEntry[>..] = [];
    var ads2: payment_file::AchAddenda[>..] = [];
    var opts2 = payment_file::AchOptions { skip_total_check: false, check_routing: false };
    assert(payment_file::parse_ach(out2, opts2, lim, h2, bs2, es2, ads2).kind == payment_file::F_NONE);
}

fn test_ach_fixture() {
    // A hand-built file in the style of the test files of the Go
    // reference library: one batch of PPD credits, no padding. The
    // records are composed from parts, so every column is exact.
    var f: u8[>..] = [];
    // File header.
    f.push('1'); put(f, "01"); f.push(' ');
    put(f, "121140399");
    put(f, "0123456789");
    put(f, "261109");
    put(f, "1430");
    f.push('A');
    put(f, "094");
    put(f, "10");
    f.push('1');
    pad_to(f, "ACME BANK", 23);
    pad_to(f, "ACME CORP", 23);
    pad_to(f, "REF00001", 8);
    f.push('\n');
    // Batch header.
    f.push('5'); put(f, "220");
    pad_to(f, "ACME CORP", 16);
    pad_to(f, "", 20);
    put(f, "1234567890");
    put(f, "PPD");
    pad_to(f, "PAYROLL", 10);
    put(f, "      ");
    put(f, "261110");
    put(f, "   ");
    f.push('1');
    put(f, "12114039");
    put(f, "0000001");
    f.push('\n');
    // Entry detail.
    f.push('6');
    put(f, "22");
    put(f, "121140399");
    pad_to(f, "00012345678", 17);
    put(f, "0000100000");
    pad_to(f, "", 15);
    pad_to(f, "ALICE DOE", 22);
    put(f, "  ");
    f.push('0');
    put(f, "121140390000001");
    f.push('\n');
    // Batch control.
    f.push('8');
    put(f, "220");
    put(f, "000001");
    put(f, "0012114039");
    put(f, "000000000000");
    put(f, "000000100000");
    put(f, "1234567890");
    pad_to(f, "", 19);
    pad_to(f, "", 6);
    put(f, "12114039");
    put(f, "0000001");
    f.push('\n');
    // File control.
    f.push('9');
    put(f, "000001");
    put(f, "000001");
    put(f, "00000001");
    put(f, "0012114039");
    put(f, "000000000000");
    put(f, "000000100000");
    pad_to(f, "", 39);
    f.push('\n');
    var h = payment_file::new_ach_file_header();
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    let r = payment_file::parse_ach(f, opts, lim, h, bs, es, ads);
    assert(r.kind == payment_file::F_NONE);
    assert(bs.len == 1 && es.len == 1);
    assert(h.destination_routing == "121140399");
    assert(h.creation_year == 2026 && h.creation_month == 11 && h.creation_day == 9);
    assert(bs[0].company_name == "ACME CORP" && bs[0].sec_code == "PPD");
    assert(es[0].amount == 100000);
    assert(es[0].individual_name == "ALICE DOE");
    assert(es[0].trace_number == "121140390000001");
}

// pad_to appends a text and fills the rest of the width with spaces.
fn pad_to(dst: u8[>..]&, s: const u8[:], width: i64) {
    var i: i64 = 0;
    while i < s.len { dst.push(s[i]); i += 1; }
    while i < width { dst.push(' '); i += 1; }
}

// put appends a text.
fn put(dst: u8[>..]&, s: const u8[:]) {
    var i: i64 = 0;
    while i < s.len { dst.push(s[i]); i += 1; }
}
