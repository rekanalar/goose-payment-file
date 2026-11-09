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
    test_pacs008_round_trip();
    test_pacs008_order();
    test_pacs008_escape();
    test_pacs008_writer_faults();
    test_pacs008_atomic();
    test_pacs008_mixed_currency();
    test_pacs008_fixture_v06();
    test_pacs008_fixture_v08();
    test_pacs008_fixture_v09();
    test_pacs008_reader_faults();
    test_pacs008_hostile();
    test_pacs008_switches();
    test_pacs008_missing_parts();
    test_pacs008_no_account();
    test_pacs008_security();
    test_iat_round_trip();
    test_iat_optional();
    test_iat_returns();
    test_iat_refusals();
    test_iat_mixed();
    test_sec_round_trips();
    test_sec_returns();
    test_sec_shr();
    test_sec_refusals();
    test_sec_bad_return_codes();
    test_sec_mixed();
    print("ok");
}

// iat_file_header gives the file header of the IAT tests.
fn iat_file_header() -> payment_file::AchFileHeader {
    var h = payment_file::new_ach_file_header();
    h.destination_routing = "121140399";
    h.origin_id = "1234567890";
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.creation_hour = 14; h.creation_minute = 30;
    h.id_modifier = "A";
    h.destination_name = "Acme Bank";
    h.origin_name = "Acme Corp";
    h.reference = "REF00001";
    return h;
}

// iat_build writes one IAT batch with one entry. The flag opt adds the
// optional records of types 02, 17 and 18. The kind drop leaves one
// mandatory record out. The flag long_name gives the name of the
// record of type 10 one byte too many.
fn iat_build(opt: bool, drop: i64, long_name: bool, dob: const u8[:], out: u8[>..]&) -> payment_file::Fault {
    var addenda: payment_file::IatAddenda[>..] = [];
    if opt {
        var a = payment_file::new_iat_addenda(2);
        a.ref_one = "REF1"; a.terminal_id = "T1"; a.serial = "000001";
        a.date_month = 11; a.date_day = 9; a.auth_code = "AUTH01";
        a.location = "Main St"; a.city = "Boston"; a.state = "MA";
        addenda.push(a);
    }
    if drop != 10 {
        var a = payment_file::new_iat_addenda(10);
        a.txn_type_code = "BUS"; a.foreign_amount = 11000; a.foreign_trace = "FX123";
        a.name = "Hans Mueller";
        if long_name { a.name = "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJ"; }
        addenda.push(a);
    }
    if drop != 11 {
        var a = payment_file::new_iat_addenda(11);
        a.name = "Acme Corp"; a.street = "1 Main St";
        addenda.push(a);
    }
    if drop != 12 {
        var a = payment_file::new_iat_addenda(12);
        a.city_state = "New York*NY\\"; a.country_postal = "US*10001\\";
        addenda.push(a);
    }
    if drop != 13 {
        var a = payment_file::new_iat_addenda(13);
        a.name = "Acme Bank"; a.id_qualifier = "01"; a.id_number = "121140399";
        a.branch_country = "US";
        addenda.push(a);
    }
    if drop != 14 {
        var a = payment_file::new_iat_addenda(14);
        a.name = "Deutsche Bank"; a.id_qualifier = "02"; a.id_number = "DEUTDEFF";
        a.branch_country = "DE";
        addenda.push(a);
    }
    if drop != 15 {
        var a = payment_file::new_iat_addenda(15);
        a.receiver_id = "R-123"; a.street = "Hauptstr 5";
        addenda.push(a);
    }
    if drop != 16 {
        var a = payment_file::new_iat_addenda(16);
        a.city_state = "Berlin*BE\\"; a.country_postal = "DE*10115\\";
        a.date_of_birth = dob;
        addenda.push(a);
    }
    if opt {
        var a = payment_file::new_iat_addenda(17);
        a.payment_info = "Invoice 77";
        addenda.push(a);
        var b = payment_file::new_iat_addenda(17);
        b.payment_info = "Second line";
        addenda.push(b);
        var c = payment_file::new_iat_addenda(18);
        c.name = "Corr Bank"; c.id_qualifier = "02"; c.id_number = "CORRUS33";
        c.branch_country = "US";
        addenda.push(c);
    }
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
    b.batch_number = 2;
    b.entry_start = 0;
    b.entry_count = 1;
    batches.push(b);
    var lim = payment_file::default_limits();
    return payment_file::write_ach_iat(iat_file_header(), batches, entries, addenda, lim, out);
}

// iat_read parses a file of the IAT tests and gives the fault kind.
fn iat_read(input: u8[>..]&, bs: payment_file::AchBatch[>..]&, es: payment_file::AchEntry[>..]&,
            ads: payment_file::AchAddenda[>..]&, ib: payment_file::IatBatch[>..]&,
            ie: payment_file::IatEntry[>..]&, ia: payment_file::IatAddenda[>..]&) -> i32 {
    var h = payment_file::new_ach_file_header();
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    return payment_file::parse_ach_iat(input, opts, lim, h, bs, es, ads, ib, ie, ia).kind;
}

// iat_kind parses a file and gives the fault kind and nothing else.
fn iat_kind(input: u8[>..]&) -> i32 {
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var ib: payment_file::IatBatch[>..] = [];
    var ie: payment_file::IatEntry[>..] = [];
    var ia: payment_file::IatAddenda[>..] = [];
    return iat_read(input, bs, es, ads, ib, ie, ia);
}

// test_iat_round_trip writes an IAT batch with the seven mandatory
// records and reads it back.
fn test_iat_round_trip() {
    var out: u8[>..] = [];
    assert(iat_build(false, 0, false, "1980-01-02", out).kind == payment_file::F_NONE);
    // 12 records pad to 2 blocks of 10: 20 records of 95 bytes.
    assert(out.len == 20 * 95);
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var ib: payment_file::IatBatch[>..] = [];
    var ie: payment_file::IatEntry[>..] = [];
    var ia: payment_file::IatAddenda[>..] = [];
    assert(iat_read(out, bs, es, ads, ib, ie, ia) == payment_file::F_NONE);
    assert(bs.len == 0 && es.len == 0 && ads.len == 0);
    assert(ib.len == 1 && ie.len == 1 && ia.len == 7);
    assert(ib[0].fx_indicator == "FF" && ib[0].fx_ref_indicator == 3);
    assert(ib[0].dest_country == "DE" && ib[0].origin_currency == "USD" && ib[0].dest_currency == "EUR");
    assert(ib[0].originator_id == "1234567890" && ib[0].description == "PAYMENT");
    assert(ib[0].effective_year == 2026 && ib[0].effective_month == 11 && ib[0].effective_day == 10);
    assert(ib[0].batch_number == 2 && ib[0].entry_count == 1);
    assert(ib[0].settlement_date == "");
    assert(ie[0].transaction_code == 22 && ie[0].amount == 12345);
    assert(ie[0].rdfi_routing == "021000021");
    assert(ie[0].dfi_account == "DE89370400440532013000");
    assert(ie[0].trace_number == "121140390000001");
    assert(ie[0].addenda_count == 7);
    assert(ia[0].kind == 10 && ia[0].txn_type_code == "BUS" && ia[0].foreign_amount == 11000);
    assert(ia[0].foreign_trace == "FX123" && ia[0].name == "Hans Mueller");
    assert(ia[1].kind == 11 && ia[1].name == "Acme Corp" && ia[1].street == "1 Main St");
    assert(ia[2].kind == 12 && ia[2].city_state == "New York*NY\\");
    assert(ia[3].kind == 13 && ia[3].id_number == "121140399" && ia[3].branch_country == "US");
    assert(ia[4].kind == 14 && ia[4].name == "Deutsche Bank" && ia[4].id_qualifier == "02");
    assert(ia[5].kind == 15 && ia[5].receiver_id == "R-123" && ia[5].street == "Hauptstr 5");
    assert(ia[6].kind == 16 && ia[6].date_of_birth == "1980-01-02");
    // The settlement date of the batch header comes from the file.
    var sd: u8[>..] = [];
    replace_all(out, "EUR261110   112114039", "EUR261110010112114039", sd);
    var ib2: payment_file::IatBatch[>..] = [];
    var ie2: payment_file::IatEntry[>..] = [];
    var ia2: payment_file::IatAddenda[>..] = [];
    var bs2: payment_file::AchBatch[>..] = [];
    var es2: payment_file::AchEntry[>..] = [];
    var ads2: payment_file::AchAddenda[>..] = [];
    assert(iat_read(sd, bs2, es2, ads2, ib2, ie2, ia2) == payment_file::F_NONE);
    assert(ib2[0].settlement_date == "010");
    // parse_ach refuses a file with an IAT batch, so no batch is lost.
    var h = payment_file::new_ach_file_header();
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    var b2: payment_file::AchBatch[>..] = [];
    var e2: payment_file::AchEntry[>..] = [];
    var a2: payment_file::AchAddenda[>..] = [];
    assert(payment_file::parse_ach(out, opts, lim, h, b2, e2, a2).kind == payment_file::F_UNKNOWN_TAG);
}

