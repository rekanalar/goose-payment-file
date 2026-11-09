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

// find_from tells where a pattern sits at or after a position. It
// gives -1 when the pattern is absent.
fn find_from(out: u8[>..]&, pattern: const u8[:], from: i64) -> i64 {
    var i: i64 = from;
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
<PmtInf><PmtInfId>P-8</PmtInfId><PmtMtd>TRF</PmtMtd><ReqdExctnDt>2026-12-01</ReqdExctnDt><Dbtr><Nm>Debtor SA</Nm></Dbtr>
<DbtrAcct><Id><IBAN>ES9121000418450200051332</IBAN></Id></DbtrAcct><DbtrAgt><FinInstnId></FinInstnId></DbtrAgt>
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
<CstmrCdtTrfInitn><GrpHdr><MsgId>M1</MsgId><CreDtTm>2026-11-09T09:00:00</CreDtTm><NbOfTxs>1</NbOfTxs><CtrlSum>99.00</CtrlSum><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P1</PmtInfId><PmtMtd>TRF</PmtMtd><ReqdExctnDt>2026-12-01</ReqdExctnDt><Dbtr><Nm>Debtor</Nm></Dbtr>
<DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct><DbtrAgt><FinInstnId></FinInstnId></DbtrAgt>
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
<CstmrCdtTrfInitn><GrpHdr><MsgId>M1</MsgId><CreDtTm>2026-11-09T09:00:00</CreDtTm><NbOfTxs>1</NbOfTxs><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P1</PmtInfId><PmtMtd>TRF</PmtMtd><ReqdExctnDt>2026-12-01</ReqdExctnDt><Dbtr><Nm>Debtor</Nm></Dbtr>
<DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct><DbtrAgt><FinInstnId></FinInstnId></DbtrAgt>
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
<CstmrCdtTrfInitn><GrpHdr><MsgId>M1</MsgId><CreDtTm>2026-11-09T09:00:00</CreDtTm><NbOfTxs>1</NbOfTxs><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P1</PmtInfId><PmtMtd>TRF</PmtMtd><ReqdExctnDt>2026-12-01</ReqdExctnDt><Dbtr><Nm>Deb*tor</Nm></Dbtr>
<DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct><DbtrAgt><FinInstnId></FinInstnId></DbtrAgt>
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

// party_header gives the group header of the party tests.
fn party_header() -> payment_file::GrpHeader {
    var h = payment_file::new_header();
    h.message_id = "MSG-2026-0001";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.creation_minutes = 14 * 60 + 30; h.creation_offset = 60;
    h.initiator = "Acme Trading Ltd";
    return h;
}

// cat joins three texts into a builder.
fn cat(a: const u8[:], b: const u8[:], c: const u8[:], out: u8[>..]&) {
    put(out, a);
    put(out, b);
    put(out, c);
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
        let pos = find_from(out, order[i], at);
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
<DbtrAgt><FinInstnId></FinInstnId></DbtrAgt><Dbtr><Nm>Deb</Nm></Dbtr><DbtrAcct><Id><IBAN>DE89370400440532013000</IBAN></Id></DbtrAcct>
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

const OLD_OUTPUT: const u8[:] = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:pain.001.001.03\"><CstmrCdtTrfInitn><GrpHdr><MsgId>MSG-2026-0001</MsgId><CreDtTm>2026-11-09T14:30:00+01:00</CreDtTm><NbOfTxs>2</NbOfTxs><CtrlSum>103.00</CtrlSum><InitgPty><Nm>Acme Trading Ltd</Nm></InitgPty></GrpHdr><PmtInf><PmtInfId>PMT-1</PmtInfId><PmtMtd>TRF</PmtMtd><BtchBookg>false</BtchBookg><NbOfTxs>2</NbOfTxs><CtrlSum>103.00</CtrlSum><ReqdExctnDt>2026-12-01</ReqdExctnDt><Dbtr><Nm>Acme Trading Ltd</Nm></Dbtr><DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct><DbtrAgt><FinInstnId></FinInstnId></DbtrAgt><ChrgBr>SLEV</ChrgBr><CdtTrfTxInf><PmtId><InstrId>INSTR-1</InstrId><EndToEndId>E2E-1</EndToEndId></PmtId><Amt><InstdAmt Ccy=\"EUR\">100.50</InstdAmt></Amt><Cdtr><Nm>Creditor One</Nm></Cdtr><CdtrAcct><Id><IBAN>DE89370400440532013000</IBAN></Id></CdtrAcct><RmtInf><Ustrd>Invoice 42</Ustrd></RmtInf></CdtTrfTxInf><CdtTrfTxInf><PmtId><EndToEndId>E2E-2</EndToEndId></PmtId><Amt><InstdAmt Ccy=\"EUR\">2.50</InstdAmt></Amt><Cdtr><Nm>Creditor Two AG</Nm></Cdtr><CdtrAcct><Id><IBAN>CH9300762011623852957</IBAN></Id></CdtrAcct><Purp><Cd>SALA</Cd></Purp><RmtInf><Strd><CdtrRefInf><Ref>RF18539007547034</Ref></CdtrRefInf></Strd></RmtInf></CdtTrfTxInf></PmtInf></CstmrCdtTrfInitn></Document>";

// The party fields of the model. The builder fills every new field of
// the debtor, the creditor and both ultimate parties.
fn party_full_model(pays: payment_file::PaymentInfo[>..]&, items: payment_file::CreditTransfer[>..]&) {
    var a = payment_file::new_address();
    a.department = "Sales";
    a.sub_department = "North";
    a.street_name = "Main Street";
    a.building_number = "12";
    a.post_code = "12345";
    a.town_name = "Amsterdam";
    a.country_subdivision = "Noord-Holland";
    a.country = "NL";
    a.line_1 = "Building A";
    a.line_2 = "Floor 3";
    var o = payment_file::new_other_id();
    o.id = "NL-ORG-1";
    o.scheme_code = "BANK";
    o.issuer = "Acme Bank";
    var pid = payment_file::new_party_id();
    pid.kind = payment_file::PARTY_ORG;
    pid.bic = "ABNANL2A";
    pid.other = o;
    pays[0].debtor_detail.address = a;
    pays[0].debtor_detail.id = pid;
    pays[0].ultimate_debtor_name = "Ultimate Owner Ltd";
    var ua = payment_file::new_address();
    ua.street_name = "Owner Way";
    ua.town_name = "Utrecht";
    ua.country = "NL";
    pays[0].ultimate_debtor_detail.address = ua;
    var uo = payment_file::new_other_id();
    uo.id = "NL-OWNER-9";
    var upid = payment_file::new_party_id();
    upid.kind = payment_file::PARTY_PERSON;
    upid.other = uo;
    pays[0].ultimate_debtor_detail.id = upid;
    items[0].creditor_detail.address = a;
    items[0].creditor_detail.id = pid;
    items[0].ultimate_creditor_name = "Ultimate Payee Inc";
    items[0].ultimate_creditor_detail.address = ua;
    items[0].ultimate_creditor_detail.id = upid;
    items[0].ultimate_debtor_name = "Ultimate Origin Ltd";
    items[0].ultimate_debtor_detail.address = ua;
    items[0].ultimate_debtor_detail.id = upid;
    items[0].structured_type = "SCOR";
    items[0].structured_issuer = "Acme Bank";
    items[0].structured_ref = "RF18539007547034";
}

// party_sample writes a document with every new field set.
fn party_sample(out: u8[>..]&) -> i32 {
    var items: payment_file::CreditTransfer[>..] = [];
    var t1 = payment_file::new_transfer();
    t1.end_to_end_id = "E2E-1";
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
    items.push(t2);
    var pays: payment_file::PaymentInfo[>..] = [];
    var p1 = payment_file::new_payment();
    p1.id = "PMT-1";
    p1.charge_bearer = "SLEV";
    p1.debtor_name = "Acme Trading Ltd";
    p1.debtor_iban = "NL91ABNA0417164300";
    p1.execution_year = 2026; p1.execution_month = 12; p1.execution_day = 1;
    p1.has_execution_date = true;
    p1.item_start = 0;
    p1.item_count = items.len as i32;
    pays.push(p1);
    party_full_model(pays, items);
    var h = payment_file::new_header();
    h.message_id = "MSG-2026-0001";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.creation_minutes = 14 * 60 + 30;
    h.creation_offset = 60;
    h.initiator = "Acme Trading Ltd";
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var lim = payment_file::default_limits();
    return payment_file::write_pain001(h, pays, items, wopts, lim, out).kind;
}

// party_read reads a document and gives the fault kind.
fn party_read(doc: const u8[:], pays: payment_file::PaymentInfo[>..]&,
              items: payment_file::CreditTransfer[>..]&, buf: u8[>..]&) -> i32 {
    var h = payment_file::new_header();
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var lim = payment_file::default_limits();
    return payment_file::parse_pain001(doc, lim, ropts, h, pays, items, buf).kind;
}

// The new fields survive a write and a read.
fn test_party_roundtrip() {
    var out: u8[>..] = [];
    assert(party_sample(out) == 0);
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    assert(party_read(out[..], pays, items, buf) == 0);
    assert(pays.len == 1 && items.len == 2);
    let a = pays[0].debtor_detail.address;
    assert(a.department == "Sales" && a.sub_department == "North");
    assert(a.street_name == "Main Street" && a.building_number == "12");
    assert(a.post_code == "12345" && a.town_name == "Amsterdam");
    assert(a.country_subdivision == "Noord-Holland" && a.country == "NL");
    assert(a.line_1 == "Building A" && a.line_2 == "Floor 3");
    let pid = pays[0].debtor_detail.id;
    assert(pid.kind == payment_file::PARTY_ORG && pid.bic == "ABNANL2A");
    assert(pid.other.id == "NL-ORG-1" && pid.other.scheme_code == "BANK");
    assert(pid.other.issuer == "Acme Bank");
    assert(pays[0].ultimate_debtor_name == "Ultimate Owner Ltd");
    assert(pays[0].ultimate_debtor_detail.address.town_name == "Utrecht");
    assert(pays[0].ultimate_debtor_detail.id.kind == payment_file::PARTY_PERSON);
    assert(pays[0].ultimate_debtor_detail.id.other.id == "NL-OWNER-9");
    assert(items[0].creditor_detail.address.country == "NL");
    assert(items[0].ultimate_creditor_name == "Ultimate Payee Inc");
    assert(items[0].ultimate_creditor_detail.address.street_name == "Owner Way");
    assert(items[0].ultimate_debtor_name == "Ultimate Origin Ltd");
    assert(items[0].ultimate_debtor_detail.address.country == "NL");
    assert(items[0].structured_type == "SCOR" && items[0].structured_issuer == "Acme Bank");
    assert(items[0].structured_ref == "RF18539007547034");
    // The unstructured and the structured remittance sit together.
    assert(items[0].remittance == "Invoice 42");
    // An item without the new fields holds nothing.
    assert(items[1].ultimate_creditor_name.len == 0);
    assert(items[1].creditor_detail.id.kind == payment_file::PARTY_NONE);
}

// A file with many parties and many items keeps every text valid. The
// texts of the reader point into one buffer. The buffer must grow
// without moving the texts.
fn test_party_many() {
    var items: payment_file::CreditTransfer[>..] = [];
    var i: i64 = 0;
    while i < 200 {
        var t = payment_file::new_transfer();
        t.end_to_end_id = "E2E-LONG";
        let m, ok = finance::money(100 + i, "EUR");
        assert(ok);
        t.amount = m;
        t.creditor_name = "Creditor Number";
        t.creditor_iban = "DE89370400440532013000";
        t.remittance = "Invoice with a long text 1234567890";
        items.push(t);
        i += 1;
    }
    var pays: payment_file::PaymentInfo[>..] = [];
    var p = payment_file::new_payment();
    p.id = "PMT-1";
    p.debtor_name = "Acme Trading Ltd";
    p.debtor_iban = "NL91ABNA0417164300";
    p.execution_year = 2026; p.execution_month = 12; p.execution_day = 1;
    p.has_execution_date = true;
    p.item_start = 0;
    p.item_count = items.len as i32;
    pays.push(p);
    var a = payment_file::new_address();
    a.street_name = "Main Street";
    a.town_name = "Amsterdam";
    a.country = "NL";
    p.debtor_detail.address = a;
    pays[0].debtor_detail.address = a;
    var h = party_header();
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var lim = payment_file::default_limits();
    var out: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, out).kind == 0);
    var rp: payment_file::PaymentInfo[>..] = [];
    var ri: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    assert(party_read(out[..], rp, ri, buf) == 0);
    assert(rp.len == 1 && ri.len == 200);
    assert(rp[0].debtor_detail.address.town_name == "Amsterdam");
    var k: i64 = 0;
    while k < 200 {
        assert(ri[k].end_to_end_id == "E2E-LONG");
        assert(ri[k].creditor_name == "Creditor Number");
        assert(ri[k].remittance == "Invoice with a long text 1234567890");
        k += 1;
    }
}

// The elements follow the order of the schema.
fn test_party_order() {
    var out: u8[>..] = [];
    assert(party_sample(out) == 0);
    // The debtor: the name, the address, the identification.
    let dbtr = find(out, "<Dbtr>");
    assert(dbtr >= 0);
    let nm = find(out, "<Dbtr><Nm>");
    let adr = find(out, "<PstlAdr>");
    let id = find(out, "<Dbtr><Nm>Acme Trading Ltd</Nm><PstlAdr>");
    assert(nm >= 0 && adr > nm && id >= 0);
    // The ultimate debtor of the block sits after the debtor agent.
    assert(find(out, "<DbtrAgt>") < find(out, "<UltmtDbtr>"));
    assert(find(out, "<UltmtDbtr>") < find(out, "<ChrgBr>"));
    // The ultimate creditor of the item sits after the creditor account.
    assert(find(out, "<CdtrAcct>") < find(out, "<UltmtCdtr>"));
    assert(find(out, "<UltmtCdtr>") < find(out, "<RmtInf>"));
    // The type of the creditor reference sits before the reference.
    assert(find(out, "<Tp><CdOrPrtry><Cd>SCOR</Cd></CdOrPrtry><Issr>Acme Bank</Issr></Tp>") >= 0);
    assert(find(out, "<CdtrRefInf><Tp><CdOrPrtry><Cd>SCOR</Cd></CdOrPrtry><Issr>Acme Bank</Issr></Tp><Ref>RF18539007547034</Ref></CdtrRefInf>") >= 0);
    // The address holds its fields in the order of the schema.
    let adr2 = find(out, "<PstlAdr>");
    let dept = find(out, "<Dept>");
    let st = find(out, "<StrtNm>");
    let ctry = find(out, "<Ctry>");
    let line = find(out, "<AdrLine>");
    assert(dept > adr2 && st > dept && ctry > st && line > ctry);
}

