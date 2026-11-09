// The EPC character set and the text length rules.
//
// The SSR1 set of the EPC lists the characters that a SEPA text may
// hold: the Latin letters, the digits, the space and one punctuation
// group. A control byte is never allowed. A text may not end in ?,
// because the EPC list reserves a trailing ? for an escape pair. The
// limits are 35 for an id and 140 for a remittance text, as in the
// schemas. A name has 140 in the schemas and 70 in the EPC rulebook.
namespace payment_file;

import std;
import fault;

// put appends a text to a builder.
fn put(out: u8[>..]&, s: const u8[:]) {
    var i: i64 = 0;
    while i < s.len { out.push(s[i]); i += 1; }
}

// epc_ok tells whether every byte of the text sits in the EPC set.
fn epc_ok(text: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < text.len {
        let c = text[i];
        if c >= 'a' && c <= 'z' { i += 1; continue; }
        if c >= 'A' && c <= 'Z' { i += 1; continue; }
        if c >= '0' && c <= '9' { i += 1; continue; }
        if c == ' ' || c == '-' || c == '?' || c == ':' || c == '(' || c == ')'
           || c == '.' || c == ',' || c == '\'' || c == '+' || c == '/' {
            i += 1;
            continue;
        }
        return false;
    }
    if text.len > 0 && text[text.len - 1] == '?' { return false; }
    return true;
}

// check_text checks one text against the EPC set and a length limit.
// The flag turns the set check off, never the length check. The limit
// of the caller and the limit of the package both hold: the shorter
// one wins.
fn check_text(text: const u8[:], max: i64, tag: const u8[:], epc: bool, lim: Limits&) -> Fault {
    var bound = max;
    if lim.max_text < bound { bound = lim.max_text; }
    if text.len > bound {
        return fault(F_LIMIT, 0, 0, tag, "the text is longer than the schema allows");
    }
    var i: i64 = 0;
    while i < text.len {
        let c = text[i];
        if c < ' ' || c == 127 {
            return fault(F_CHARSET, 0, 0, tag, "the text holds a control byte");
        }
        i += 1;
    }
    if find(text, "\n") >= 0 || find(text, "\r") >= 0 {
        return fault(F_CHARSET, 0, 0, tag, "the text holds a line end");
    }
    if epc && !epc_ok(text) {
        return fault(F_CHARSET, 0, 0, tag, "the text holds a byte outside the EPC set");
    }
    return no_fault();
}