// test_iat_optional adds the optional records of types 02, 17 and 18.
fn test_iat_optional() {
    var out: u8[>..] = [];
    assert(iat_build(true, 0, false, "1980-01-02", out).kind == payment_file::F_NONE);
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var ib: payment_file::IatBatch[>..] = [];
    var ie: payment_file::IatEntry[>..] = [];
    var ia: payment_file::IatAddenda[>..] = [];
    assert(iat_read(out, bs, es, ads, ib, ie, ia) == payment_file::F_NONE);
    assert(ia.len == 11 && ie[0].addenda_count == 11);
    assert(ia[0].kind == 2 && ia[0].ref_one == "REF1" && ia[0].terminal_id == "T1");
    assert(ia[0].serial == "000001" && ia[0].date_month == 11 && ia[0].date_day == 9);
    assert(ia[0].auth_code == "AUTH01" && ia[0].location == "Main St");
    assert(ia[0].city == "Boston" && ia[0].state == "MA");
    assert(ia[1].kind == 10 && ia[7].kind == 16);
    assert(ia[8].kind == 17 && ia[8].payment_info == "Invoice 77" && ia[8].sequence == 1);
    assert(ia[9].kind == 17 && ia[9].payment_info == "Second line" && ia[9].sequence == 2);
    assert(ia[10].kind == 18 && ia[10].name == "Corr Bank" && ia[10].id_number == "CORRUS33");
    assert(ia[10].branch_country == "US" && ia[10].sequence == 1);
}

// returns_build writes a batch of two WEB entries. The first holds a
// return of the given code and the second holds a notice of change
// of the given code.
fn returns_build(return_code: const u8[:], change_code: const u8[:], with_death: bool,
                 out: u8[>..]&) -> payment_file::Fault {
    var addenda: payment_file::AchAddenda[>..] = [];
    var r = payment_file::new_ach_addenda();
    r.kind = 99;
    r.return_code = return_code;
    r.original_trace = "121140390000009";
    r.original_dfi = "12114039";
    r.addenda_information = "INSUFFICIENT";
    if with_death { r.death_year = 2026; r.death_month = 11; r.death_day = 1; }
    addenda.push(r);
    var n = payment_file::new_ach_addenda();
    n.kind = 98;
    n.change_code = change_code;
    n.original_trace = "121140390000008";
    n.original_dfi = "12114039";
    n.corrected_data = "00012345678";
    addenda.push(n);
    var entries: payment_file::AchEntry[>..] = [];
    var e1 = payment_file::new_ach_entry();
    e1.transaction_code = 27;
    e1.rdfi_routing = "121140399";
    e1.account = "00012345678";
    e1.amount = 100;
    e1.trace_number = "121140390000001";
    e1.addenda_start = 0;
    e1.addenda_count = 1;
    entries.push(e1);
    var e2 = payment_file::new_ach_entry();
    e2.transaction_code = 27;
    e2.rdfi_routing = "121140399";
    e2.account = "00012345678";
    e2.amount = 200;
    e2.trace_number = "121140390000002";
    e2.addenda_start = 1;
    e2.addenda_count = 1;
    entries.push(e2);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = 200;
    b.company_name = "Acme Corp";
    b.company_id = "1234567890";
    b.sec_code = "WEB";
    b.description = "RETURNS";
    b.effective_year = 2026; b.effective_month = 11; b.effective_day = 10;
    b.odfi_id = "12114039";
    b.batch_number = 1;
    b.entry_start = 0;
    b.entry_count = 2;
    batches.push(b);
    var lim = payment_file::default_limits();
    return payment_file::write_ach(iat_file_header(), batches, entries, addenda, lim, out);
}

// test_iat_returns writes a return and a notice of change and reads
// them back.
fn test_iat_returns() {
    var out: u8[>..] = [];
    assert(returns_build("R01", "C01", true, out).kind == payment_file::F_NONE);
    var h = payment_file::new_ach_file_header();
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    assert(payment_file::parse_ach(out, opts, lim, h, bs, es, ads).kind == payment_file::F_NONE);
    assert(ads.len == 2 && es[0].addenda_count == 1 && es[1].addenda_count == 1);
    assert(ads[0].kind == 99 && ads[0].return_code == "R01");
    assert(ads[0].original_trace == "121140390000009" && ads[0].original_dfi == "12114039");
    assert(ads[0].addenda_information == "INSUFFICIENT");
    assert(ads[0].death_year == 2026 && ads[0].death_month == 11 && ads[0].death_day == 1);
    assert(ads[1].kind == 98 && ads[1].change_code == "C01");
    assert(ads[1].original_trace == "121140390000008");
    assert(ads[1].corrected_data == "00012345678");
    // A return with no date of death reads back with no date.
    var out2: u8[>..] = [];
    assert(returns_build("R90", "C69", false, out2).kind == payment_file::F_NONE);
    var bs2: payment_file::AchBatch[>..] = [];
    var es2: payment_file::AchEntry[>..] = [];
    var ads2: payment_file::AchAddenda[>..] = [];
    assert(payment_file::parse_ach(out2, opts, lim, h, bs2, es2, ads2).kind == payment_file::F_NONE);
    assert(ads2[0].return_code == "R90" && ads2[0].death_year == 0);
    assert(ads2[1].change_code == "C69");
}