// A model without the new fields writes the same bytes as before, save
// for the payment type block that the writer now writes.
fn test_party_old_output() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: false, indent: false };
    assert(sample(wopts, out) == 0);
    var stripped: u8[>..] = [];
    replace_all(out, "<PmtTpInf><SvcLvl><Cd>SEPA</Cd></SvcLvl></PmtTpInf>", "", stripped);
    assert(stripped[..] == OLD_OUTPUT);
}

// A text one byte over its limit is a fault on both sides.
fn test_party_overlength() {
    var long70: u8[>..] = [];
    var i: i64 = 0;
    while i < 71 { long70.push('A'); i += 1; }
    let l70 = long70[..];
    var long35: u8[>..] = [];
    i = 0;
    while i < 36 { long35.push('B'); i += 1; }
    let l35 = long35[..];
    var long16: u8[>..] = [];
    i = 0;
    while i < 17 { long16.push('C'); i += 1; }
    let l16 = long16[..];
    var long4: u8[>..] = [];
    i = 0;
    while i < 5 { long4.push('D'); i += 1; }
    let l4 = long4[..];
    // The street name of the debtor.
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var out: u8[>..] = [];
    assert(party_sample(out) == 0);
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var lim = payment_file::default_limits();
    var h = party_header();
    // The writer refuses a long street name.
    var a = payment_file::new_address();
    a.street_name = l70;
    a.country = "NL";
    pays.push(payment_file::new_payment());
    pays[0].id = "PMT-1";
    pays[0].debtor_name = "Acme Trading Ltd";
    pays[0].debtor_iban = "NL91ABNA0417164300";
    pays[0].debtor_detail.address = a;
    pays[0].execution_year = 2026; pays[0].execution_month = 12; pays[0].execution_day = 1;
    pays[0].has_execution_date = true;
    var t = payment_file::new_transfer();
    t.end_to_end_id = "E2E-1";
    let m, ok = finance::money(100, "EUR");
    assert(ok);
    t.amount = m;
    t.creditor_name = "Creditor One";
    t.creditor_iban = "DE89370400440532013000";
    items.push(t);
    pays[0].item_start = 0;
    pays[0].item_count = 1;
    var o1: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o1).kind == payment_file::F_LIMIT);
    assert(o1.len == 0);
    // The reader refuses a long street name.
    var doc: u8[>..] = [];
    var pat: u8[>..] = [];
    cat("<StrtNm>", l70, "</StrtNm>", pat);
    replace_all(out, "<StrtNm>Main Street</StrtNm>", pat[..], doc);
    var rp: payment_file::PaymentInfo[>..] = [];
    var ri: payment_file::CreditTransfer[>..] = [];
    var rbuf: u8[>..] = [];
    assert(party_read(doc[..], rp, ri, rbuf) == payment_file::F_LIMIT);
    // The writer refuses a long town name, a long building number and a long scheme code.
    var a2 = payment_file::new_address();
    a2.town_name = l35;
    pays[0].debtor_detail.address = a2;
    var o2: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o2).kind == payment_file::F_LIMIT);
    assert(o2.len == 0);
    var a3 = payment_file::new_address();
    a3.building_number = l16;
    pays[0].debtor_detail.address = a3;
    var o3: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o3).kind == payment_file::F_LIMIT);
    assert(o3.len == 0);
    var o4 = payment_file::new_other_id();
    o4.id = "X";
    o4.scheme_code = l4;
    var pid = payment_file::new_party_id();
    pid.kind = payment_file::PARTY_ORG;
    pid.other = o4;
    pays[0].debtor_detail.address = payment_file::new_address();
    pays[0].debtor_detail.id = pid;
    var o5: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o5).kind == payment_file::F_LIMIT);
    assert(o5.len == 0);
}

// The texts are escaped and the EPC set holds them.
fn test_party_escape() {
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var out: u8[>..] = [];
    assert(party_sample(out) == 0);
    var a = payment_file::new_address();
    a.street_name = "Main <Street> & Co";
    pays.push(payment_file::new_payment());
    pays[0].id = "PMT-1";
    pays[0].debtor_name = "Acme Trading Ltd";
    pays[0].debtor_iban = "NL91ABNA0417164300";
    pays[0].debtor_detail.address = a;
    pays[0].execution_year = 2026; pays[0].execution_month = 12; pays[0].execution_day = 1;
    pays[0].has_execution_date = true;
    var t = payment_file::new_transfer();
    t.end_to_end_id = "E2E-1";
    let m, ok = finance::money(100, "EUR");
    assert(ok);
    t.amount = m;
    t.creditor_name = "Creditor One";
    t.creditor_iban = "DE89370400440532013000";
    items.push(t);
    pays[0].item_start = 0;
    pays[0].item_count = 1;
    var h = party_header();
    var lim = payment_file::default_limits();
    // Without the EPC set the markup characters are escaped.
    var wopts = payment_file::PainWriteOptions { epc_charset: false, indent: false };
    var o1: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o1).kind == 0);
    assert(find(o1, "<StrtNm>Main &lt;Street&gt; &amp; Co</StrtNm>") >= 0);
    // With the EPC set the same text is refused.
    var wopts2 = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var o2: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts2, lim, o2).kind == payment_file::F_CHARSET);
    assert(o2.len == 0);
}

// The reader and the writer refuse the same bad values.
fn test_party_refusals() {
    var out: u8[>..] = [];
    assert(party_sample(out) == 0);
    var rp: payment_file::PaymentInfo[>..] = [];
    var ri: payment_file::CreditTransfer[>..] = [];
    var rbuf: u8[>..] = [];
    // A lowercase country is a fault on both sides.
    var doc: u8[>..] = [];
    replace_all(out, "<Ctry>NL</Ctry>", "<Ctry>nl</Ctry>", doc);
    assert(party_read(doc[..], rp, ri, rbuf) == payment_file::F_SYNTAX);
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var lim = payment_file::default_limits();
    var h = party_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var t = payment_file::new_transfer();
    t.end_to_end_id = "E2E-1";
    let m, ok = finance::money(100, "EUR");
    assert(ok);
    t.amount = m;
    t.creditor_name = "Creditor One";
    t.creditor_iban = "DE89370400440532013000";
    items.push(t);
    pays.push(payment_file::new_payment());
    pays[0].id = "PMT-1";
    pays[0].debtor_name = "Acme Trading Ltd";
    pays[0].debtor_iban = "NL91ABNA0417164300";
    pays[0].execution_year = 2026; pays[0].execution_month = 12; pays[0].execution_day = 1;
    pays[0].has_execution_date = true;
    pays[0].item_start = 0;
    pays[0].item_count = 1;
    var a = payment_file::new_address();
    a.country = "nl";
    pays[0].debtor_detail.address = a;
    var o1: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o1).kind == payment_file::F_SYNTAX);
    assert(o1.len == 0);
    // An unknown document type is a fault on both sides.
    pays[0].debtor_detail.address = payment_file::new_address();
    var doc2: u8[>..] = [];
    replace_all(out, "<Cd>SCOR</Cd>", "<Cd>XXXX</Cd>", doc2);
    assert(party_read(doc2[..], rp, ri, rbuf) == payment_file::F_SYNTAX);
    items[0].structured_type = "XXXX";
    var o2: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o2).kind == payment_file::F_SYNTAX);
    assert(o2.len == 0);
    items[0].structured_type = "SCOR";
    // An identification of an unknown kind is a fault.
    var o3 = payment_file::new_other_id();
    o3.id = "X";
    var pid = payment_file::new_party_id();
    pid.kind = 7;
    pid.other = o3;
    pays[0].debtor_detail.id = pid;
    items[0].structured_type = "";
    var o4: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o4).kind == payment_file::F_SYNTAX);
    assert(o4.len == 0);
    // An ultimate party with an address and no name is a fault.
    pays[0].debtor_detail.id = payment_file::new_party_id();
    var a2 = payment_file::new_address();
    a2.country = "NL";
    pays[0].ultimate_debtor_detail.address = a2;
    var o5: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o5).kind == payment_file::F_SYNTAX);
    assert(o5.len == 0);
    pays[0].ultimate_debtor_detail = payment_file::new_party_detail();
    // A scheme that holds a code and a proprietary text is a fault.
    var o6 = payment_file::new_other_id();
    o6.id = "X";
    o6.scheme_code = "BANK";
    o6.scheme_proprietary = "Other";
    var pid2 = payment_file::new_party_id();
    pid2.kind = payment_file::PARTY_ORG;
    pid2.other = o6;
    pays[0].debtor_detail.id = pid2;
    var o7: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o7).kind == payment_file::F_SYNTAX);
    assert(o7.len == 0);
    // The reader refuses a scheme that holds both.
    var doc3: u8[>..] = [];
    replace_all(out, "<SchmeNm><Cd>BANK</Cd></SchmeNm>", "<SchmeNm><Cd>BANK</Cd><Prtry>Other</Prtry></SchmeNm>", doc3);
    assert(party_read(doc3[..], rp, ri, rbuf) == payment_file::F_SYNTAX);
    // The reader refuses a party that holds both kinds.
    var doc4: u8[>..] = [];
    replace_all(out, "<PrvtId>", "<OrgId><Othr><Id>Z</Id></Othr></OrgId><PrvtId>", doc4);
    assert(party_read(doc4[..], rp, ri, rbuf) == payment_file::F_SYNTAX);
    // The reader refuses a second other identifier.
    var doc5: u8[>..] = [];
    replace_all(out, "<Othr><Id>NL-ORG-1</Id>", "<Othr><Id>NL-ORG-1</Id></Othr><Othr><Id>NL-ORG-2</Id>", doc5);
    assert(party_read(doc5[..], rp, ri, rbuf) == payment_file::F_LIMIT);
    // The reader refuses a third address line.
    var doc6: u8[>..] = [];
    replace_all(out, "<AdrLine>Building A</AdrLine><AdrLine>Floor 3</AdrLine>", "<AdrLine>One</AdrLine><AdrLine>Two</AdrLine><AdrLine>Three</AdrLine>", doc6);
    assert(party_read(doc6[..], rp, ri, rbuf) == payment_file::F_LIMIT);
    // The reader refuses a BIC that is not a BIC.
    var doc7: u8[>..] = [];
    replace_all(out, "<BICOrBEI>ABNANL2A</BICOrBEI>", "<BICOrBEI>abnanl2a</BICOrBEI>", doc7);
    assert(party_read(doc7[..], rp, ri, rbuf) == payment_file::F_SYNTAX);
    // An ultimate party with an address and no name is a fault on both sides.
    var doc8: u8[>..] = [];
    replace_all(out, "<UltmtDbtr><Nm>Ultimate Owner Ltd</Nm>", "<UltmtDbtr>", doc8);
    assert(party_read(doc8[..], rp, ri, rbuf) == payment_file::F_SYNTAX);
    pays[0].ultimate_debtor_name = "";
    pays[0].ultimate_debtor_detail.address = a;
    var o8: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o8).kind == payment_file::F_SYNTAX);
    assert(o8.len == 0);
    // An identification that holds nothing is a fault on both sides.
    var doc9: u8[>..] = [];
    replace_all(out, "<Id><OrgId><BICOrBEI>ABNANL2A</BICOrBEI><Othr><Id>NL-ORG-1</Id><SchmeNm><Cd>BANK</Cd></SchmeNm><Issr>Acme Bank</Issr></Othr></OrgId></Id>",
               "<Id><OrgId></OrgId></Id>", doc9);
    assert(party_read(doc9[..], rp, ri, rbuf) == payment_file::F_SYNTAX);
    var o9 = payment_file::new_other_id();
    var pid3 = payment_file::new_party_id();
    pid3.kind = payment_file::PARTY_ORG;
    pid3.other = o9;
    pays[0].debtor_detail.id = pid3;
    var o9b: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o9b).kind == payment_file::F_SYNTAX);
    assert(o9b.len == 0);
    // An other identifier with no id is a fault on both sides.
    var doc10: u8[>..] = [];
    replace_all(out, "<Othr><Id>NL-ORG-1</Id><SchmeNm><Cd>BANK</Cd></SchmeNm><Issr>Acme Bank</Issr></Othr>",
               "<Othr><Issr>Acme Bank</Issr></Othr>", doc10);
    assert(party_read(doc10[..], rp, ri, rbuf) == payment_file::F_SYNTAX);
    var o10 = payment_file::new_other_id();
    o10.issuer = "Acme Bank";
    var pid4 = payment_file::new_party_id();
    pid4.kind = payment_file::PARTY_ORG;
    pid4.other = o10;
    pays[0].debtor_detail.id = pid4;
    var o10b: u8[>..] = [];
    assert(payment_file::write_pain001(h, pays, items, wopts, lim, o10b).kind == payment_file::F_SYNTAX);
    assert(o10b.len == 0);
}