// test_iat_refusals pins the writer and reader faults of the IAT
// batch, the returns and the notices.
fn test_iat_refusals() {
    var out: u8[>..] = [];
    // A mandatory record that is missing is a fault in the writer.
    assert(iat_build(false, 13, false, "1980-01-02", out).kind == payment_file::F_SYNTAX);
    assert(iat_build(false, 10, false, "1980-01-02", out).kind == payment_file::F_SYNTAX);
    assert(iat_build(false, 16, false, "1980-01-02", out).kind == payment_file::F_SYNTAX);
    // A text that is longer than its field is a fault, never a cut.
    assert(iat_build(false, 0, true, "1980-01-02", out).kind == payment_file::F_LIMIT);
    // A return code in a gap of the list, a lower-case code and a
    // change code in a gap are faults in the writer.
    assert(returns_build("R48", "C01", false, out).kind == payment_file::F_SYNTAX);
    assert(returns_build("R54", "C01", false, out).kind == payment_file::F_SYNTAX);
    assert(returns_build("r01", "C01", false, out).kind == payment_file::F_SYNTAX);
    assert(returns_build("R01", "C10", false, out).kind == payment_file::F_SYNTAX);
    assert(returns_build("R01", "C70", false, out).kind == payment_file::F_SYNTAX);
    // Every fault left the output as it was.
    assert(out.len == 0);
    // The reader refuses the same faults in a file.
    var good: u8[>..] = [];
    assert(iat_build(false, 0, false, "1980-01-02", good).kind == payment_file::F_NONE);
    var bad: u8[>..] = [];
    replace_all(good, "0000012345DE89", "0000012346DE89", bad);
    assert(iat_kind(bad) == payment_file::F_TOTAL);
    var fx: u8[>..] = [];
    replace_all(good, "FF3", "XX3", fx);
    assert(iat_kind(fx) == payment_file::F_SYNTAX);
    var ret: u8[>..] = [];
    assert(returns_build("R01", "C01", false, ret).kind == payment_file::F_NONE);
    var r48: u8[>..] = [];
    replace_all(ret, "R01", "R48", r48);
    assert(iat_kind(r48) == payment_file::F_SYNTAX);
    var c10: u8[>..] = [];
    replace_all(ret, "C01", "C10", c10);
    assert(iat_kind(c10) == payment_file::F_SYNTAX);
    // The skip switch turns the total checks off, not the layout checks.
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var ib: payment_file::IatBatch[>..] = [];
    var ie: payment_file::IatEntry[>..] = [];
    var ia: payment_file::IatAddenda[>..] = [];
    var h = payment_file::new_ach_file_header();
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    opts.skip_total_check = true;
    assert(payment_file::parse_ach_iat(bad, opts, lim, h, bs, es, ads, ib, ie, ia).kind == payment_file::F_NONE);
    // A control byte or a byte above 127 in any column is a fault.
    var ctl: u8[>..] = [];
    replace_all(good, "Hans Mueller", "Hans\x01Mueller", ctl);
    assert(iat_kind(ctl) == payment_file::F_CHARSET);
    var high: u8[>..] = [];
    replace_all(good, "Hans Mueller", "Hans\xc3\xa9Mueller", high);
    assert(iat_kind(high) == payment_file::F_CHARSET);
    // A date of birth that is not a date is a fault in the writer.
    assert(iat_build(false, 0, false, "1980-13-45", out).kind == payment_file::F_DATE);
    assert(iat_build(false, 0, false, "19800102", out).kind == payment_file::F_DATE);
    // An empty date of birth is allowed, because a corporate
    // originator has none.
    var empty: u8[>..] = [];
    assert(iat_build(false, 0, false, "", empty).kind == payment_file::F_NONE);
    assert(iat_kind(empty) == payment_file::F_NONE);
    // The reader refuses a malformed date of birth in a file.
    var bad_dob: u8[>..] = [];
    replace_all(good, "1980-01-02", "1980-13-45", bad_dob);
    assert(iat_kind(bad_dob) == payment_file::F_DATE);
    // The limits hold the reader back when the file holds too much.
    var small = payment_file::default_limits();
    small.max_addenda = 3;
    assert(payment_file::parse_ach_iat(good, opts, small, h, bs, es, ads, ib, ie, ia).kind == payment_file::F_LIMIT);
}

// record_at gives the record n of a file of 95 byte records.
fn record_at(src: u8[>..]&, n: i64) -> const u8[:] {
    return src[n * 95..(n + 1) * 95];
}

// test_iat_mixed reads a file with a PPD batch and an IAT batch. The
// file control covers both.
fn test_iat_mixed() {
    // The PPD batch: one credit of 100.00.
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var e = payment_file::new_ach_entry();
    e.transaction_code = 22;
    e.rdfi_routing = "121140399";
    e.account = "00012345678";
    e.amount = 10000;
    e.trace_number = "121140390000001";
    entries.push(e);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = 220;
    b.company_name = "Acme Corp";
    b.company_id = "1234567890";
    b.sec_code = "PPD";
    b.description = "PAYROLL";
    b.effective_year = 2026; b.effective_month = 11; b.effective_day = 10;
    b.odfi_id = "12114039";
    b.batch_number = 1;
    b.entry_start = 0;
    b.entry_count = 1;
    batches.push(b);
    var lim = payment_file::default_limits();
    var ppd: u8[>..] = [];
    assert(payment_file::write_ach(iat_file_header(), batches, entries, addenda, lim, ppd).kind == payment_file::F_NONE);
    var iat: u8[>..] = [];
    assert(iat_build(false, 0, false, "1980-01-02", iat).kind == payment_file::F_NONE);
    // The mixed file: the header, the PPD batch records 1 to 3, the IAT
    // batch records 1 to 10, then the file control and the padding.
    var mixed: u8[>..] = [];
    put(mixed, record_at(ppd, 0));
    var k: i64 = 1;
    while k <= 3 { put(mixed, record_at(ppd, k)); k += 1; }
    k = 1;
    while k <= 10 { put(mixed, record_at(iat, k)); k += 1; }
    // 2 batches, 2 blocks, 9 entries and addenda, hash 14214041,
    // credits 10000 + 12345.
    put(mixed, "9000002000002000000090014214041000000000000000000022345");
    k = 0;
    while k < 39 { mixed.push(' '); k += 1; }
    mixed.push('\n');
    var rest: i64 = 0;
    while rest < 5 {
        k = 0;
        while k < 94 { mixed.push('9'); k += 1; }
        mixed.push('\n');
        rest += 1;
    }
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    var ib: payment_file::IatBatch[>..] = [];
    var ie: payment_file::IatEntry[>..] = [];
    var ia: payment_file::IatAddenda[>..] = [];
    assert(iat_read(mixed, bs, es, ads, ib, ie, ia) == payment_file::F_NONE);
    assert(bs.len == 1 && es.len == 1 && ib.len == 1 && ie.len == 1 && ia.len == 7);
    assert(bs[0].sec_code == "PPD" && ib[0].dest_country == "DE");
    // A wrong batch count in the file control is a fault.
    var bad: u8[>..] = [];
    replace_all(mixed, "9000002000002", "9000003000002", bad);
    assert(iat_kind(bad) == payment_file::F_TOTAL);
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

// The transactions of the sample message: one credit from a debtor to
// a creditor in euros and one in dollars.
// pacs_tx gives a valid transaction for the tests to change.
fn pacs_tx() -> payment_file::Pacs008Tx {
    var t = payment_file::new_pacs008_tx();
    t.end_to_end_id = "E2E-1";
    t.instruction_id = "INSTR-1";
    t.transaction_id = "TX-1";
    t.uetr = "123e4567-e89b-42d3-a456-426614174000";
    t.amount = finance::Money { minor: 10050, code: "EUR" };
    t.has_settlement_date = true;
    t.settle_year = 2026; t.settle_month = 12; t.settle_day = 1;
    t.charge_bearer = "SLEV";
    t.debtor_name = "Acme Trading Ltd";
    t.debtor_country = "NL";
    t.debtor_iban = "NL91ABNA0417164300";
    t.debtor_bic = "ABNANL2A";
    t.creditor_name = "Creditor One";
    t.creditor_country = "DE";
    t.creditor_iban = "DE89370400440532013000";
    t.creditor_bic = "COBADEFFXXX";
    t.remittance = "Invoice 42";
    return t;
}

// pacs_hdr gives a valid header for the tests to change.
fn pacs_hdr() -> payment_file::Pacs008Header {
    var h = payment_file::new_pacs008_header();
    h.base.message_id = "MSG-2026-0002";
    h.base.has_creation = true;
    h.base.creation_year = 2026; h.base.creation_month = 11; h.base.creation_day = 9;
    h.base.creation_minutes = 14 * 60 + 30;
    h.base.creation_offset = 60;
    h.settlement_method = "INDA";
    h.has_settlement_date = true;
    h.settle_year = 2026; h.settle_month = 12; h.settle_day = 1;
    h.has_batch_booking = true;
    h.batch_booking = false;
    h.instructing_bic = "ABNANL2A";
    h.instructed_bic = "COBADEFFXXX";
    return h;
}

// write_one writes one transaction under a good header and gives the
// kind of the fault.
fn write_one(h: payment_file::Pacs008Header, t: payment_file::Pacs008Tx, epc: bool) -> i32 {
    var txs: payment_file::Pacs008Tx[>..] = [];
    txs.push(t);
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: epc, indent: false };
    var lim = payment_file::default_limits();
    let f = payment_file::write_pacs008(h, txs, wopts, lim, out);
    return f.kind;
}

fn pacs_sample(opts: payment_file::PainWriteOptions, out: u8[>..]&) -> i32 {
    var txs: payment_file::Pacs008Tx[>..] = [];
    txs.push(pacs_tx());
    var t2 = pacs_tx();
    t2.end_to_end_id = "E2E-2";
    t2.instruction_id = "";
    t2.transaction_id = "";
    t2.uetr = "";
    t2.amount = finance::Money { minor: 250, code: "EUR" };
    t2.debtor_country = "";
    t2.creditor_name = "Creditor Two AG";
    t2.creditor_country = "";
    t2.creditor_iban = "CH9300762011623852957";
    t2.creditor_bic = "POFICHBEXXX";
    t2.remittance = "";
    txs.push(t2);
    var lim = payment_file::default_limits();
    let f = payment_file::write_pacs008(pacs_hdr(), txs, opts, lim, out);
    return f.kind;
}

// pacs_read reads a document and gives the kind of the fault.
fn pacs_read(doc: const u8[:], skip: bool, ibans: bool, lim: payment_file::Limits&) -> i32 {
    var h = payment_file::new_pacs008_header();
    var txs: payment_file::Pacs008Tx[>..] = [];
    var buf: u8[>..] = [];
    var ropts = payment_file::PainOptions { skip_control_sum_check: skip, check_iban: ibans, epc_charset: true };
    let r = payment_file::parse_pacs008(doc, lim, ropts, h, txs, buf);
    return r.kind;
}

fn test_pacs008_round_trip() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    let w = pacs_sample(wopts, out);
    if w != 0 { print("FAIL pacs write ", w, "\n"); }
    assert(w == 0);
    assert(find(out, "pacs.008.001.08") >= 0);
    assert(find(out, "<NbOfTxs>2</NbOfTxs>") >= 0);
    assert(find(out, "<CtrlSum>103.00</CtrlSum>") >= 0);
    assert(find(out, "<IntrBkSttlmAmt Ccy=\"EUR\">100.50</IntrBkSttlmAmt>") >= 0);
    assert(find(out, "<TtlIntrBkSttlmAmt Ccy=\"EUR\">103.00</TtlIntrBkSttlmAmt>") >= 0);
    assert(find(out, "<SttlmMtd>INDA</SttlmMtd>") >= 0);
    assert(find(out, "<UETR>123e4567-e89b-42d3-a456-426614174000</UETR>") >= 0);
    assert(find(out, "<BICFI>ABNANL2A</BICFI>") >= 0);
    var h = payment_file::new_pacs008_header();
    var txs: payment_file::Pacs008Tx[>..] = [];
    var buf: u8[>..] = [];
    var lim = payment_file::default_limits();
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    let text: const u8[:] = out[..];
    let r = payment_file::parse_pacs008(text, lim, ropts, h, txs, buf);
    if r.kind != 0 { print("FAIL pacs read ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == 0);
    assert(h.base.message_id == "MSG-2026-0002");
    assert(h.base.has_creation && h.base.creation_year == 2026);
    assert(h.base.count == 2 && h.base.has_control_sum && h.base.control_sum == 10300);
    assert(h.settlement_method == "INDA");
    assert(h.has_settlement_date && h.settle_day == 1);
    assert(h.has_batch_booking && !h.batch_booking);
    assert(h.instructing_bic == "ABNANL2A" && h.instructed_bic == "COBADEFFXXX");
    assert(txs.len == 2);
    assert(txs[0].end_to_end_id == "E2E-1" && txs[0].instruction_id == "INSTR-1" && txs[0].transaction_id == "TX-1");
    assert(txs[0].uetr == "123e4567-e89b-42d3-a456-426614174000");
    assert(txs[0].amount.minor == 10050 && txs[0].amount.code == "EUR");
    assert(txs[0].has_settlement_date && txs[0].settle_month == 12);
    assert(txs[0].charge_bearer == "SLEV");
    assert(txs[0].debtor_name == "Acme Trading Ltd" && txs[0].debtor_country == "NL");
    assert(txs[0].debtor_iban == "NL91ABNA0417164300" && txs[0].debtor_bic == "ABNANL2A");
    assert(txs[0].creditor_name == "Creditor One" && txs[0].creditor_country == "DE");
    assert(txs[0].creditor_iban == "DE89370400440532013000" && txs[0].creditor_bic == "COBADEFFXXX");
    assert(txs[0].remittance == "Invoice 42");
    assert(txs[1].end_to_end_id == "E2E-2" && txs[1].amount.minor == 250);
    assert(txs[1].creditor_iban == "CH9300762011623852957");
}

fn test_pacs008_order() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    let w = pacs_sample(wopts, out);
    assert(w == 0);
    // The order of the group header and of the transaction.
    var tags = ["<MsgId>", "<CreDtTm>", "<BtchBookg>", "<NbOfTxs>", "<CtrlSum>", "<TtlIntrBkSttlmAmt",
                "<IntrBkSttlmDt>", "<SttlmInf>", "<InstgAgt>", "<InstdAgt>", "<CdtTrfTxInf>",
                "<PmtId>", "<EndToEndId>", "<UETR>", "<ChrgBr>", "<Dbtr>", "<DbtrAcct>", "<DbtrAgt>",
                "<CdtrAgt>", "<Cdtr>", "<CdtrAcct>", "<RmtInf>"];
    var last: i64 = -1;
    var i: i64 = 0;
    while i < tags.len {
        let at = find(out, tags[i]);
        assert(at >= 0);
        assert(at > last);
        last = at;
        i += 1;
    }
}

fn test_pacs008_escape() {
    // The set check is off, so a name with markup reaches the file.
    // The writer escapes it, so it cannot end the element.
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: false, indent: false };
    var t1 = pacs_tx();
    t1.debtor_name = "A & B <Ltd>";
    t1.creditor_name = "Creditor & Co";
    var txs: payment_file::Pacs008Tx[>..] = [];
    txs.push(t1);
    var h = pacs_hdr();
    h.base.message_id = "MSG-ESC";
    var lim = payment_file::default_limits();
    let f = payment_file::write_pacs008(h, txs, wopts, lim, out);
    assert(f.kind == 0);
    assert(find(out, "A &amp; B &lt;Ltd&gt;") >= 0);
    assert(find(out, "Creditor &amp; Co") >= 0);
    assert(find(out, "<Ltd>") < 0);
    var rh = payment_file::new_pacs008_header();
    var rtxs: payment_file::Pacs008Tx[>..] = [];
    var buf: u8[>..] = [];
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: false };
    let text: const u8[:] = out[..];
    let r = payment_file::parse_pacs008(text, lim, ropts, rh, rtxs, buf);
    assert(r.kind == 0);
    assert(rtxs[0].debtor_name == "A & B <Ltd>");
}

fn test_pacs008_writer_faults() {
    var h = pacs_hdr();
    // An empty list of transactions.
    var none: payment_file::Pacs008Tx[>..] = [];
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var lim = payment_file::default_limits();
    let f0 = payment_file::write_pacs008(h, none, wopts, lim, out);
    assert(f0.kind != 0);
    // A bad settlement method.
    var h2 = pacs_hdr();
    h2.settlement_method = "XXXX";
    assert(write_one(h2, pacs_tx(), true) == payment_file::F_SYNTAX);
    // A bad UETR.
    var t2 = pacs_tx();
    t2.uetr = "not-a-uuid";
    assert(write_one(h, t2, true) != 0);
    // A negative amount.
    var t3 = pacs_tx();
    t3.amount = finance::Money { minor: -1, code: "EUR" };
    assert(write_one(h, t3, true) == payment_file::F_AMOUNT);
    // A bad IBAN.
    var t4 = pacs_tx();
    t4.debtor_iban = "NL91ABNA0417164301";
    assert(write_one(h, t4, true) == payment_file::F_IBAN);
    // An empty end-to-end id.
    var t5 = pacs_tx();
    t5.end_to_end_id = "";
    assert(write_one(h, t5, true) == payment_file::F_SYNTAX);
    // An IBAN and an other id in one account.
    var t6 = pacs_tx();
    t6.debtor_other_id = "123";
    assert(write_one(h, t6, true) == payment_file::F_SYNTAX);
    // A missing settlement date in the group header.
    var h3 = pacs_hdr();
    h3.has_settlement_date = false;
    assert(write_one(h3, pacs_tx(), true) == payment_file::F_DATE);
    // A transaction with no settlement date of its own is legal.
    var t7 = pacs_tx();
    t7.has_settlement_date = false;
    assert(write_one(h, t7, true) == 0);
    // A bad charge bearer.
    var t8 = pacs_tx();
    t8.charge_bearer = "XXXX";
    assert(write_one(h, t8, true) == payment_file::F_SYNTAX);
    // A country that is not two capital letters.
    var t9 = pacs_tx();
    t9.debtor_country = "nld";
    assert(write_one(h, t9, true) == payment_file::F_SYNTAX);
}