// sample_debit_full builds a debit with every party field set: the
// addresses, the identifications, the ultimate parties, the purpose
// and the typed creditor reference.
fn sample_debit_full(opts: payment_file::PainWriteOptions, out: u8[>..]&) -> i32 {
    var items: payment_file::DirectDebit[>..] = [];
    var t = payment_file::new_direct_debit();
    t.end_to_end_id = "E2E-P1";
    let m, ok = finance::money(1000, "EUR");
    if !ok { return -1; }
    t.amount = m;
    t.mandate_id = "MANDATE-P1";
    t.signature_year = 2025; t.signature_month = 6; t.signature_day = 1;
    t.has_signature_date = true;
    t.debtor_name = "Debtor Full";
    t.debtor_iban = "DE89370400440532013000";
    t.debtor_detail.address.town_name = "Berlin";
    t.debtor_detail.address.country = "DE";
    t.debtor_detail.address.line_1 = "Torstrasse 10";
    t.debtor_detail.id.kind = payment_file::PARTY_PERSON;
    t.debtor_detail.id.other.id = "P-4711";
    t.debtor_detail.id.other.issuer = "Registry";
    t.ultimate_creditor_name = "Rent Holder";
    t.ultimate_creditor_detail.id.kind = payment_file::PARTY_ORG;
    t.ultimate_creditor_detail.id.bic = "ABNANL2A";
    t.ultimate_debtor_name = "Original Payer";
    t.ultimate_debtor_detail.address.country = "DE";
    t.purpose = "GDDS";
    t.remittance = "Rent June";
    t.structured_type = "SCOR";
    t.structured_issuer = "Issuer One";
    t.structured_ref = "RF18539007547034";
    items.push(t);
    var blocks: payment_file::DebitInfo[>..] = [];
    var b = payment_file::new_debit_info();
    b.id = "DD-P1";
    b.creditor_name = "Club Treasurer";
    b.creditor_iban = "NL91ABNA0417164300";
    b.creditor_bic = "ABNANL2A";
    b.creditor_detail.address.town_name = "Amsterdam";
    b.creditor_detail.address.street_name = "Dam";
    b.creditor_detail.address.building_number = "1";
    b.creditor_detail.address.post_code = "1012";
    b.creditor_detail.address.country = "NL";
    b.creditor_detail.id.kind = payment_file::PARTY_ORG;
    b.creditor_detail.id.other.id = "NL-REG-123";
    b.creditor_detail.id.other.issuer = "KVK";
    b.ultimate_creditor_name = "Ultimate Club";
    b.ultimate_creditor_detail.address.town_name = "Utrecht";
    b.ultimate_creditor_detail.address.country = "NL";
    b.ultimate_creditor_detail.id.kind = payment_file::PARTY_ORG;
    b.ultimate_creditor_detail.id.other.id = "UC-1";
    b.scheme_id = "DE98ZZZ09999999999";
    b.charge_bearer = "SLEV";
    b.seq_type = "RCUR";
    b.instrument = "CORE";
    b.collection_year = 2026; b.collection_month = 12; b.collection_day = 1;
    b.has_collection_date = true;
    b.item_count = 1;
    blocks.push(b);
    var h = payment_file::new_header();
    h.message_id = "DD-MSG-P1";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.creation_minutes = 9 * 60;
    h.initiator = "Club Treasurer";
    var lim = payment_file::default_limits();
    let f = payment_file::write_pain008(h, blocks, items, opts, lim, out);
    return f.kind;
}

fn test_debit_parties_round_trip() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample_debit_full(wopts, out) == 0);
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var lim = payment_file::default_limits();
    var h = payment_file::new_header();
    var blocks: payment_file::DebitInfo[>..] = [];
    var items: payment_file::DirectDebit[>..] = [];
    var buf: u8[>..] = [];
    let r = payment_file::parse_pain008(out, lim, ropts, h, blocks, items, buf);
    if r.kind != 0 { print("FAIL debit parties read ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == payment_file::F_NONE);
    assert(blocks.len == 1 && items.len == 1);
    let ca = blocks[0].creditor_detail.address;
    assert(ca.town_name == "Amsterdam" && ca.street_name == "Dam");
    assert(ca.building_number == "1" && ca.post_code == "1012" && ca.country == "NL");
    let cid = blocks[0].creditor_detail.id;
    assert(cid.kind == payment_file::PARTY_ORG && cid.bic.len == 0);
    assert(cid.other.id == "NL-REG-123" && cid.other.issuer == "KVK");
    assert(blocks[0].ultimate_creditor_name == "Ultimate Club");
    assert(blocks[0].ultimate_creditor_detail.address.town_name == "Utrecht");
    assert(blocks[0].ultimate_creditor_detail.address.country == "NL");
    assert(blocks[0].ultimate_creditor_detail.id.other.id == "UC-1");
    let da = items[0].debtor_detail.address;
    assert(da.town_name == "Berlin" && da.country == "DE" && da.line_1 == "Torstrasse 10");
    let did = items[0].debtor_detail.id;
    assert(did.kind == payment_file::PARTY_PERSON && did.other.id == "P-4711");
    assert(did.other.issuer == "Registry");
    assert(items[0].ultimate_creditor_name == "Rent Holder");
    assert(items[0].ultimate_creditor_detail.id.kind == payment_file::PARTY_ORG);
    assert(items[0].ultimate_creditor_detail.id.bic == "ABNANL2A");
    assert(items[0].ultimate_debtor_name == "Original Payer");
    assert(items[0].ultimate_debtor_detail.address.country == "DE");
    assert(items[0].purpose == "GDDS");
    assert(items[0].remittance == "Rent June");
    assert(items[0].structured_type == "SCOR");
    assert(items[0].structured_issuer == "Issuer One");
    assert(items[0].structured_ref == "RF18539007547034");
}

fn test_debit_parties_order() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample_debit_full(wopts, out) == 0);
    // The schema is a sequence: the block ultimate creditor sits
    // between the agent and the charge bearer. The item ultimate
    // creditor sits after the mandate, the ultimate debtor and the
    // purpose sit before the remittance.
    let order = ["<Cdtr>", "<PstlAdr>", "<TwnNm>", "<Ctry>", "<Id>", "<OrgId>", "<Othr>", "</Cdtr>",
                 "<CdtrAcct>", "<CdtrAgt>", "<UltmtCdtr>", "<ChrgBr>", "<CdtrSchmeId>", "<DrctDbtTxInf>",
                 "<PmtId>", "<InstdAmt", "<DrctDbtTx>", "</DrctDbtTx>", "<UltmtCdtr>", "<DbtrAgt>",
                 "<Dbtr>", "<PstlAdr>", "<PrvtId>", "<Othr>", "</Dbtr>", "<DbtrAcct>", "<UltmtDbtr>",
                 "<Purp>", "<Cd>GDDS</Cd>", "</Purp>", "<RmtInf>", "<Ustrd>", "<Strd>", "<CdtrRefInf>",
                 "<Cd>SCOR</Cd>", "<Issr>", "<Ref>", "</RmtInf>"];
    var at: i64 = find(out, "<PmtInf>");
    var i: i64 = 0;
    while i < order.len {
        let pos = find_from(out, order[i], at);
        if pos < at { print("FAIL order at ", order[i], "\n"); }
        assert(pos >= at);
        at = pos;
        i += 1;
    }
}

fn test_anybic_and_lei() {
    var lim = payment_file::default_limits();
    var ropts = payment_file::PainOptions { skip_control_sum_check: true, check_iban: true, epc_charset: true };
    // A later pain.001 file names the BIC AnyBIC. The reader takes it.
    let tpl = """
<?xml version="1.0"?><Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.09">
<CstmrCdtTrfInitn><GrpHdr><MsgId>M1</MsgId><CreDtTm>2026-11-09T09:00:00</CreDtTm><NbOfTxs>1</NbOfTxs><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P1</PmtInfId><PmtMtd>TRF</PmtMtd><ReqdExctnDt>2026-12-01</ReqdExctnDt><Dbtr><Nm>Debtor</Nm><Id><OrgId><AnyBIC>ABNANL2A</AnyBIC></OrgId></Id></Dbtr>
<DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct><DbtrAgt><FinInstnId></FinInstnId></DbtrAgt>
<CdtTrfTxInf><PmtId><EndToEndId>E1</EndToEndId></PmtId><Amt><InstdAmt Ccy="EUR">1.00</InstdAmt></Amt>
<Cdtr><Nm>Cred</Nm></Cdtr><CdtrAcct><Id><IBAN>BE68539007547034</IBAN></Id></CdtrAcct></CdtTrfTxInf>
</PmtInf></CstmrCdtTrfInitn></Document>
""";
    var h = payment_file::new_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    let r1 = payment_file::parse_pain001(tpl, lim, ropts, h, pays, items, buf);
    if r1.kind != 0 { print("FAIL anybic ", payment_file::kind_name(r1.kind), " ", r1.tag, " ", r1.detail, "\n"); }
    assert(r1.kind == payment_file::F_NONE);
    assert(pays[0].debtor_detail.id.bic == "ABNANL2A");
    assert(pays[0].debtor_detail.id.lei.len == 0);
    // An identification that holds only an LEI passes.
    var base: u8[>..] = [];
    put(base, tpl);
    var lei_doc: u8[>..] = [];
    replace_all(base, "<AnyBIC>ABNANL2A</AnyBIC>", "<LEI>5493001KJTIIGC8Y1R12</LEI>", lei_doc);
    var h2 = payment_file::new_header();
    var pays2: payment_file::PaymentInfo[>..] = [];
    var items2: payment_file::CreditTransfer[>..] = [];
    var buf2: u8[>..] = [];
    let r2 = payment_file::parse_pain001(lei_doc, lim, ropts, h2, pays2, items2, buf2);
    if r2.kind != 0 { print("FAIL lei ", payment_file::kind_name(r2.kind), " ", r2.tag, " ", r2.detail, "\n"); }
    assert(r2.kind == payment_file::F_NONE);
    assert(pays2[0].debtor_detail.id.lei == "5493001KJTIIGC8Y1R12");
    // Two BIC names in one identification is a fault.
    var two_bics: u8[>..] = [];
    put(two_bics, tpl);
    var two_doc: u8[>..] = [];
    replace_all(two_bics, "<AnyBIC>ABNANL2A</AnyBIC>",
                "<BICOrBEI>ABNANL2A</BICOrBEI><AnyBIC>ABNANL2A</AnyBIC>", two_doc);
    var h4 = payment_file::new_header();
    var pays4: payment_file::PaymentInfo[>..] = [];
    var items4: payment_file::CreditTransfer[>..] = [];
    var buf4: u8[>..] = [];
    let r4 = payment_file::parse_pain001(two_doc, lim, ropts, h4, pays4, items4, buf4);
    assert(r4.kind == payment_file::F_SYNTAX);
    // A broken LEI faults.
    var lei_bad: u8[>..] = [];
    replace_all(base, "<AnyBIC>ABNANL2A</AnyBIC>", "<LEI>5493001KJTIIGC8Y1R1X</LEI>", lei_bad);
    var h3 = payment_file::new_header();
    var pays3: payment_file::PaymentInfo[>..] = [];
    var items3: payment_file::CreditTransfer[>..] = [];
    var buf3: u8[>..] = [];
    let r3 = payment_file::parse_pain001(lei_bad, lim, ropts, h3, pays3, items3, buf3);
    assert(r3.kind == payment_file::F_SYNTAX);
    // The writer refuses a model that holds an LEI, and leaves the
    // buffer of the caller untouched.
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample_debit(wopts, out) == 0);
    var items4: payment_file::DirectDebit[>..] = [];
    var t = payment_file::new_direct_debit();
    t.end_to_end_id = "E1";
    let m, ok = finance::money(100, "EUR");
    assert(ok);
    t.amount = m;
    t.mandate_id = "M1";
    t.signature_year = 2025; t.signature_month = 2; t.signature_day = 3;
    t.has_signature_date = true;
    t.debtor_name = "D";
    t.debtor_iban = "DE89370400440532013000";
    t.ultimate_creditor_name = "U";
    t.ultimate_creditor_detail.id.kind = payment_file::PARTY_ORG;
    t.ultimate_creditor_detail.id.lei = "5493001KJTIIGC8Y1R12";
    items4.push(t);
    var blocks: payment_file::DebitInfo[>..] = [];
    var bl = payment_file::new_debit_info();
    bl.id = "B1"; bl.creditor_name = "C"; bl.creditor_iban = "NL91ABNA0417164300";
    bl.scheme_id = "DE98ZZZ09999999999"; bl.seq_type = "FRST"; bl.instrument = "CORE";
    bl.collection_year = 2026; bl.collection_month = 12; bl.collection_day = 1;
    bl.has_collection_date = true;
    bl.item_count = 1;
    blocks.push(bl);
    var h4 = payment_file::new_header();
    h4.message_id = "M"; h4.initiator = "I"; h4.has_creation = true;
    h4.creation_year = 2026; h4.creation_month = 11; h4.creation_day = 9;
    var lim4 = payment_file::default_limits();
    let w = payment_file::write_pain008(h4, blocks, items4, wopts, lim4, out);
    assert(w.kind == payment_file::F_SYNTAX);
    assert(find(out, "5493001KJTIIGC8Y1R12") < 0);
}

fn test_debit_write_atomic() {
    // A buffer with old bytes keeps them when a fault stops the write.
    var out: u8[>..] = [];
    out.push('O'); out.push('L'); out.push('D');
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var items: payment_file::DirectDebit[>..] = [];
    var t = payment_file::new_direct_debit();
    t.end_to_end_id = "E1";
    let m, ok = finance::money(100, "EUR");
    assert(ok);
    t.amount = m;
    t.mandate_id = "M1";
    t.signature_year = 2025; t.signature_month = 2; t.signature_day = 3;
    t.has_signature_date = true;
    t.debtor_name = "D";
    t.debtor_iban = "DE89370400440532013000";
    t.ultimate_debtor_detail.address.country = "DE";
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
    var lim = payment_file::default_limits();
    // An ultimate party with an address and no name is a fault.
    let w1 = payment_file::write_pain008(h, blocks, items, wopts, lim, out);
    assert(w1.kind == payment_file::F_SYNTAX);
    assert(out.len == 3 && out[0] == 'O');
    // A text above its limit is a fault too.
    var items2: payment_file::DirectDebit[>..] = [];
    var t2 = payment_file::new_direct_debit();
    t2.end_to_end_id = "E1";
    let m2, ok2 = finance::money(100, "EUR");
    assert(ok2);
    t2.amount = m2;
    t2.mandate_id = "M1";
    t2.signature_year = 2025; t2.signature_month = 2; t2.signature_day = 3;
    t2.has_signature_date = true;
    t2.debtor_name = "D";
    t2.debtor_iban = "DE89370400440532013000";
    t2.ultimate_creditor_name = "This ultimate creditor name is far longer than seventy characters for the test of the limit check";
    items2.push(t2);
    let w2 = payment_file::write_pain008(h, blocks, items2, wopts, lim, out);
    assert(w2.kind != payment_file::F_NONE);
    assert(out.len == 3 && out[0] == 'O');
    // A reference type with an issuer and no code is a fault. The
    // schema makes the code element required in the type.
    var items3: payment_file::DirectDebit[>..] = [];
    var t3 = payment_file::new_direct_debit();
    t3.end_to_end_id = "E1";
    let m3, ok3 = finance::money(100, "EUR");
    assert(ok3);
    t3.amount = m3;
    t3.mandate_id = "M1";
    t3.signature_year = 2025; t3.signature_month = 2; t3.signature_day = 3;
    t3.has_signature_date = true;
    t3.debtor_name = "D";
    t3.debtor_iban = "DE89370400440532013000";
    t3.structured_issuer = "Issuer One";
    t3.structured_ref = "RF18539007547034";
    items3.push(t3);
    let w3 = payment_file::write_pain008(h, blocks, items3, wopts, lim, out);
    assert(w3.kind == payment_file::F_SYNTAX);
    assert(out.len == 3 && out[0] == 'O');
}

fn test_debit_empty_names() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample_debit(wopts, out) == 0);
    var lim = payment_file::default_limits();
    var a: u8[>..] = [];
    replace_all(out, "<Cdtr><Nm>Club Treasurer</Nm>", "<Cdtr><Nm></Nm>", a);
    assert(read_debit_kind(a, false, lim) == payment_file::F_SYNTAX);
    var b: u8[>..] = [];
    replace_all(out, "<Dbtr><Nm>Debtor One</Nm>", "<Dbtr><Nm></Nm>", b);
    assert(read_debit_kind(b, false, lim) == payment_file::F_SYNTAX);
}

fn test_debit_old_model_bytes() {
    // The bytes of a debit without the new fields match the bytes of
    // the last release, captured by hand from that release.
    let full = """
<?xml version="1.0" encoding="UTF-8"?><Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.008.001.02"><CstmrDrctDbtInitn><GrpHdr><MsgId>DD-MSG-1</MsgId><CreDtTm>2026-11-09T09:00:00</CreDtTm><NbOfTxs>2</NbOfTxs><CtrlSum>35.50</CtrlSum><InitgPty><Nm>Club Treasurer</Nm></InitgPty></GrpHdr><PmtInf><PmtInfId>DD-1</PmtInfId><PmtMtd>DD</PmtMtd><NbOfTxs>2</NbOfTxs><CtrlSum>35.50</CtrlSum><PmtTpInf><SvcLvl><Cd>SEPA</Cd></SvcLvl><LclInstrm><Cd>CORE</Cd></LclInstrm><SeqTp>RCUR</SeqTp></PmtTpInf><ReqdColltnDt>2026-12-01</ReqdColltnDt><Cdtr><Nm>Club Treasurer</Nm></Cdtr><CdtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></CdtrAcct><CdtrAgt><FinInstnId><BIC>ABNANL2A</BIC></FinInstnId></CdtrAgt><ChrgBr>SLEV</ChrgBr><CdtrSchmeId><Id><PrvtId><Othr><Id>DE98ZZZ09999999999</Id><SchmeNm><Prtry>SEPA</Prtry></SchmeNm></Othr></PrvtId></Id></CdtrSchmeId><DrctDbtTxInf><PmtId><EndToEndId>E2E-D1</EndToEndId></PmtId><InstdAmt Ccy="EUR">10.00</InstdAmt><DrctDbtTx><MndtRltdInf><MndtId>MANDATE-1</MndtId><DtOfSgntr>2025-03-14</DtOfSgntr></MndtRltdInf></DrctDbtTx><DbtrAgt><FinInstnId></FinInstnId></DbtrAgt><Dbtr><Nm>Debtor One</Nm></Dbtr><DbtrAcct><Id><IBAN>DE89370400440532013000</IBAN></Id></DbtrAcct><RmtInf><Ustrd>Membership 2026</Ustrd></RmtInf></DrctDbtTxInf><DrctDbtTxInf><PmtId><EndToEndId>E2E-D2</EndToEndId></PmtId><InstdAmt Ccy="EUR">25.50</InstdAmt><DrctDbtTx><MndtRltdInf><MndtId>MANDATE-2</MndtId><DtOfSgntr>2024-11-02</DtOfSgntr><AmdmntInd>false</AmdmntInd></MndtRltdInf></DrctDbtTx><DbtrAgt><FinInstnId><BIC>UBSWCHZH80A</BIC></FinInstnId></DbtrAgt><Dbtr><Nm>Debtor Two</Nm></Dbtr><DbtrAcct><Id><IBAN>CH9300762011623852957</IBAN></Id></DbtrAcct></DrctDbtTxInf></PmtInf></CstmrDrctDbtInitn></Document>
""";
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample_debit(wopts, out) == 0);
    if out.len != full.len {
        print("FAIL old bytes len ", out.len, " want ", full.len, "\n");
    }
    assert(out.len == full.len);
    var i: i64 = 0;
    while i < out.len {
        if out[i] != full[i] {
            print("FAIL old bytes at ", i, ": got ", out[i], " want ", full[i], "\n");
        }
        assert(out[i] == full[i]);
        i += 1;
    }
}

fn test_debit_reader_refusals() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample_debit_full(wopts, out) == 0);
    var lim = payment_file::default_limits();
    // A third address line is a fault.
    var a: u8[>..] = [];
    var txt = "<TwnNm>Amsterdam</TwnNm><AdrLine>One</AdrLine><AdrLine>Two</AdrLine><AdrLine>Three</AdrLine>";
    replace_all(out, "<TwnNm>Amsterdam</TwnNm>", txt, a);
    assert(read_debit_kind(a, false, lim) == payment_file::F_LIMIT);
    // A second other identifier is a fault.
    var b: u8[>..] = [];
    replace_all(out, "<Id>NL-REG-123</Id><Issr>KVK</Issr>", "<Id>NL-REG-123</Id><Issr>KVK</Issr></Othr><Othr><Id>NL-REG-999</Id>", b);
    assert(read_debit_kind(b, false, lim) == payment_file::F_LIMIT);
    // A second copy of an address field is a fault.
    var c: u8[>..] = [];
    replace_all(out, "<TwnNm>Amsterdam</TwnNm>", "<TwnNm>Amsterdam</TwnNm><TwnNm>Rotterdam</TwnNm>", c);
    assert(read_debit_kind(c, false, lim) == payment_file::F_SYNTAX);
    // Two LEIs are a fault.
    var d: u8[>..] = [];
    replace_all(out, "<Id><OrgId><Othr>", "<Id><OrgId><LEI>5493001KJTIIGC8Y1R12</LEI><LEI>11111111111111111111</LEI><Othr>", d);
    assert(read_debit_kind(d, false, lim) == payment_file::F_SYNTAX);
    // An address line with no text is a fault.
    var e: u8[>..] = [];
    replace_all(out, "<TwnNm>Amsterdam</TwnNm>", "<TwnNm>Amsterdam</TwnNm><AdrLine></AdrLine>", e);
    assert(read_debit_kind(e, false, lim) == payment_file::F_SYNTAX);
    // A reference type with an issuer and no code is a fault.
    var g: u8[>..] = [];
    replace_all(out, "<CdOrPrtry><Cd>SCOR</Cd></CdOrPrtry>", "", g);
    assert(read_debit_kind(g, false, lim) == payment_file::F_SYNTAX);
    // Two names and two organisation identifications are faults.
    var i2: u8[>..] = [];
    replace_all(out, "<Cdtr><Nm>Club Treasurer</Nm>", "<Cdtr><Nm>Club Treasurer</Nm><Nm>Again</Nm>", i2);
    assert(read_debit_kind(i2, false, lim) == payment_file::F_SYNTAX);
    var j: u8[>..] = [];
    replace_all(out, "<Id><OrgId><Othr><Id>NL-REG-123</Id><Issr>KVK</Issr></Othr></OrgId></Id>",
                "<Id><OrgId><Othr><Id>NL-REG-123</Id><Issr>KVK</Issr></Othr></OrgId><OrgId><Othr><Id>SECOND</Id></Othr></OrgId></Id>", j);
    assert(read_debit_kind(j, false, lim) == payment_file::F_SYNTAX);
}


// A credit transfer with a service level and a reference type of its
// own. An empty text means the default.
fn sample_transfer(opts: payment_file::PainWriteOptions, level: const u8[:],
                   code: const u8[:], prop: const u8[:], out: u8[>..]&) -> i32 {
    var items: payment_file::CreditTransfer[>..] = [];
    var t = payment_file::new_transfer();
    t.end_to_end_id = "E2E-1";
    let m, ok = finance::money(100, "EUR");
    if !ok { return -1; }
    t.amount = m;
    t.creditor_name = "Creditor One";
    t.creditor_iban = "DE89370400440532013000";
    t.structured_type = code;
    t.structured_proprietary_type = prop;
    t.structured_ref = "RF18539007547034";
    items.push(t);
    var pays: payment_file::PaymentInfo[>..] = [];
    var p = payment_file::new_payment();
    p.id = "PMT-1";
    p.service_level = level;
    p.debtor_name = "Acme Trading Ltd";
    p.debtor_iban = "NL91ABNA0417164300";
    p.execution_year = 2026; p.execution_month = 12; p.execution_day = 1;
    p.has_execution_date = true;
    p.item_start = 0;
    p.item_count = items.len as i32;
    pays.push(p);
    var h = payment_file::new_header();
    h.message_id = "MSG-1";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.initiator = "Acme Trading Ltd";
    var lim = payment_file::default_limits();
    let f = payment_file::write_pain001(h, pays, items, opts, lim, out);
    return f.kind;
}

// A direct debit with a service level of its own.
fn sample_debit_level(opts: payment_file::PainWriteOptions, level: const u8[:], out: u8[>..]&) -> i32 {
    var items: payment_file::DirectDebit[>..] = [];
    var t = payment_file::new_direct_debit();
    t.end_to_end_id = "E2E-1";
    let m, ok = finance::money(100, "EUR");
    if !ok { return -1; }
    t.amount = m;
    t.mandate_id = "MANDATE-1";
    t.signature_year = 2025; t.signature_month = 6; t.signature_day = 1;
    t.has_signature_date = true;
    t.debtor_name = "Debtor One";
    t.debtor_iban = "DE89370400440532013000";
    items.push(t);
    var blocks: payment_file::DebitInfo[>..] = [];
    var b = payment_file::new_debit_info();
    b.id = "DD-1";
    b.service_level = level;
    b.creditor_name = "Club Treasurer";
    b.creditor_iban = "NL91ABNA0417164300";
    b.scheme_id = "DE98ZZZ09999999999";
    b.seq_type = "RCUR";
    b.instrument = "CORE";
    b.collection_year = 2026; b.collection_month = 12; b.collection_day = 1;
    b.has_collection_date = true;
    b.item_count = 1;
    blocks.push(b);
    var h = payment_file::new_header();
    h.message_id = "DD-MSG-1";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.initiator = "Club Treasurer";
    var lim = payment_file::default_limits();
    let f = payment_file::write_pain008(h, blocks, items, opts, lim, out);
    return f.kind;
}

// The pain.001 writer writes the payment type block with the service
// level. The pain.008 writer writes the same value.
fn test_service_level() {
    var out: u8[>..] = [];
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    assert(sample(wopts, out) == 0);
    let pinf = find(out, "<PmtInf>");
    let csum = find_from(out, "<CtrlSum>", pinf);
    let tp = find_from(out, "<PmtTpInf>", pinf);
    let sl = find_from(out, "<SvcLvl><Cd>SEPA</Cd></SvcLvl>", tp);
    let exdt = find_from(out, "<ReqdExctnDt>", pinf);
    assert(pinf >= 0 && csum > pinf && tp > csum && sl > tp && exdt > sl);
    var dout: u8[>..] = [];
    assert(sample_debit(wopts, dout) == 0);
    assert(find(dout, "<SvcLvl><Cd>SEPA</Cd></SvcLvl>") >= 0);
    // The model holds the service level of the block.
    var own: u8[>..] = [];
    assert(sample_transfer(wopts, "PRPT", "", "", own) == 0);
    assert(find(own, "<SvcLvl><Cd>PRPT</Cd></SvcLvl>") >= 0);
    // A service level above its limit is a fault.
    var bad: u8[>..] = [];
    assert(sample_transfer(wopts, "SEPTX", "", "", bad) == payment_file::F_LIMIT);
}

// swap_kind replaces one text of a pain.001 document and returns the
// kind of the fault that the reader gives.
fn swap_kind(tpl: const u8[:], from: const u8[:], to: const u8[:]) -> i32 {
    var lim = payment_file::default_limits();
    var ropts = payment_file::PainOptions { skip_control_sum_check: true, check_iban: true, epc_charset: true };
    var base: u8[>..] = [];
    put(base, tpl);
    var doc: u8[>..] = [];
    replace_all(base, from, to, doc);
    var h = payment_file::new_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    let r = payment_file::parse_pain001(doc, lim, ropts, h, pays, items, buf);
    return r.kind;
}