fn test_pacs008_atomic() {
    var lim = payment_file::default_limits();
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var out: u8[>..] = [];
    let w = pacs_sample(wopts, out);
    assert(w == 0);
    let before = out.len;
    var h = pacs_hdr();
    h.base.message_id = "MSG-ATOMIC";
    // The first extra message lands in the buffer.
    var txs: payment_file::Pacs008Tx[>..] = [];
    txs.push(pacs_tx());
    let f = payment_file::write_pacs008(h, txs, wopts, lim, out);
    assert(f.kind == 0);
    assert(out.len > before);
    // A fault after the header leaves the buffer as it was.
    var before2 = out.len;
    var txs2: payment_file::Pacs008Tx[>..] = [];
    var t2 = pacs_tx();
    t2.uetr = "123e4567-e89b-12d3-a456-426614174000";
    txs2.push(t2);
    let f2 = payment_file::write_pacs008(h, txs2, wopts, lim, out);
    assert(f2.kind != 0);
    assert(out.len == before2);
}

fn test_pacs008_mixed_currency() {
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var out: u8[>..] = [];
    var txs: payment_file::Pacs008Tx[>..] = [];
    txs.push(pacs_tx());
    var t2 = pacs_tx();
    t2.end_to_end_id = "E2E-2";
    t2.amount = finance::Money { minor: 200, code: "USD" };
    txs.push(t2);
    var lim = payment_file::default_limits();
    let f = payment_file::write_pacs008(pacs_hdr(), txs, wopts, lim, out);
    assert(f.kind == 0);
    assert(find(out, "<CtrlSum>") < 0);
    assert(find(out, "<TtlIntrBkSttlmAmt") < 0);
    assert(find(out, "<NbOfTxs>2</NbOfTxs>") >= 0);
}