// The reader takes the later pain.001 forms, where the execution date
// holds a child element.
fn test_later_forms() {
    var lim = payment_file::default_limits();
    var ropts = payment_file::PainOptions { skip_control_sum_check: true, check_iban: true, epc_charset: true };
    let tpl = """
<?xml version="1.0"?><Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.09">
<CstmrCdtTrfInitn><GrpHdr><MsgId>M1</MsgId><CreDtTm>2026-11-09T09:00:00</CreDtTm><NbOfTxs>1</NbOfTxs><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P1</PmtInfId><PmtMtd>TRF</PmtMtd><PmtTpInf><SvcLvl><Cd>SEPA</Cd></SvcLvl></PmtTpInf>
<ReqdExctnDt>2026-12-01</ReqdExctnDt>
<Dbtr><Nm>Debtor</Nm><Id><OrgId><AnyBIC>ABNANL2A</AnyBIC></OrgId></Id></Dbtr>
<DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct><DbtrAgt><FinInstnId></FinInstnId></DbtrAgt>
<CdtTrfTxInf><PmtId><EndToEndId>E1</EndToEndId></PmtId><Amt><InstdAmt Ccy="EUR">1.00</InstdAmt></Amt>
<Cdtr><Nm>Cred</Nm></Cdtr><CdtrAcct><Id><IBAN>BE68539007547034</IBAN></Id></CdtrAcct></CdtTrfTxInf>
</PmtInf></CstmrCdtTrfInitn></Document>
""";
    // The plain text of the earlier form.
    var h = payment_file::new_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    let r = payment_file::parse_pain001(tpl, lim, ropts, h, pays, items, buf);
    if r.kind != 0 { print("FAIL later plain ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == payment_file::F_NONE);
    assert(pays[0].execution_year == 2026 && pays[0].execution_month == 12 && pays[0].execution_day == 1);
    assert(pays[0].service_level == "SEPA");
    // The later form holds the date as a child element.
    var base: u8[>..] = [];
    put(base, tpl);
    var dt_doc: u8[>..] = [];
    replace_all(base, "<ReqdExctnDt>2026-12-01</ReqdExctnDt>", "<ReqdExctnDt><Dt>2026-12-02</Dt></ReqdExctnDt>", dt_doc);
    var h2 = payment_file::new_header();
    var pays2: payment_file::PaymentInfo[>..] = [];
    var items2: payment_file::CreditTransfer[>..] = [];
    var buf2: u8[>..] = [];
    let r2 = payment_file::parse_pain001(dt_doc, lim, ropts, h2, pays2, items2, buf2);
    if r2.kind != 0 { print("FAIL later dt ", payment_file::kind_name(r2.kind), " ", r2.tag, " ", r2.detail, "\n"); }
    assert(r2.kind == payment_file::F_NONE);
    assert(pays2[0].execution_day == 2);
    // The date and the time form.
    var dtm_doc: u8[>..] = [];
    replace_all(base, "<ReqdExctnDt>2026-12-01</ReqdExctnDt>", "<ReqdExctnDt><DtTm>2026-12-03T09:15:00</DtTm></ReqdExctnDt>", dtm_doc);
    var h3 = payment_file::new_header();
    var pays3: payment_file::PaymentInfo[>..] = [];
    var items3: payment_file::CreditTransfer[>..] = [];
    var buf3: u8[>..] = [];
    let r3 = payment_file::parse_pain001(dtm_doc, lim, ropts, h3, pays3, items3, buf3);
    if r3.kind != 0 { print("FAIL later dtm ", payment_file::kind_name(r3.kind), " ", r3.tag, " ", r3.detail, "\n"); }
    assert(r3.kind == payment_file::F_NONE);
    assert(pays3[0].execution_day == 3);
    // An execution date with no text and no child element is a fault.
    var empty_doc: u8[>..] = [];
    replace_all(base, "<ReqdExctnDt>2026-12-01</ReqdExctnDt>", "<ReqdExctnDt></ReqdExctnDt>", empty_doc);
    var h4 = payment_file::new_header();
    var pays4: payment_file::PaymentInfo[>..] = [];
    var items4: payment_file::CreditTransfer[>..] = [];
    var buf4: u8[>..] = [];
    let r4 = payment_file::parse_pain001(empty_doc, lim, ropts, h4, pays4, items4, buf4);
    assert(r4.kind == payment_file::F_DATE);
    // A second child, a text with a child, two payment type elements,
    // two service levels and a code with a child element are faults.
    let rd = "<ReqdExctnDt>2026-12-01</ReqdExctnDt>";
    assert(swap_kind(tpl, rd, "<ReqdExctnDt><Dt>2026-12-02</Dt><Dt>2026-12-03</Dt></ReqdExctnDt>") == payment_file::F_SYNTAX);
    assert(swap_kind(tpl, rd, "<ReqdExctnDt>2026-12-01<Dt>2026-12-02</Dt></ReqdExctnDt>") == payment_file::F_SYNTAX);
    let tp = "<PmtTpInf><SvcLvl><Cd>SEPA</Cd></SvcLvl></PmtTpInf>";
    assert(swap_kind(tpl, tp, "<PmtTpInf><SvcLvl><Cd>SEPA</Cd></SvcLvl></PmtTpInf><PmtTpInf><SvcLvl><Cd>SEPA</Cd></SvcLvl></PmtTpInf>") == payment_file::F_SYNTAX);
    assert(swap_kind(tpl, tp, "<PmtTpInf><SvcLvl><Cd>SEPA</Cd></SvcLvl><SvcLvl><Cd>SEPA</Cd></SvcLvl></PmtTpInf>") == payment_file::F_SYNTAX);
    assert(swap_kind(tpl, "<Cd>SEPA</Cd>", "<Cd><X>1</X></Cd>") == payment_file::F_SYNTAX);
    assert(swap_kind(tpl, "<Cd>SEPA</Cd>", "<Prtry>X</Prtry>") == payment_file::F_SYNTAX);
}

// The proprietary form of the reference type reads and writes.
fn test_proprietary_reference() {
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var out: u8[>..] = [];
    assert(sample_transfer(wopts, "", "", "CUSTOM", out) == 0);
    assert(find(out, "<CdOrPrtry><Prtry>CUSTOM</Prtry></CdOrPrtry>") >= 0);
    assert(find(out, "<CdOrPrtry><Cd>") < 0);
    // The reader takes the proprietary text.
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var lim = payment_file::default_limits();
    var h = payment_file::new_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    let text: const u8[:] = out[..];
    let r = payment_file::parse_pain001(text, lim, ropts, h, pays, items, buf);
    if r.kind != 0 { print("FAIL prop read ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == payment_file::F_NONE);
    assert(items[0].structured_proprietary_type == "CUSTOM");
    assert(items[0].structured_type.len == 0);
    assert(items[0].structured_ref == "RF18539007547034");
    // A model with a code and a proprietary text is a fault, and the
    // output buffer keeps its old bytes.
    var out2: u8[>..] = [];
    out2.push('O'); out2.push('L'); out2.push('D');
    assert(sample_transfer(wopts, "", "SCOR", "CUSTOM", out2) == payment_file::F_SYNTAX);
    assert(out2.len == 3 && out2[0] == 'O');
    // The code form still writes.
    var out3: u8[>..] = [];
    assert(sample_transfer(wopts, "", "SCOR", "", out3) == 0);
    assert(find(out3, "<CdOrPrtry><Cd>SCOR</Cd></CdOrPrtry>") >= 0);
}

// renamed_tag renames one element pair in a written message, reads the
// result and gives the tag of the fault. The kind must be syntax.
fn renamed_tag(text: const u8[:], o: const u8[:], c: const u8[:], ro: const u8[:], rc: const u8[:], debit: bool) -> const u8[:] {
    var a: u8[>..] = [];
    var b: u8[>..] = [];
    var base: u8[>..] = [];
    put(base, text);
    replace_all(base, o, ro, a);
    replace_all(a, c, rc, b);
    var lim = payment_file::default_limits();
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var h = payment_file::new_header();
    var buf: u8[>..] = [];
    var blocks: payment_file::DebitInfo[>..] = [];
    var ditems: payment_file::DirectDebit[>..] = [];
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    let doc: const u8[:] = b[..];
    var kind = payment_file::F_NONE;
    var tag: const u8[:] = "";
    if debit {
        let r = payment_file::parse_pain008(doc, lim, ropts, h, blocks, ditems, buf);
        kind = r.kind;
        tag = r.tag;
    } else {
        let r = payment_file::parse_pain001(doc, lim, ropts, h, pays, items, buf);
        kind = r.kind;
        tag = r.tag;
    }
    if kind != payment_file::F_SYNTAX { return "none"; }
    return tag;
}

// The readers refuse a file that lacks an element the schema requires,
// and the fault names the element. A file that the writer wrote reads.
fn test_mandatory_elements() {
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var out: u8[>..] = [];
    assert(sample(wopts, out) == 0);
    let t1: const u8[:] = out[..];
    assert(renamed_tag(t1, "<CreDtTm>", "</CreDtTm>", "<Xx>", "</Xx>", false) == "CreDtTm");
    assert(renamed_tag(t1, "<InitgPty>", "</InitgPty>", "<Xx>", "</Xx>", false) == "InitgPty");
    assert(renamed_tag(t1, "<PmtInfId>", "</PmtInfId>", "<Xx>", "</Xx>", false) == "PmtInfId");
    assert(renamed_tag(t1, "<PmtMtd>", "</PmtMtd>", "<Xx>", "</Xx>", false) == "PmtMtd");
    assert(renamed_tag(t1, "<ReqdExctnDt>", "</ReqdExctnDt>", "<Xx>", "</Xx>", false) == "ReqdExctnDt");
    assert(renamed_tag(t1, "<Dbtr>", "</Dbtr>", "<Xx>", "</Xx>", false) == "Dbtr");
    assert(renamed_tag(t1, "<DbtrAcct>", "</DbtrAcct>", "<Xx>", "</Xx>", false) == "DbtrAcct");
    assert(renamed_tag(t1, "<DbtrAgt>", "</DbtrAgt>", "<Xx>", "</Xx>", false) == "DbtrAgt");
    assert(renamed_tag(t1, "<DbtrAcct><Id>", "</Id></DbtrAcct>", "<DbtrAcct><Xx>", "</Xx></DbtrAcct>", false) == "Id");
    assert(renamed_tag(t1, "<DbtrAgt><FinInstnId>", "</FinInstnId></DbtrAgt>", "<DbtrAgt><Xx>", "</Xx></DbtrAgt>", false) == "FinInstnId");
    assert(renamed_tag(t1, "<PmtId>", "</PmtId>", "<Xx>", "</Xx>", false) == "PmtId");
    assert(renamed_tag(t1, "<EndToEndId>", "</EndToEndId>", "<Xx>", "</Xx>", false) == "EndToEndId");
    // A block with no item is a fault.
    let empty001 = """
<?xml version="1.0"?><Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.03">
<CstmrCdtTrfInitn><GrpHdr><MsgId>M1</MsgId><CreDtTm>2026-11-09T09:00:00</CreDtTm><NbOfTxs>0</NbOfTxs><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P1</PmtInfId><PmtMtd>TRF</PmtMtd><ReqdExctnDt>2026-12-01</ReqdExctnDt><Dbtr><Nm>Debtor</Nm></Dbtr>
<DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct><DbtrAgt><FinInstnId></FinInstnId></DbtrAgt>
</PmtInf></CstmrCdtTrfInitn></Document>
""";
    assert(swap_kind(empty001, "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    // The count of the group header.
    assert(renamed_tag(t1, "<NbOfTxs>", "</NbOfTxs>", "<Xx>", "</Xx>", false) == "NbOfTxs");
    var dout: u8[>..] = [];
    assert(sample_debit(wopts, dout) == 0);
    let t2: const u8[:] = dout[..];
    assert(renamed_tag(t2, "<CreDtTm>", "</CreDtTm>", "<Xx>", "</Xx>", true) == "CreDtTm");
    assert(renamed_tag(t2, "<InitgPty>", "</InitgPty>", "<Xx>", "</Xx>", true) == "InitgPty");
    assert(renamed_tag(t2, "<PmtInfId>", "</PmtInfId>", "<Xx>", "</Xx>", true) == "PmtInfId");
    assert(renamed_tag(t2, "<PmtMtd>", "</PmtMtd>", "<Xx>", "</Xx>", true) == "PmtMtd");
    assert(renamed_tag(t2, "<ReqdColltnDt>", "</ReqdColltnDt>", "<Xx>", "</Xx>", true) == "ReqdColltnDt");
    assert(renamed_tag(t2, "<Cdtr>", "</Cdtr>", "<Xx>", "</Xx>", true) == "Cdtr");
    assert(renamed_tag(t2, "<CdtrAcct>", "</CdtrAcct>", "<Xx>", "</Xx>", true) == "CdtrAcct");
    assert(renamed_tag(t2, "<CdtrAgt>", "</CdtrAgt>", "<Xx>", "</Xx>", true) == "CdtrAgt");
    assert(renamed_tag(t2, "<CdtrAcct><Id>", "</Id></CdtrAcct>", "<CdtrAcct><Xx>", "</Xx></CdtrAcct>", true) == "Id");
    assert(renamed_tag(t2, "<PmtId>", "</PmtId>", "<Xx>", "</Xx>", true) == "PmtId");
    assert(renamed_tag(t2, "<EndToEndId>", "</EndToEndId>", "<Xx>", "</Xx>", true) == "EndToEndId");
    assert(renamed_tag(t2, "<DbtrAgt>", "</DbtrAgt>", "<Xx>", "</Xx>", true) == "DbtrAgt");
    assert(renamed_tag(t2, "<Dbtr>", "</Dbtr>", "<Xx>", "</Xx>", true) == "Dbtr");
    assert(renamed_tag(t2, "<DbtrAcct>", "</DbtrAcct>", "<Xx>", "</Xx>", true) == "DbtrAcct");
    // An unchanged file reads.
    assert(renamed_tag(t1, "<Zz>", "</Zz>", "<Xx>", "</Xx>", false) == "none");
    assert(renamed_tag(t2, "<Zz>", "</Zz>", "<Xx>", "</Xx>", true) == "none");
}

// swap_debit replaces two texts of a pain.008 document and gives the
// kind of the reader fault.
fn swap_debit(text: const u8[:], a1: const u8[:], b1: const u8[:], a2: const u8[:], b2: const u8[:]) -> i32 {
    var base: u8[>..] = [];
    put(base, text);
    var one: u8[>..] = [];
    var two: u8[>..] = [];
    replace_all(base, a1, b1, one);
    replace_all(one, a2, b2, two);
    var lim = payment_file::default_limits();
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var h = payment_file::new_header();
    var blocks: payment_file::DebitInfo[>..] = [];
    var items: payment_file::DirectDebit[>..] = [];
    var buf: u8[>..] = [];
    let doc: const u8[:] = two[..];
    let r = payment_file::parse_pain008(doc, lim, ropts, h, blocks, items, buf);
    return r.kind;
}

// sample_birth writes a direct debit whose debtor holds birth data and
// whose item holds a pre-notification. The mode picks one fault:
// 0 none, 1 an organisation, 2 no city, 3 a bad country, 4 a bad date,
// 5 no kind, 6 a bad pre-notification date.
fn sample_birth(opts: payment_file::PainWriteOptions, mode: i32, out: u8[>..]&) -> i32 {
    var items: payment_file::DirectDebit[>..] = [];
    var t = payment_file::new_direct_debit();
    t.end_to_end_id = "E2E-B1";
    let m, ok = finance::money(1000, "EUR");
    if !ok { return -1; }
    t.amount = m;
    t.mandate_id = "MANDATE-B1";
    t.signature_year = 2025; t.signature_month = 6; t.signature_day = 1;
    t.has_signature_date = true;
    t.debtor_name = "Debtor Born";
    t.debtor_iban = "DE89370400440532013000";
    t.debtor_detail.id.kind = payment_file::PARTY_PERSON;
    t.debtor_detail.id.birth.year = 1980; t.debtor_detail.id.birth.month = 2; t.debtor_detail.id.birth.day = 29;
    t.debtor_detail.id.birth.has_date = true;
    t.debtor_detail.id.birth.province = "Bavaria";
    t.debtor_detail.id.birth.city = "Munich";
    t.debtor_detail.id.birth.country = "DE";
    t.pre_notification_id = "PRE-77";
    t.pre_notification_year = 2026; t.pre_notification_month = 11; t.pre_notification_day = 20;
    t.has_pre_notification_date = true;
    if mode == 1 { t.debtor_detail.id.kind = payment_file::PARTY_ORG; }
    if mode == 2 { t.debtor_detail.id.birth.city = ""; }
    if mode == 3 { t.debtor_detail.id.birth.country = "de"; }
    if mode == 4 { t.debtor_detail.id.birth.day = 30; }
    if mode == 5 { t.debtor_detail.id.kind = payment_file::PARTY_NONE; }
    if mode == 6 { t.pre_notification_month = 13; }
    items.push(t);
    var blocks: payment_file::DebitInfo[>..] = [];
    var b = payment_file::new_debit_info();
    b.id = "DD-B";
    b.creditor_name = "Club Treasurer";
    b.creditor_iban = "NL91ABNA0417164300";
    b.creditor_bic = "ABNANL2A";
    b.scheme_id = "DE98ZZZ09999999999";
    b.seq_type = "RCUR";
    b.instrument = "CORE";
    b.collection_year = 2026; b.collection_month = 12; b.collection_day = 1;
    b.has_collection_date = true;
    b.item_count = 1;
    blocks.push(b);
    var h = payment_file::new_header();
    h.message_id = "DD-MSG-B";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.initiator = "Club Treasurer";
    var lim = payment_file::default_limits();
    let f = payment_file::write_pain008(h, blocks, items, opts, lim, out);
    return f.kind;
}

// The date and place of birth and the pre-notification write in schema
// order and read back. A bad value is a fault and leaves the buffer.
fn test_birth_and_pre_notification() {
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var out: u8[>..] = [];
    assert(sample_birth(wopts, 0, out) == 0);
    let tx = find(out, "<DrctDbtTx>");
    let mi = find_from(out, "</MndtRltdInf>", tx);
    let pn = find_from(out, "<PreNtfctnId>PRE-77</PreNtfctnId><PreNtfctnDt>2026-11-20</PreNtfctnDt></DrctDbtTx>", mi);
    assert(tx >= 0 && mi > tx && pn > mi);
    let bd = find(out, "<PrvtId><DtAndPlcOfBirth><BirthDt>1980-02-29</BirthDt><PrvcOfBirth>Bavaria</PrvcOfBirth><CityOfBirth>Munich</CityOfBirth><CtryOfBirth>DE</CtryOfBirth></DtAndPlcOfBirth></PrvtId>");
    assert(bd >= 0);
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var lim = payment_file::default_limits();
    var h = payment_file::new_header();
    var blocks: payment_file::DebitInfo[>..] = [];
    var items: payment_file::DirectDebit[>..] = [];
    var buf: u8[>..] = [];
    let text: const u8[:] = out[..];
    let r = payment_file::parse_pain008(text, lim, ropts, h, blocks, items, buf);
    if r.kind != 0 { print("FAIL birth read ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == payment_file::F_NONE);
    let b = items[0].debtor_detail.id.birth;
    assert(b.has_date && b.year == 1980 && b.month == 2 && b.day == 29);
    assert(b.province == "Bavaria" && b.city == "Munich" && b.country == "DE");
    assert(items[0].pre_notification_id == "PRE-77" && items[0].has_pre_notification_date);
    assert(items[0].pre_notification_month == 11 && items[0].pre_notification_day == 20);
    // The writer refuses each bad model and keeps the buffer.
    var k: i32 = 1;
    while k <= 6 {
        var bad: u8[>..] = [];
        bad.push('O');
        let wk = sample_birth(wopts, k, bad);
        assert(wk == payment_file::F_SYNTAX || wk == payment_file::F_DATE);
        assert(bad.len == 1);
        k += 1;
    }
    // The reader refuses birth data of an organisation, a second copy,
    // and a date, a city or a country that is missing or bad.
    assert(swap_debit(text, "<PrvtId>", "<OrgId>", "</PrvtId>", "</OrgId>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<CityOfBirth>Munich</CityOfBirth>", "", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<CtryOfBirth>DE</CtryOfBirth>", "", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<CtryOfBirth>DE</CtryOfBirth>", "<CtryOfBirth>Germany</CtryOfBirth>", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<BirthDt>1980-02-29</BirthDt>", "", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<BirthDt>1980-02-29</BirthDt>", "<BirthDt>1981-02-29</BirthDt>", "<Zz>", "<Zz>") == payment_file::F_DATE);
    assert(swap_debit(text, "<PreNtfctnDt>2026-11-20</PreNtfctnDt>", "<PreNtfctnDt>2026-13-20</PreNtfctnDt>", "<Zz>", "<Zz>") == payment_file::F_DATE);
    assert(swap_debit(text, "</DtAndPlcOfBirth>", "</DtAndPlcOfBirth><DtAndPlcOfBirth><BirthDt>1980-02-29</BirthDt><CityOfBirth>X</CityOfBirth><CtryOfBirth>DE</CtryOfBirth></DtAndPlcOfBirth>", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<PrvcOfBirth>Bavaria</PrvcOfBirth>", "<PrvcOfBirth>A</PrvcOfBirth><PrvcOfBirth>B</PrvcOfBirth>", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<PreNtfctnId>PRE-77</PreNtfctnId>", "<PreNtfctnId>A</PreNtfctnId><PreNtfctnId>B</PreNtfctnId>", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<PreNtfctnDt>2026-11-20</PreNtfctnDt>", "<PreNtfctnDt>2026-11-20</PreNtfctnDt><PreNtfctnDt>2026-11-21</PreNtfctnDt>", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    // A person that holds only birth data is an identification.
    assert(swap_debit(text, "<Zz>", "<Zz>", "<Zz>", "<Zz>") == payment_file::F_NONE);
    // The pain.001 reader takes the birth data of a private debtor.
    let p001 = """
<?xml version="1.0"?><Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.03">
<CstmrCdtTrfInitn><GrpHdr><MsgId>M1</MsgId><CreDtTm>2026-11-09T09:00:00</CreDtTm><NbOfTxs>1</NbOfTxs><InitgPty><Nm>Init</Nm></InitgPty></GrpHdr>
<PmtInf><PmtInfId>P1</PmtInfId><PmtMtd>TRF</PmtMtd><ReqdExctnDt>2026-12-01</ReqdExctnDt>
<Dbtr><Nm>Debtor</Nm><Id><PrvtId><DtAndPlcOfBirth><BirthDt>1975-05-06</BirthDt><CityOfBirth>Lyon</CityOfBirth><CtryOfBirth>FR</CtryOfBirth></DtAndPlcOfBirth></PrvtId></Id></Dbtr>
<DbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></DbtrAcct><DbtrAgt><FinInstnId></FinInstnId></DbtrAgt>
<CdtTrfTxInf><PmtId><EndToEndId>E1</EndToEndId></PmtId><Amt><InstdAmt Ccy="EUR">1.00</InstdAmt></Amt>
<Cdtr><Nm>Cred</Nm></Cdtr><CdtrAcct><Id><IBAN>BE68539007547034</IBAN></Id></CdtrAcct></CdtTrfTxInf>
</PmtInf></CstmrCdtTrfInitn></Document>
""";
    assert(swap_kind(p001, "<Zz>", "<Zz>") == payment_file::F_NONE);
    assert(swap_kind(p001, "<CityOfBirth>Lyon</CityOfBirth>", "") == payment_file::F_SYNTAX);
}

// sample_amend writes a direct debit whose mandate holds amendment
// details and an electronic signature. The mode picks one fault:
// 0 none, 1 the flag is false, 2 an agent with a BIC and a marker,
// 3 a bad IBAN, 4 a bad final date.
fn sample_amend(opts: payment_file::PainWriteOptions, mode: i32, out: u8[>..]&) -> i32 {
    var items: payment_file::DirectDebit[>..] = [];
    var t = payment_file::new_direct_debit();
    t.end_to_end_id = "E2E-A1";
    let m, ok = finance::money(1000, "EUR");
    if !ok { return -1; }
    t.amount = m;
    t.mandate_id = "NEW-MANDATE";
    t.signature_year = 2025; t.signature_month = 6; t.signature_day = 1;
    t.has_signature_date = true;
    t.has_amendment = true;
    t.amendment = true;
    t.debtor_name = "Debtor A";
    t.debtor_iban = "DE89370400440532013000";
    t.electronic_signature = "SIG-1";
    t.amendment_details.mandate_id = "OLD-MANDATE";
    t.amendment_details.creditor_name = "Old Creditor";
    t.amendment_details.creditor_detail.id.kind = payment_file::PARTY_ORG;
    t.amendment_details.creditor_detail.id.other.id = "DE98ZZZ09999999999";
    t.amendment_details.creditor_detail.id.other.scheme_proprietary = "SEPA";
    t.amendment_details.creditor_agent.present = true;
    t.amendment_details.creditor_agent.bic = "ABNANL2A";
    t.amendment_details.debtor_name = "Old Debtor";
    t.amendment_details.debtor_iban = "NL91ABNA0417164300";
    t.amendment_details.debtor_agent.present = true;
    t.amendment_details.debtor_agent.other_id = "SMNDA";
    t.amendment_details.debtor_agent_iban = "CH9300762011623852957";
    t.amendment_details.final_year = 2027; t.amendment_details.final_month = 1; t.amendment_details.final_day = 31;
    t.amendment_details.has_final_date = true;
    if mode == 1 { t.amendment = false; }
    if mode == 2 { t.amendment_details.debtor_agent.bic = "ABNANL2A"; }
    if mode == 3 { t.amendment_details.debtor_iban = "NL91ABNA0417164301"; }
    if mode == 4 { t.amendment_details.final_day = 32; }
    items.push(t);
    var blocks: payment_file::DebitInfo[>..] = [];
    var b = payment_file::new_debit_info();
    b.id = "DD-A";
    b.creditor_name = "Club Treasurer";
    b.creditor_iban = "NL91ABNA0417164300";
    b.creditor_bic = "ABNANL2A";
    b.scheme_id = "DE98ZZZ09999999999";
    b.seq_type = "RCUR";
    b.instrument = "CORE";
    b.collection_year = 2026; b.collection_month = 12; b.collection_day = 1;
    b.has_collection_date = true;
    b.item_count = 1;
    blocks.push(b);
    var h = payment_file::new_header();
    h.message_id = "DD-MSG-A";
    h.has_creation = true;
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.initiator = "Club Treasurer";
    var lim = payment_file::default_limits();
    let f = payment_file::write_pain008(h, blocks, items, opts, lim, out);
    return f.kind;
}

// The amendment details of a mandate write in schema order, read back,
// and a bad value is a fault.
fn test_amendment_details() {
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var out: u8[>..] = [];
    assert(sample_amend(wopts, 0, out) == 0);
    let ind = find(out, "<AmdmntInd>true</AmdmntInd><AmdmntInfDtls><OrgnlMndtId>OLD-MANDATE</OrgnlMndtId>");
    let cs = find_from(out, "<OrgnlCdtrSchmeId><Nm>Old Creditor</Nm><Id><OrgId><Othr><Id>DE98ZZZ09999999999</Id><SchmeNm><Prtry>SEPA</Prtry></SchmeNm></Othr></OrgId></Id></OrgnlCdtrSchmeId>", ind);
    let ca = find_from(out, "<OrgnlCdtrAgt><FinInstnId><BIC>ABNANL2A</BIC></FinInstnId></OrgnlCdtrAgt>", cs);
    let db = find_from(out, "<OrgnlDbtr><Nm>Old Debtor</Nm></OrgnlDbtr>", ca);
    let da = find_from(out, "<OrgnlDbtrAcct><Id><IBAN>NL91ABNA0417164300</IBAN></Id></OrgnlDbtrAcct>", db);
    let ag = find_from(out, "<OrgnlDbtrAgt><FinInstnId><Othr><Id>SMNDA</Id></Othr></FinInstnId></OrgnlDbtrAgt>", da);
    let ac = find_from(out, "<OrgnlDbtrAgtAcct><Id><IBAN>CH9300762011623852957</IBAN></Id></OrgnlDbtrAgtAcct>", ag);
    let fd = find_from(out, "<OrgnlFnlColltnDt>2027-01-31</OrgnlFnlColltnDt></AmdmntInfDtls><ElctrncSgntr>SIG-1</ElctrncSgntr></MndtRltdInf>", ac);
    assert(ind >= 0 && cs > ind && ca > cs && db > ca && da > db && ag > da && ac > ag && fd > ac);
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var lim = payment_file::default_limits();
    var h = payment_file::new_header();
    var blocks: payment_file::DebitInfo[>..] = [];
    var items: payment_file::DirectDebit[>..] = [];
    var buf: u8[>..] = [];
    let text: const u8[:] = out[..];
    let r = payment_file::parse_pain008(text, lim, ropts, h, blocks, items, buf);
    if r.kind != 0 { print("FAIL amend read ", payment_file::kind_name(r.kind), " ", r.tag, " ", r.detail, "\n"); }
    assert(r.kind == payment_file::F_NONE);
    let a = items[0].amendment_details;
    assert(a.mandate_id == "OLD-MANDATE" && a.creditor_name == "Old Creditor");
    assert(a.creditor_detail.id.kind == payment_file::PARTY_ORG && a.creditor_detail.id.other.id == "DE98ZZZ09999999999");
    assert(a.creditor_agent.present && a.creditor_agent.bic == "ABNANL2A" && a.creditor_agent.other_id.len == 0);
    assert(a.debtor_name == "Old Debtor" && a.debtor_iban == "NL91ABNA0417164300");
    assert(a.debtor_agent.present && a.debtor_agent.other_id == "SMNDA" && a.debtor_agent.bic.len == 0);
    assert(a.debtor_agent_iban == "CH9300762011623852957");
    assert(a.has_final_date && a.final_year == 2027 && a.final_month == 1 && a.final_day == 31);
    assert(items[0].electronic_signature == "SIG-1");
    // The writer refuses each bad model and keeps the buffer.
    var k: i32 = 1;
    while k <= 4 {
        var bad: u8[>..] = [];
        bad.push('O');
        let wk = sample_amend(wopts, k, bad);
        assert(wk != 0);
        assert(bad.len == 1);
        k += 1;
    }
    // A scheme id with no name is a valid original party.
    assert(swap_debit(text, "<Nm>Old Creditor</Nm>", "", "<Zz>", "<Zz>") == payment_file::F_NONE);
    // The reader refuses a second copy, a false indicator, an agent
    // with both forms, a bad IBAN, a bad date and a missing FinInstnId.
    assert(swap_debit(text, "<OrgnlMndtId>OLD-MANDATE</OrgnlMndtId>", "<OrgnlMndtId>A</OrgnlMndtId><OrgnlMndtId>B</OrgnlMndtId>", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<AmdmntInd>true</AmdmntInd>", "<AmdmntInd>false</AmdmntInd>", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<Id>SMNDA</Id>", "<Id>SMNDA</Id></Othr><BIC>ABNANL2A</BIC><Othr><Id>X</Id>", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<IBAN>NL91ABNA0417164300</IBAN></Id></OrgnlDbtrAcct>", "<IBAN>NL91ABNA0417164301</IBAN></Id></OrgnlDbtrAcct>", "<Zz>", "<Zz>") != payment_file::F_NONE);
    assert(swap_debit(text, "<OrgnlFnlColltnDt>2027-01-31</OrgnlFnlColltnDt>", "<OrgnlFnlColltnDt>2027-02-30</OrgnlFnlColltnDt>", "<Zz>", "<Zz>") == payment_file::F_DATE);
    assert(swap_debit(text, "<OrgnlDbtrAgt><FinInstnId><Othr><Id>SMNDA</Id></Othr></FinInstnId></OrgnlDbtrAgt>", "<OrgnlDbtrAgt></OrgnlDbtrAgt>", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
    assert(swap_debit(text, "<ElctrncSgntr>SIG-1</ElctrncSgntr>", "<ElctrncSgntr>A</ElctrncSgntr><ElctrncSgntr>B</ElctrncSgntr>", "<Zz>", "<Zz>") == payment_file::F_SYNTAX);
}

// The service level comes back over a round trip in both messages.
fn test_service_level_round_trip() {
    var wopts = payment_file::PainWriteOptions { epc_charset: true, indent: false };
    var ropts = payment_file::PainOptions { skip_control_sum_check: false, check_iban: true, epc_charset: true };
    var lim = payment_file::default_limits();
    var out: u8[>..] = [];
    assert(sample(wopts, out) == 0);
    var h = payment_file::new_header();
    var pays: payment_file::PaymentInfo[>..] = [];
    var items: payment_file::CreditTransfer[>..] = [];
    var buf: u8[>..] = [];
    let text: const u8[:] = out[..];
    let r = payment_file::parse_pain001(text, lim, ropts, h, pays, items, buf);
    assert(r.kind == payment_file::F_NONE);
    assert(pays[0].service_level == "SEPA");
    var dout: u8[>..] = [];
    assert(sample_debit(wopts, dout) == 0);
    var h2 = payment_file::new_header();
    var blocks: payment_file::DebitInfo[>..] = [];
    var items2: payment_file::DirectDebit[>..] = [];
    var buf2: u8[>..] = [];
    let r2 = payment_file::parse_pain008(dout, lim, ropts, h2, blocks, items2, buf2);
    assert(r2.kind == payment_file::F_NONE);
    assert(blocks[0].service_level == "SEPA");
    // The model holds the service level of the block.
    var own: u8[>..] = [];
    assert(sample_debit_level(wopts, "PRPT", own) == 0);
    assert(find(own, "<SvcLvl><Cd>PRPT</Cd></SvcLvl>") >= 0);
    var h3 = payment_file::new_header();
    var blocks3: payment_file::DebitInfo[>..] = [];
    var items3: payment_file::DirectDebit[>..] = [];
    var buf3: u8[>..] = [];
    let r3 = payment_file::parse_pain008(own, lim, ropts, h3, blocks3, items3, buf3);
    assert(r3.kind == payment_file::F_NONE);
    assert(blocks3[0].service_level == "PRPT");
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
    test_debit_parties_round_trip();
    test_debit_parties_order();
    test_anybic_and_lei();
    test_debit_write_atomic();
    test_debit_empty_names();
    test_debit_old_model_bytes();
    test_debit_reader_refusals();
    test_service_level();
    test_later_forms();
    test_proprietary_reference();
    test_service_level_round_trip();
    test_mandatory_elements();
    test_birth_and_pre_notification();
    test_amendment_details();
    test_code_lists();
    test_missing_amount();
    test_amount_overflow();
    test_blocks_tile_items();
    test_party_roundtrip();
    test_party_many();
    test_party_order();
    test_party_old_output();
    test_party_overlength();
    test_party_escape();
    test_party_refusals();
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
    test_mte_round_trip();
    test_cie_columns();
    test_mte_refusals();
    test_shr_terminal_required();
    test_name_rule();
    test_mte_reader_refusals();
    test_adv_round_trip();
    test_adv_columns();
    test_adv_refusals();
    test_adv_policy();
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
    e1.individual_name = "Receiver";
    e1.transaction_code = 27;
    e1.rdfi_routing = "121140399";
    e1.account = "00012345678";
    e1.amount = 100;
    e1.trace_number = "121140390000001";
    e1.addenda_start = 0;
    e1.addenda_count = 1;
    entries.push(e1);
    var e2 = payment_file::new_ach_entry();
    e2.individual_name = "Receiver";
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
    e.individual_name = "Receiver";
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
    e.individual_name = "Receiver";
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
    e.individual_name = "Receiver";
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
    e0.individual_name = "Receiver";
    e0.transaction_code = 22;
    e0.rdfi_routing = "121140399";
    e0.amount = 1;
    e0.trace_number = "121140390000001";
    e0.addenda_start = 0;
    e0.addenda_count = 1;
    entries.push(e0);
    var e1 = payment_file::new_ach_entry();
    e1.individual_name = "Receiver";
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
        // A terminal record of form 1 means two of them.
        if a_kind == 2 && a_form == 1 { e.addenda_count = 2; }
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
        if e.addenda_count == 2 { addenda.push(a); }
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

// bytes_at tells whether the bytes of the file at the position equal
// the text.
fn bytes_at(out: u8[>..]&, pos: i64, want: const u8[:]) -> bool {
    var k: i64 = 0;
    while k < want.len {
        if out[pos + k] != want[k] { return false; }
        k += 1;
    }
    return true;
}

fn test_mte_round_trip() {
    var out: u8[>..] = [];
    assert(sec_build("MTE", 27, 5000, 225, "", "ATM00000000000000000A1", "Receiver", "NY", 2, 0, out)
           == payment_file::F_NONE);
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out, bs, es, ads) == payment_file::F_NONE);
    assert(bs[0].sec_code == "MTE");
    assert(es.len == 1 && ads.len == 1);
    assert(es[0].individual_name == "Receiver");
    assert(es[0].individual_id == "ATM00000000000000000A1");
    assert(es[0].amount == 5000 && es[0].transaction_code == 27);
    assert(ads[0].kind == 2 && ads[0].state == "NY" && ads[0].terminal_id == "TERM01");
    // The name holds columns 40 to 54 and the id holds columns 55 to 76.
    let r = (find(out, "\n6") + 1);
    assert(r > 0);
    assert(bytes_at(out, r + 39, "Receiver       "));
    assert(bytes_at(out, r + 54, "ATM00000000000000000A1"));
}

fn test_cie_columns() {
    var out: u8[>..] = [];
    assert(sec_build("CIE", 22, 100, 220, "", "12345678901234567890AB", "ABCDEFGHIJKLMNO", "NY", 0, 0, out)
           == payment_file::F_NONE);
    let r = (find(out, "\n6") + 1);
    assert(r > 0);
    assert(bytes_at(out, r + 39, "ABCDEFGHIJKLMNO"));
    assert(bytes_at(out, r + 54, "12345678901234567890AB"));
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out, bs, es, ads) == payment_file::F_NONE);
    assert(es[0].individual_name == "ABCDEFGHIJKLMNO");
    assert(es[0].individual_id == "12345678901234567890AB");
    // A PPD entry keeps the other order.
    var out2: u8[>..] = [];
    assert(sec_build("PPD", 22, 100, 220, "", "123456789012345", "Receiver", "NY", 0, 0, out2)
           == payment_file::F_NONE);
    let r2 = (find(out2, "\n6") + 1);
    assert(bytes_at(out2, r2 + 39, "123456789012345"));
    assert(bytes_at(out2, r2 + 54, "Receiver"));
}

fn test_mte_refusals() {
    var out: u8[>..] = [];
    let id = "ATM00000000000000000A1";
    // No terminal record, and two of them.
    assert(sec_build("MTE", 27, 100, 225, "", id, "Receiver", "NY", 0, 0, out) == payment_file::F_LIMIT);
    assert(sec_build("MTE", 27, 100, 225, "", id, "Receiver", "NY", 2, 1, out) == payment_file::F_LIMIT);
    // A zero amount.
    assert(sec_build("MTE", 27, 0, 225, "", id, "Receiver", "NY", 2, 0, out) == payment_file::F_AMOUNT);
    assert(sec_build("MTE", 27, 1, 225, "", id, "Receiver", "NY", 2, 0, out) == payment_file::F_NONE);
    // A blank or all-zero identification number or name.
    assert(sec_build("MTE", 27, 100, 225, "", "", "Receiver", "NY", 2, 0, out) == payment_file::F_SYNTAX);
    assert(sec_build("MTE", 27, 100, 225, "", "0000000000", "Receiver", "NY", 2, 0, out) == payment_file::F_SYNTAX);
    assert(sec_build("MTE", 27, 100, 225, "", id, "  ", "NY", 2, 0, out) == payment_file::F_SYNTAX);
    // The widths: 15 for the name and 22 for the id, never cut.
    assert(sec_build("MTE", 27, 100, 225, "", id, "ABCDEFGHIJKLMNOP", "NY", 2, 0, out) != payment_file::F_NONE);
    assert(sec_build("MTE", 27, 100, 225, "", "ATM00000000000000000A12", "Receiver", "NY", 2, 0, out)
           != payment_file::F_NONE);
    // A state outside the list.
    assert(sec_build("MTE", 27, 100, 225, "", id, "Receiver", "ZZ", 2, 0, out) != payment_file::F_NONE);
    // A terminal record on a code that takes none.
    assert(sec_build("PPD", 22, 100, 220, "", "123", "Receiver", "NY", 2, 0, out) == payment_file::F_LIMIT);
    // ADV stays refused.
    assert(sec_build("ADV", 27, 100, 225, "", id, "Receiver", "NY", 2, 0, out) != payment_file::F_NONE);
}

fn test_shr_terminal_required() {
    var out: u8[>..] = [];
    assert(sec_build("SHR", 22, 100, 220, "21", "12280000000001", "A", "NY", 0, 0, out)
           == payment_file::F_LIMIT);
    // The reader refuses an SHR batch with no terminal record. Build a
    // PPD file and change its SEC code to SHR.
    assert(sec_build("PPD", 22, 100, 220, "21", "12280000000001", "A", "NY", 0, 0, out)
           == payment_file::F_NONE);
    let h = (find(out, "\n5") + 1);
    assert(h > 0);
    out[h + 50] = 'S'; out[h + 51] = 'H'; out[h + 52] = 'R';
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out, bs, es, ads) == payment_file::F_LIMIT);
}

fn test_mte_reader_refusals() {
    var out: u8[>..] = [];
    // An entry with no terminal record, relabelled MTE, is a fault.
    assert(sec_build("PPD", 27, 100, 225, "", "ATM0000000000A1", "Receiver", "NY", 0, 0, out)
           == payment_file::F_NONE);
    let h = (find(out, "\n5") + 1);
    assert(h > 0);
    out[h + 50] = 'M'; out[h + 51] = 'T'; out[h + 52] = 'E';
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out, bs, es, ads) == payment_file::F_LIMIT);
    // A blank name on a PPD entry is a fault.
    var out2: u8[>..] = [];
    assert(sec_build("PPD", 22, 100, 220, "", "123", "Receiver", "NY", 0, 0, out2) == payment_file::F_NONE);
    let r2 = (find(out2, "\n6") + 1);
    var k: i64 = 54;
    while k < 76 { out2[r2 + k] = ' '; k += 1; }
    var bs2: payment_file::AchBatch[>..] = [];
    var es2: payment_file::AchEntry[>..] = [];
    var ads2: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out2, bs2, es2, ads2) == payment_file::F_SYNTAX);
    // A zero amount in an MTE file is a fault.
    var out3: u8[>..] = [];
    assert(sec_build("MTE", 27, 100, 225, "", "ATM00000000000000000A1", "Receiver", "NY", 2, 0, out3)
           == payment_file::F_NONE);
    let r3 = (find(out3, "\n6") + 1);
    k = 29;
    while k < 39 { out3[r3 + k] = '0'; k += 1; }
    var bs3: payment_file::AchBatch[>..] = [];
    var es3: payment_file::AchEntry[>..] = [];
    var ads3: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out3, bs3, es3, ads3) != payment_file::F_NONE);
}

// adv_build writes a file with one advice batch of two entries.
fn adv_build(code2: i64, name: const u8[:], out: u8[>..]&) -> i32 {
    return adv_build_mode(code2, name, 0, out);
}

// adv_build_mode breaks one rule of the batch: 1 blank account, 2 Julian
// day 0, 3 sequence 0, 4 equal sequence numbers, 5 service class 200,
// 6 originator status 1, 7 a second batch whose entry range wraps an i32.
fn adv_build_mode(code2: i64, name: const u8[:], mode: i64, out: u8[>..]&) -> i32 {
    var entries: payment_file::AdvEntry[>..] = [];
    var e = payment_file::new_adv_entry();
    e.transaction_code = 81;
    e.rdfi_routing = "121140399";
    e.account = "00012345678";
    e.amount = 123456;
    e.advice_routing_number = "021000021";
    e.file_identification = "FILE1";
    e.ach_operator_data = "A";
    e.individual_name = name;
    e.discretionary = "DD";
    e.ach_operator_routing_number = "12114039";
    e.julian_day = 313;
    e.sequence_number = 1;
    entries.push(e);
    var e2 = e;
    e2.transaction_code = code2;
    e2.amount = 99999999999;
    e2.sequence_number = 2;
    if mode == 1 { e2.account = ""; }
    if mode == 2 { e2.julian_day = 0; }
    if mode == 3 { e2.sequence_number = 0; }
    if mode == 4 { e2.sequence_number = 1; }
    entries.push(e2);
    var batches: payment_file::AchBatch[>..] = [];
    var b = payment_file::new_ach_batch();
    b.service_class = 280;
    if mode == 5 { b.service_class = 200; }
    b.company_name = "Acme Corp";
    b.company_id = "1234567890";
    b.sec_code = "ADV";
    b.description = "ADVICE";
    b.effective_year = 2026; b.effective_month = 11; b.effective_day = 10;
    b.originator_status = 0;
    if mode == 6 { b.originator_status = 1; }
    b.odfi_id = "12114039";
    b.batch_number = 1;
    b.entry_start = 0;
    b.entry_count = 2;
    batches.push(b);
    if mode == 7 {
        batches[0].entry_count = 1;
        var b2 = b;
        b2.batch_number = 2;
        b2.entry_start = 1;
        b2.entry_count = 2147483647;
        batches.push(b2);
    }
    var h = payment_file::new_ach_file_header();
    h.destination_routing = "121140399";
    h.origin_id = "1234567890";
    h.creation_year = 2026; h.creation_month = 11; h.creation_day = 9;
    h.creation_hour = 14; h.creation_minute = 30;
    h.id_modifier = "A";
    h.destination_name = "Bank";
    h.origin_name = "Corp";
    var lim = payment_file::default_limits();
    return payment_file::write_ach_adv(h, batches, entries, lim, out).kind;
}

fn adv_parse(out: u8[>..]&, es: payment_file::AdvEntry[>..]&) -> i32 {
    var h = payment_file::new_ach_file_header();
    var lim = payment_file::default_limits();
    var opts = payment_file::new_ach_options();
    var bs: payment_file::AchBatch[>..] = [];
    return payment_file::parse_ach_adv(out, opts, lim, h, bs, es).kind;
}

fn test_adv_round_trip() {
    var out: u8[>..] = [];
    assert(adv_build(84, "Receiver", out) == payment_file::F_NONE);
    // 6 records pad to one block of 10.
    assert(out.len == 10 * 95);
    var es: payment_file::AdvEntry[>..] = [];
    assert(adv_parse(out, es) == payment_file::F_NONE);
    assert(es.len == 2);
    assert(es[0].transaction_code == 81 && es[0].amount == 123456);
    assert(es[0].rdfi_routing == "121140399" && es[0].account == "00012345678");
    assert(es[0].advice_routing_number == "021000021" && es[0].file_identification == "FILE1");
    assert(es[0].individual_name == "Receiver" && es[0].julian_day == 313);
    assert(es[1].transaction_code == 84 && es[1].amount == 99999999999);
    assert(es[1].sequence_number == 2);
}

fn test_adv_columns() {
    var out: u8[>..] = [];
    assert(adv_build(84, "Receiver", out) == payment_file::F_NONE);
    let r = find(out, "\n6") + 1;
    assert(out[r + 1] == '8' && out[r + 2] == '1');
    assert(bytes_at(out, r + 3, "12114039"));
    assert(out[r + 11] == '9');
    assert(bytes_at(out, r + 27, "000000123456"));
    assert(bytes_at(out, r + 39, "021000021"));
    assert(bytes_at(out, r + 48, "FILE1A"));
    assert(bytes_at(out, r + 54, "Receiver"));
    assert(out[r + 78] == '0');
    assert(bytes_at(out, r + 79, "12114039"));
    assert(bytes_at(out, r + 87, "3130001"));
    // The batch control holds twenty digit totals: debit then credit.
    let c = find(out, "\n8") + 1;
    assert(bytes_at(out, c + 1, "280000002"));
    assert(bytes_at(out, c + 20, "00000000099999999999"));
    assert(bytes_at(out, c + 40, "00000000000000123456"));
    // The file control holds the same totals at columns 32 to 71.
    let f = find(out, "\n9") + 1;
    assert(bytes_at(out, f + 31, "00000000099999999999"));
    assert(bytes_at(out, f + 51, "00000000000000123456"));
    assert(out[f + 71] == ' ' && out[f + 93] == ' ');
}

fn test_adv_policy() {
    // The normal writer refuses an advice batch.
    var out: u8[>..] = [];
    assert(sec_build("ADV", 27, 100, 280, "", "123", "Receiver", "NY", 0, 0, out)
           == payment_file::F_SYNTAX);
    assert(out.len == 0);
    // The normal reader refuses an advice batch.
    var out2: u8[>..] = [];
    assert(adv_build(84, "Receiver", out2) == payment_file::F_NONE);
    var bs: payment_file::AchBatch[>..] = [];
    var es: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out2, bs, es, ads) != payment_file::F_NONE);
    // The advice routing number holds nine digits. The operator
    // routing number holds eight digits. A byte that is no digit in
    // either field is a fault.
    let spots: i64[>..] = [39, 86];
    var si: i64 = 0;
    while si < spots.len {
        var out3: u8[>..] = [];
        assert(adv_build(84, "Receiver", out3) == payment_file::F_NONE);
        let r3 = find(out3, "\n6") + 1;
        out3[r3 + spots[si]] = 'A';
        var es3: payment_file::AdvEntry[>..] = [];
        assert(adv_parse(out3, es3) == payment_file::F_SYNTAX);
        si += 1;
    }
}

fn test_adv_refusals() {
    var out: u8[>..] = [];
    assert(adv_build(40, "Receiver", out) == payment_file::F_SYNTAX);
    assert(adv_build(84, "", out) == payment_file::F_SYNTAX);
    assert(adv_build_mode(84, "Receiver", 1, out) == payment_file::F_SYNTAX);
    assert(adv_build_mode(84, "Receiver", 2, out) == payment_file::F_DATE);
    assert(adv_build_mode(84, "Receiver", 3, out) == payment_file::F_LIMIT);
    assert(adv_build_mode(84, "Receiver", 4, out) == payment_file::F_TOTAL);
    assert(adv_build_mode(84, "Receiver", 5, out) == payment_file::F_SYNTAX);
    assert(adv_build_mode(84, "Receiver", 6, out) == payment_file::F_SYNTAX);
    assert(adv_build_mode(84, "Receiver", 7, out) == payment_file::F_LIMIT);
    assert(out.len == 0);
    // A flipped byte of the debit total is a fault.
    assert(adv_build(84, "Receiver", out) == payment_file::F_NONE);
    let c = find(out, "\n8") + 1;
    out[c + 39] = '7';
    var es: payment_file::AdvEntry[>..] = [];
    assert(adv_parse(out, es) == payment_file::F_TOTAL);
    // A normal file control record is no advice file control.
    var out2: u8[>..] = [];
    assert(adv_build(84, "Receiver", out2) == payment_file::F_NONE);
    let f = find(out2, "\n9") + 1;
    var k: i64 = 55;
    while k < 71 { out2[f + k] = ' '; k += 1; }
    var es2: payment_file::AdvEntry[>..] = [];
    assert(adv_parse(out2, es2) != payment_file::F_NONE);
    // The reader holds the blank rules of the writer.
    var cuts: i64[>..] = [12, 39, 48, 54, 79];
    var ci: i64 = 0;
    while ci < cuts.len {
        var o4: u8[>..] = [];
        assert(adv_build(84, "Receiver", o4) == payment_file::F_NONE);
        let r4 = find(o4, "\n6") + 1;
        let from = cuts[ci];
        var to = from + 15;
        if from == 39 { to = from + 9; }
        if from == 48 { to = from + 5; }
        if from == 54 { to = from + 22; }
        if from == 79 { to = from + 8; }
        var q: i64 = from;
        while q < to { o4[r4 + q] = ' '; q += 1; }
        var es4: payment_file::AdvEntry[>..] = [];
        assert(adv_parse(o4, es4) == payment_file::F_SYNTAX);
        ci += 1;
    }
    // An addenda indicator of 1 is a fault.
    var o5: u8[>..] = [];
    assert(adv_build(84, "Receiver", o5) == payment_file::F_NONE);
    let r5 = find(o5, "\n6") + 1;
    o5[r5 + 78] = '1';
    var es5: payment_file::AdvEntry[>..] = [];
    assert(adv_parse(o5, es5) == payment_file::F_LIMIT);
    // A normal file with a wide file control record is refused.
    var o6: u8[>..] = [];
    assert(sec_build("PPD", 22, 100, 220, "", "123", "Receiver", "NY", 0, 0, o6) == payment_file::F_NONE);
    let f6 = find(o6, "\n9") + 1;
    o6[f6 + 60] = '1';
    var bs6: payment_file::AchBatch[>..] = [];
    var es6: payment_file::AchEntry[>..] = [];
    var ad6: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(o6, bs6, es6, ad6) == payment_file::F_SYNTAX);
    // A total that does not fit an i64 is a fault, not a wrapped value.
    var o7: u8[>..] = [];
    assert(adv_build(84, "Receiver", o7) == payment_file::F_NONE);
    let c7 = find(o7, "\n8") + 1;
    var w: i64 = 0;
    while w < 20 { o7[c7 + 20 + w] = '9'; w += 1; }
    var es7: payment_file::AdvEntry[>..] = [];
    assert(adv_parse(o7, es7) == payment_file::F_OVERFLOW);
    // A batch with no entry is a fault.
    var o8: u8[>..] = [];
    assert(adv_build(84, "Receiver", o8) == payment_file::F_NONE);
    let r8 = find(o8, "\n6") + 1;
    // Drop the two entry records and put the control record in their place.
    var o8b: u8[>..] = [];
    var w8: i64 = 0;
    while w8 < o8.len {
        if w8 == r8 { w8 = r8 + 190; continue; }
        o8b.push(o8[w8]);
        w8 += 1;
    }
    var es8: payment_file::AdvEntry[>..] = [];
    assert(adv_parse(o8b, es8) == payment_file::F_SYNTAX);
    // The control record must agree with the batch header.
    var o9: u8[>..] = [];
    assert(adv_build(84, "Receiver", o9) == payment_file::F_NONE);
    let c9 = find(o9, "\n8") + 1;
    o9[c9 + 79] = '9';
    var es9: payment_file::AdvEntry[>..] = [];
    assert(adv_parse(o9, es9) == payment_file::F_TOTAL);
    // The normal reader refuses an advice file.
    var out3: u8[>..] = [];
    assert(adv_build(84, "Receiver", out3) == payment_file::F_NONE);
    var bs: payment_file::AchBatch[>..] = [];
    var es3: payment_file::AchEntry[>..] = [];
    var ads: payment_file::AchAddenda[>..] = [];
    assert(sec_parse(out3, bs, es3, ads) != payment_file::F_NONE);
}

fn test_name_rule() {
    var out: u8[>..] = [];
    assert(sec_build("PPD", 22, 100, 220, "", "123", "", "NY", 0, 0, out) == payment_file::F_SYNTAX);
    assert(sec_build("PPD", 22, 100, 220, "", "123", "000", "NY", 0, 0, out) == payment_file::F_SYNTAX);
    assert(sec_build("PPD", 22, 100, 220, "", "123", "A", "NY", 0, 0, out) == payment_file::F_NONE);
    // CCD holds no name rule.
    assert(sec_build("CCD", 22, 100, 220, "", "123", "", "NY", 0, 0, out) == payment_file::F_NONE);
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