// The message of the version .001.06. The element names of that
// version hold the BIC under BICFI and no total of the header.
fn test_pacs008_fixture_v06() {
    let doc = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.06">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>MSG-06</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><TtlIntrBkSttlmAmt Ccy="EUR">10.00</TtlIntrBkSttlmAmt>
<IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt><SttlmInf><SttlmMtd>INGA</SttlmMtd></SttlmInf>
</GrpHdr><CdtTrfTxInf><PmtId><EndToEndId>E-06</EndToEndId><TxId>T-06</TxId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">10.00</IntrBkSttlmAmt><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<ChrgBr>SLEV</ChrgBr><Dbtr><Nm>Debtor SA</Nm><PstlAdr><Ctry>NL</Ctry></PstlAdr></Dbtr>
<DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct>
<DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>Creditor BV</Nm></Cdtr><CdtrAcct><Id><IBAN>BE68539007547034</IBAN></Id></CdtrAcct>
<RmtInf><Ustrd>Invoice 7</Ustrd></RmtInf></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    var lim = payment_file::default_limits();
    var h = payment_file::new_pacs008_header();
    var txs: payment_file::Pacs008Tx[>..] = [];
    var buf: u8[>..] = [];
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    let r = payment_file::parse_pacs008(doc, lim, ropts, h, txs, buf);
    if r.kind != 0 { print("FAIL pacs06 ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == 0);
    assert(h.base.message_id == "MSG-06" && h.settlement_method == "INGA");
    assert(h.has_settlement_date && h.settle_month == 2);
    assert(h.base.count == 1);
    assert(txs.len == 1);
    assert(txs[0].end_to_end_id == "E-06" && txs[0].transaction_id == "T-06");
    assert(txs[0].amount.minor == 1000);
    assert(txs[0].debtor_country == "NL" && txs[0].debtor_bic == "ABNANL2A");
    assert(txs[0].creditor_bic == "COBADEFFXXX");
    assert(txs[0].remittance == "Invoice 7");
}

// The message of the version .001.08 with the clearing system member
// id instead of a BIC.
fn test_pacs008_fixture_v08() {
    let doc = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>MSG-08</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>10.00</CtrlSum><TtlIntrBkSttlmAmt Ccy="EUR">10.00</TtlIntrBkSttlmAmt>
<IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt><SttlmInf><SttlmMtd>CLRG</SttlmMtd></SttlmInf>
</GrpHdr><CdtTrfTxInf><PmtId><EndToEndId>E-08</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">10.00</IntrBkSttlmAmt><ChrgBr>DEBT</ChrgBr>
<Dbtr><Nm>Debtor SA</Nm></Dbtr>
<DbtrAcct><Id><Othr><Id>ACCT-08</Id></Othr></Id></DbtrAcct>
<DbtrAgt><FinInstnId><ClrSysMmbId><MmbId>234567891</MmbId></ClrSysMmbId></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><ClrSysMmbId><MmbId>000000010</MmbId></ClrSysMmbId></FinInstnId></CdtrAgt>
<Cdtr><Nm>Creditor BV</Nm></Cdtr>
<CdtrAcct><Id><Othr><Id>ACCT-09</Id></Othr></Id></CdtrAcct>
</CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    var lim = payment_file::default_limits();
    var h = payment_file::new_pacs008_header();
    var txs: payment_file::Pacs008Tx[>..] = [];
    var buf: u8[>..] = [];
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    let r = payment_file::parse_pacs008(doc, lim, ropts, h, txs, buf);
    if r.kind != 0 { print("FAIL pacs08 ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == 0);
    assert(h.settlement_method == "CLRG");
    assert(h.base.control_sum == 1000);
    assert(txs.len == 1);
    assert(txs[0].debtor_other_id == "ACCT-08" && txs[0].debtor_iban == "");
    assert(txs[0].debtor_member_id == "234567891");
    assert(txs[0].creditor_other_id == "ACCT-09");
    assert(txs[0].creditor_member_id == "000000010");
}

// The message of the version .001.09 with the BIC under the name BIC
// and the UETR in the payment id.
fn test_pacs008_fixture_v09() {
    let doc = """
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.09">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>MSG-09</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>10.00</CtrlSum>
<IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt><SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf>
</GrpHdr><CdtTrfTxInf><PmtId><EndToEndId>E-09</EndToEndId>
<UETR>123e4567-e89b-42d3-a456-426614174000</UETR></PmtId>
<IntrBkSttlmAmt Ccy="EUR">10.00</IntrBkSttlmAmt><ChrgBr>SHAR</ChrgBr>
<Dbtr><Nm>Debtor SA</Nm></Dbtr>
<DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct>
<DbtrAgt><FinInstnId><BIC>ABNANL2A</BIC></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BIC>COBADEFFXXX</BIC></FinInstnId></CdtrAgt>
<Cdtr><Nm>Creditor BV</Nm></Cdtr><CdtrAcct><Id><IBAN>BE68539007547034</IBAN></Id></CdtrAcct>
</CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    var lim = payment_file::default_limits();
    var h = payment_file::new_pacs008_header();
    var txs: payment_file::Pacs008Tx[>..] = [];
    var buf: u8[>..] = [];
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    let r = payment_file::parse_pacs008(doc, lim, ropts, h, txs, buf);
    if r.kind != 0 { print("FAIL pacs09 ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == 0);
    assert(txs.len == 1);
    assert(txs[0].uetr == "123e4567-e89b-42d3-a456-426614174000");
    assert(txs[0].debtor_bic == "ABNANL2A" && txs[0].creditor_bic == "COBADEFFXXX");
    assert(txs[0].charge_bearer == "SHAR");
}

fn test_pacs008_reader_faults() {
    var lim = payment_file::default_limits();
    // A bad settlement method.
    let bad_method = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>ZZZZ</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(bad_method, false, true, lim) == payment_file::F_SYNTAX);
    // A count that differs from the transactions.
    let bad_count = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>5</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(bad_count, false, true, lim) == payment_file::F_TOTAL);
    // A control sum that differs from the transactions.
    let bad_sum = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>99.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(bad_sum, false, true, lim) == payment_file::F_TOTAL);
    // A total of the header that differs, with no control sum.
    let bad_total = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><TtlIntrBkSttlmAmt Ccy="EUR">99.00</TtlIntrBkSttlmAmt>
<IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(bad_total, false, true, lim) == payment_file::F_TOTAL);
    // A bad UETR.
    let bad_uetr = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId><UETR>nope</UETR></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(bad_uetr, false, true, lim) == payment_file::F_SYNTAX);
    // A bad IBAN.
    let bad_iban = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAcct><Id><IBAN>NL91ABNA0417164301</IBAN></Id></DbtrAcct>
<DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(bad_iban, false, true, lim) == payment_file::F_IBAN);
    // An amount with no currency.
    let no_ccy = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt>1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(no_ccy, false, true, lim) == payment_file::F_AMOUNT);
    // A message with no transaction.
    let empty = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>0</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(empty, false, true, lim) == payment_file::F_SYNTAX);
    // A document that is not well formed.
    assert(pacs_read("<Document><FIToFICstmrCdtTrf>", false, true, lim) == payment_file::F_SYNTAX);
}

fn test_pacs008_hostile() {
    var lim = payment_file::default_limits();
    // A doctype and an entity. The package never expands an entity.
    let entity = """
<?xml version="1.0"?>
<!DOCTYPE Document [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>&xxe;</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    let k = pacs_read(entity, false, true, lim);
    assert(k == payment_file::F_SYNTAX || k == payment_file::F_CHARSET);
    // A count that does not fit.
    let big_count = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>99999999999999999999999</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(big_count, false, true, lim) != 0);
    // An amount that does not fit.
    let big_amount = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">92233720368547758.08</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(big_amount, false, true, lim) == payment_file::F_OVERFLOW);
    // A control byte in a name.
    let control = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C&#1;</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(control, false, true, lim) != 0);
}

fn test_pacs008_switches() {
    var lim = payment_file::default_limits();
    // The sum check off lets a wrong sum pass.
    let bad_sum = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>99.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(bad_sum, true, true, lim) == 0);
    // The IBAN check off lets a bad IBAN pass.
    let bad_iban = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAcct><Id><IBAN>NL91ABNA0417164301</IBAN></Id></DbtrAcct>
<DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(bad_iban, false, false, lim) == 0);
    // The item limit holds.
    var lim2 = payment_file::default_limits();
    lim2.max_items = 0;
    assert(pacs_read(bad_sum, false, true, lim2) == payment_file::F_LIMIT);
}

// The message of one transaction with the given parts. The parts that
// are empty come out of the document.
fn pacs_doc(count: const u8[:], method: const u8[:], e2e: const u8[:], bearer: const u8[:],
            debtor: const u8[:], dbtr_agt: const u8[:], cdtr_agt: const u8[:], creditor: const u8[:]) -> const u8[:] {
    if count == "zero" {
        return """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>0</NbOfTxs><CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    }
    if method == "none" {
        return """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
</GrpHdr><CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    }
    if e2e == "none" {
        return """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    }
    if bearer == "none" {
        return """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    }
    if debtor == "none" {
        return """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    }
    if dbtr_agt == "none" {
        return """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    }
    if cdtr_agt == "none" {
        return """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    }
    return """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm></Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm></Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
}

fn test_pacs008_no_account() {
    // The schema makes the account optional. A message without an
    // account is written and read back.
    var lim = payment_file::default_limits();
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var t1 = pacs_tx();
    t1.debtor_iban = "";
    t1.creditor_iban = "";
    var txs: payment_file::Pacs008Tx[>..] = [];
    txs.push(t1);
    var h = pacs_hdr();
    h.base.message_id = "MSG-NOACCT";
    var out: u8[>..] = [];
    let f = payment_file::write_pacs008(h, txs, wopts, lim, out);
    assert(f.kind == 0);
    assert(find(out, "<DbtrAcct>") < 0);
    assert(find(out, "<CdtrAcct>") < 0);
    var rh = payment_file::new_pacs008_header();
    var rtxs: payment_file::Pacs008Tx[>..] = [];
    var buf: u8[>..] = [];
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    let text: const u8[:] = out[..];
    let r = payment_file::parse_pacs008(text, lim, ropts, rh, rtxs, buf);
    assert(r.kind == 0);
    assert(rtxs.len == 1);
    assert(rtxs[0].debtor_iban == "" && rtxs[0].debtor_other_id == "");
    assert(rtxs[0].creditor_iban == "" && rtxs[0].creditor_other_id == "");
}

fn test_pacs008_missing_parts() {
    var lim = payment_file::default_limits();
    // A claimed count of zero with one transaction.
    assert(pacs_read(pacs_doc("zero", "", "", "", "", "", "", ""), false, true, lim) == payment_file::F_TOTAL);
    // A group header with no settlement method.
    assert(pacs_read(pacs_doc("", "none", "", "", "", "", "", ""), false, true, lim) == payment_file::F_SYNTAX);
    // A transaction with no end-to-end id.
    assert(pacs_read(pacs_doc("", "", "none", "", "", "", "", ""), false, true, lim) == payment_file::F_SYNTAX);
    // A transaction with no charge bearer.
    assert(pacs_read(pacs_doc("", "", "", "none", "", "", "", ""), false, true, lim) == payment_file::F_SYNTAX);
    // A transaction with no debtor.
    assert(pacs_read(pacs_doc("", "", "", "", "none", "", "", ""), false, true, lim) == payment_file::F_SYNTAX);
    // A transaction with no debtor agent.
    assert(pacs_read(pacs_doc("", "", "", "", "", "none", "", ""), false, true, lim) == payment_file::F_SYNTAX);
    // A transaction with no creditor agent.
    assert(pacs_read(pacs_doc("", "", "", "", "", "", "none", ""), false, true, lim) == payment_file::F_SYNTAX);
    // A transaction with an empty debtor name and an empty creditor name.
    assert(pacs_read(pacs_doc("", "", "", "", "", "", "", ""), false, true, lim) == payment_file::F_SYNTAX);
}

// test_pacs008_security covers the checks that stop a hostile message
// from passing: the country of a party, the count of the group, the
// currency of the group total and the sum of the group.
fn test_pacs008_security() {
    var lim = payment_file::default_limits();
    // A country that is not two capital letters.
    let bad_country = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm><PstlAdr><Ctry>ab</Ctry></PstlAdr></Dbtr>
<DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(bad_country, false, true, lim) == payment_file::F_SYNTAX);
    // A group header with no count of transactions.
    let no_count = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<CtrlSum>1.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(no_count, false, true, lim) == payment_file::F_SYNTAX);
    // A group total in another currency than the transactions.
    let other_ccy = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><CtrlSum>1.00</CtrlSum>
<TtlIntrBkSttlmAmt Ccy="USD">1.00</TtlIntrBkSttlmAmt>
<IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(other_ccy, false, true, lim) == payment_file::F_AMOUNT);
    // A group header with no sum of the transactions.
    let no_sum = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>1</NbOfTxs><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(no_sum, false, true, lim) == payment_file::F_TOTAL);
    // Two currencies in the transactions and a sum in the group header.
    let mixed_sum = """
<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08">
<FIToFICstmrCdtTrf><GrpHdr><MsgId>M</MsgId><CreDtTm>2026-02-03T08:00:00</CreDtTm>
<NbOfTxs>2</NbOfTxs><CtrlSum>3.00</CtrlSum><IntrBkSttlmDt>2026-02-03</IntrBkSttlmDt>
<SttlmInf><SttlmMtd>INDA</SttlmMtd></SttlmInf></GrpHdr>
<CdtTrfTxInf><PmtId><EndToEndId>E</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="EUR">1.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf>
<CdtTrfTxInf><PmtId><EndToEndId>F</EndToEndId></PmtId>
<IntrBkSttlmAmt Ccy="USD">2.00</IntrBkSttlmAmt><ChrgBr>SLEV</ChrgBr>
<Dbtr><Nm>D</Nm></Dbtr><DbtrAgt><FinInstnId><BICFI>ABNANL2A</BICFI></FinInstnId></DbtrAgt>
<CdtrAgt><FinInstnId><BICFI>COBADEFFXXX</BICFI></FinInstnId></CdtrAgt>
<Cdtr><Nm>C</Nm></Cdtr></CdtTrfTxInf></FIToFICstmrCdtTrf></Document>
""";
    assert(pacs_read(mixed_sum, false, true, lim) == payment_file::F_TOTAL);
}

// sec_build writes a file with one batch of the SEC code and one
// entry. The entry holds the transaction code, the amount and the
// service class of the batch. It holds the card fields of a SHR
// entry. The kind and the form pick the addenda of the entry. The
// kind 0 means that the entry holds no addenda.
fn sec_build(sec: const u8[:], tc: i64, amount: i64, svc: i64,
             disc: const u8[:], id_text: const u8[:], name: const u8[:],
             state: const u8[:], a_kind: i64, a_form: i64, out: u8[>..]&) -> i32 {
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var e = payment_file::new_ach_entry();
    e.transaction_code = tc;
    e.rdfi_routing = "121140399";
    e.account = "00012345678";
    e.amount = amount;
    e.individual_id = id_text;
    e.individual_name = name;
    e.discretionary = disc;
    e.trace_number = "121140390000001";
    e.addenda_count = 0;
    if a_kind != 0 {
        e.addenda_count = 1;
        e.addenda_start = 0;
        var a = payment_file::new_ach_addenda();
        a.kind = a_kind;
        a.form = a_form;
        if a_kind == 5 {
            a.text = "Payment for invoice 12";
        }
        if a_kind == 98 {
            a.change_code = "C01";
            a.original_trace = "121140390000001";
            a.original_dfi = "12114039";
            a.corrected_data = "A";
        }
        if a_kind == 2 {
            a.ref_one = "REF";
            a.ref_two = "AB";
            a.terminal_id = "TERM01";
            a.serial = "000001";
            a.date_month = 11;
            a.date_day = 9;
            a.auth_code = "AUTH01";
            a.location = "1 Main St";
            a.city = "New York";
            a.state = state;
        }
        if a_kind == 99 {
            a.original_trace = "121140390000001";
            a.original_dfi = "12114039";
            if a_form == 1 {
                a.return_code = "R61";
                a.return_trace = "121140390000002";
                a.return_settlement = 100;
                a.return_reason = "01";
                a.addenda_information = "info";
            }
            if a_form == 2 {
                a.return_code = "R71";
                a.date_returned = "260102";
                a.original_settlement = 100;
                a.return_trace = "121140390000002";
                a.return_settlement = 101;
                a.return_reason = "01";
                a.dishonored_trace = "121140390000003";
                a.dishonored_settlement = 102;
                a.dishonored_reason = "61";
            }
        }
        addenda.push(a);
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
    h.destination_name = "Bank";
    h.origin_name = "Corp";
    var lim = payment_file::default_limits();
    return payment_file::write_ach(h, batches, entries, addenda, lim, out).kind;
}

// sec_parse reads a file back and gives the fault of the reader.
// The buffer is a reference, so the fields of the records may point
// into it for the whole round trip.
fn sec_parse(out: u8[>..]&, bs: payment_file::AchBatch[>..]&,
             es: payment_file::AchEntry[>..]&,
             ads: payment_file::AchAddenda[>..]&) -> i32 {
    var h = payment_file::new_ach_file_header();
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    return payment_file::parse_ach(out, opts, lim, h, bs, es, ads).kind;
}

// sec_round_trip writes a batch of the SEC code and reads it back.
// It checks the fields that the entry holds.
fn sec_round_trip(sec: const u8[:], tc: i64, amount: i64, svc: i64,
                  disc: const u8[:], id_text: const u8[:], name: const u8[:],
                  a_kind: i64, a_form: i64) -> bool {
    var out: u8[>..] = [];
    if sec_build(sec, tc, amount, svc, disc, id_text, name, "NY", a_kind, a_form, out)
       != payment_file::F_NONE {
        return false;
    }
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    if sec_parse(out, bs, es, ads) != payment_file::F_NONE { return false; }
    if bs.len != 1 || es.len != 1 { return false; }
    if bs[0].sec_code != sec { return false; }
    if es[0].transaction_code != tc { return false; }
    if es[0].amount != amount { return false; }
    if es[0].individual_name != name { return false; }
    if disc.len > 0 && es[0].discretionary != disc { return false; }
    if id_text.len > 0 && es[0].individual_id != id_text { return false; }
    if a_kind == 0 && ads.len != 0 { return false; }
    if a_kind != 0 && ads.len != 1 { return false; }
    return true;
}

fn test_sec_round_trips() {
    // ACK holds a zero dollar remittance credit prenote and one
    // addendum.
    assert(sec_round_trip("ACK", 23, 0, 220, "", "", "A", 5, 0));
    // ATX holds the count of its addenda in the individual name.
    assert(sec_round_trip("ATX", 23, 0, 220, "", "", "0001Receiver", 5, 0));
    // CIE holds credits only.
    assert(sec_round_trip("CIE", 22, 100, 220, "", "", "A", 5, 0));
    // COR holds a notice of change.
    assert(sec_round_trip("COR", 21, 0, 220, "", "", "A", 98, 0));
    // DNE holds one addendum.
    assert(sec_round_trip("DNE", 23, 0, 220, "", "", "A", 5, 0));
    // ENR holds one addendum.
    assert(sec_round_trip("ENR", 23, 0, 220, "", "", "A", 5, 0));
    // SHR holds the card fields and the terminal record.
    assert(sec_round_trip("SHR", 22, 100, 220, "21", "12280000000001", "A", 2, 0));
    // TRC holds debits only and no addendum.
    assert(sec_round_trip("TRC", 27, 100, 225, "", "", "A", 0, 0));
    // TRX holds the count of its addenda in the individual name.
    assert(sec_round_trip("TRX", 27, 100, 225, "", "", "0001Receiver", 5, 0));
    // XCK holds debits only and no addendum.
    assert(sec_round_trip("XCK", 27, 100, 225, "", "", "A", 0, 0));
}

fn test_sec_returns() {
    // The dishonored form of the return rides on a normal entry.
    var out: u8[>..] = [];
    assert(sec_build("PPD", 27, 100, 225, "", "", "A", "NY", 99, 1, out)
           == payment_file::F_NONE);
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out, bs, es, ads) == payment_file::F_NONE);
    assert(ads.len == 1);
    assert(ads[0].kind == 99 && ads[0].form == 1);
    assert(ads[0].return_code == "R61");
    assert(ads[0].original_trace == "121140390000001");
    assert(ads[0].original_dfi == "12114039");
    assert(ads[0].return_trace == "121140390000002");
    assert(ads[0].return_settlement == 100);
    assert(ads[0].return_reason == "01");
    assert(ads[0].addenda_information == "info");
    // The contested form of the return rides on a normal entry.
    var out2: u8[>..] = [];
    assert(sec_build("PPD", 27, 100, 225, "", "", "A", "NY", 99, 2, out2)
           == payment_file::F_NONE);
    var bs2: payment_file::AchBatch[>..] = [];
    var es2: payment_file::AchEntry[>..] = [];
    var ads2: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out2, bs2, es2, ads2) == payment_file::F_NONE);
    assert(ads2.len == 1);
    assert(ads2[0].kind == 99 && ads2[0].form == 2);
    assert(ads2[0].return_code == "R71");
    assert(ads2[0].date_returned == "260102");
    assert(ads2[0].original_settlement == 100);
    assert(ads2[0].return_trace == "121140390000002");
    assert(ads2[0].return_settlement == 101);
    assert(ads2[0].return_reason == "01");
    assert(ads2[0].dishonored_trace == "121140390000003");
    assert(ads2[0].dishonored_settlement == 102);
    assert(ads2[0].dishonored_reason == "61");
}

fn test_sec_shr() {
    var out: u8[>..] = [];
    assert(sec_build("SHR", 22, 100, 220, "21", "12280000000001", "A", "NY", 2, 0, out)
           == payment_file::F_NONE);
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out, bs, es, ads) == payment_file::F_NONE);
    assert(ads.len == 1);
    assert(ads[0].kind == 2);
    assert(ads[0].ref_one == "REF");
    assert(ads[0].ref_two == "AB");
    assert(ads[0].terminal_id == "TERM01");
    assert(ads[0].serial == "000001");
    assert(ads[0].date_month == 11 && ads[0].date_day == 9);
    assert(ads[0].auth_code == "AUTH01");
    assert(ads[0].location == "1 Main St");
    assert(ads[0].city == "New York");
    assert(ads[0].state == "NY");
    assert(es[0].discretionary == "21");
    assert(es[0].individual_id == "12280000000001");

    // A terminal record whose trace number differs from the entry is a fault.
    var i: i64 = 1;
    while i + 94 < out.len {
        if out[i - 1] == '\n' && out[i] == '7' && out[i + 1] == '0' && out[i + 2] == '2' {
            var k: i64 = 79;
            while k < 94 { out[i + k] = 'X'; k += 1; }
            break;
        }
        i += 1;
    }
    var bs2: payment_file::AchBatch[>..] = [];
    var es2: payment_file::AchEntry[>..] = [];
    var ads2: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out, bs2, es2, ads2) == payment_file::F_TOTAL);
}

fn test_sec_refusals() {
    var out: u8[>..] = [];
    // A COR entry carries an addenda 98.
    assert(sec_build("COR", 21, 0, 220, "", "", "A", "NY", 0, 0, out)
           == payment_file::F_LIMIT);
    // An XCK entry holds at most 2500.00.
    assert(sec_build("XCK", 27, 250001, 225, "", "", "A", "NY", 0, 0, out)
           == payment_file::F_AMOUNT);
    assert(sec_build("XCK", 27, 250000, 225, "", "", "A", "NY", 0, 0, out)
           == payment_file::F_NONE);
    // The count of the addenda of an ATX entry must match.
    assert(sec_build("ATX", 23, 0, 220, "", "", "0002Receiver", "NY", 5, 0, out)
           == payment_file::F_TOTAL);
    // A DNE entry carries one addendum.
    assert(sec_build("DNE", 23, 0, 220, "", "", "A", "NY", 0, 0, out)
           == payment_file::F_LIMIT);
    // A DNE entry holds the code 23 or 33 only.
    assert(sec_build("DNE", 22, 0, 220, "", "", "A", "NY", 5, 0, out)
           == payment_file::F_SYNTAX);
    // A COR entry holds the code 21 or 31 only.
    assert(sec_build("COR", 22, 0, 220, "", "", "A", "NY", 98, 0, out)
           == payment_file::F_SYNTAX);
    // An ACK entry holds the code 23 or 33 only.
    assert(sec_build("ACK", 22, 0, 220, "", "", "A", "NY", 5, 0, out)
           == payment_file::F_SYNTAX);
    // A CIE entry holds a credit code only.
    assert(sec_build("CIE", 27, 100, 220, "", "", "A", "NY", 5, 0, out)
           == payment_file::F_TOTAL);
    // A TRC batch of credits only holds no debit.
    assert(sec_build("TRC", 27, 100, 220, "", "", "A", "NY", 0, 0, out)
           == payment_file::F_TOTAL);
    // A TRC batch of debits only holds no credit.
    assert(sec_build("TRC", 22, 100, 225, "", "", "A", "NY", 0, 0, out)
           == payment_file::F_TOTAL);
    // The card transaction type of a SHR entry is in the card list.
    assert(sec_build("SHR", 22, 100, 220, "44", "12280000000001", "A", "NY", 0, 0, out)
           == payment_file::F_SYNTAX);
    // The card expiration month of a SHR entry is 01 to 12.
    assert(sec_build("SHR", 22, 100, 220, "21", "13280000000001", "A", "NY", 0, 0, out)
           == payment_file::F_DATE);
    // The card expiration year of a SHR entry is 18 to 50.
    assert(sec_build("SHR", 22, 100, 220, "21", "12170000000001", "A", "NY", 0, 0, out)
           == payment_file::F_DATE);
    // The terminal state of a SHR entry is a state of the United
    // States.
    assert(sec_build("SHR", 22, 100, 220, "21", "12280000000001", "A", "ZZ", 2, 0, out)
           == payment_file::F_SYNTAX);
    // The terminal record rides on a SHR entry only.
    assert(sec_build("PPD", 27, 100, 225, "", "", "A", "NY", 2, 0, out)
           == payment_file::F_LIMIT);
    // The plain form of the return takes no dishonored or contested
    // code.
    assert(sec_bad_code(out, 0, "R71") == payment_file::F_SYNTAX);
    assert(sec_bad_code(out, 0, "R61") == payment_file::F_SYNTAX);
    assert(sec_bad_code(out, 0, "R01") == payment_file::F_NONE);
}


fn test_sec_bad_return_codes() {
    var out: u8[>..] = [];
    // The dishonored list holds R61, R62 and R67 to R70.
    assert(sec_bad_code(out, 1, "R71") == payment_file::F_SYNTAX);
    assert(sec_bad_code(out, 1, "R01") == payment_file::F_SYNTAX);
    // The contested list holds R71 to R77.
    assert(sec_bad_code(out, 2, "R70") == payment_file::F_SYNTAX);
    assert(sec_bad_code(out, 2, "R61") == payment_file::F_SYNTAX);
    // A code of the lists is valid.
    assert(sec_bad_code(out, 1, "R61") == payment_file::F_NONE);
    assert(sec_bad_code(out, 2, "R71") == payment_file::F_NONE);
}

// sec_bad_code writes a file with a return addenda of the form and
// the code. The form 1 is the dishonored form and the form 2 the
// contested form.
fn sec_bad_code(out: u8[>..]&, form: i64, code: const u8[:]) -> i32 {
    var entries: payment_file::AchEntry[>..] = [];
    var addenda: payment_file::AchAddenda[>..] = [];
    var e = payment_file::new_ach_entry();
    e.transaction_code = 27;
    e.rdfi_routing = "121140399";
    e.account = "00012345678";
    e.amount = 100;
    e.individual_name = "A";
    e.trace_number = "121140390000001";
    e.addenda_count = 1;
    e.addenda_start = 0;
    entries.push(e);
    var a = payment_file::new_ach_addenda();
    a.kind = 99;
    a.form = form;
    a.return_code = code;
    a.original_trace = "121140390000001";
    a.original_dfi = "12114039";
    if form == 0 {
        a.addenda_information = "info";
    }
    if form == 1 {
        a.return_trace = "121140390000002";
        a.return_settlement = 100;
        a.return_reason = "01";
        a.addenda_information = "info";
    }
    if form == 2 {
        a.date_returned = "260102";
        a.original_settlement = 100;
        a.return_trace = "121140390000002";
        a.return_settlement = 101;
        a.return_reason = "01";
        a.dishonored_trace = "121140390000003";
        a.dishonored_settlement = 102;
        a.dishonored_reason = "61";
    }
    addenda.push(a);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = 225;
    b.company_name = "Acme Corp";
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

fn test_sec_mixed() {
    // A file holds a PPD batch and a TRC batch.
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
    e2.transaction_code = 27;
    e2.rdfi_routing = "121140399";
    e2.account = "00012345678";
    e2.amount = 500;
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
    b1.entry_count = 1;
    batches.push(b1);
    var b2 = payment_file::new_ach_batch();
    b2.service_class = 225;
    b2.company_name = "Acme Corp";
    b2.company_id = "1234567890";
    b2.sec_code = "TRC";
    b2.description = "PAY";
    b2.effective_year = 2026; b2.effective_month = 11; b2.effective_day = 10;
    b2.odfi_id = "12114039";
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
    h.destination_name = "Bank";
    h.origin_name = "Corp";
    var lim = payment_file::default_limits();
    var out: u8[>..] = [];
    assert(payment_file::write_ach(h, batches, entries, addenda, lim, out).kind
           == payment_file::F_NONE);
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out, bs, es, ads) == payment_file::F_NONE);
    assert(bs.len == 2);
    assert(bs[0].sec_code == "PPD" && bs[1].sec_code == "TRC");
    assert(es.len == 2);
    assert(es[0].amount == 10000 && es[1].amount == 500);
}
