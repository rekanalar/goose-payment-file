// The code lists that a direct debit checks.
//
// The sequence type and the local instrument are short code lists of
// the SEPA rulebook. A value outside the list is a fault.
namespace payment_file;

import std;

// seq_type_ok tells whether the text is a sequence type.
fn seq_type_ok(s: const u8[:]) -> bool {
    return s == "FRST" || s == "RCUR" || s == "OOFF" || s == "FNAL";
}

// instrument_ok tells whether the text is a local instrument. COR1 is
// a withdrawn code that old files still hold.
fn instrument_ok(s: const u8[:]) -> bool {
    return s == "CORE" || s == "COR1" || s == "B2B";
}

// pay_method_ok tells whether the text is a payment method of a
// credit transfer.
fn pay_method_ok(s: const u8[:]) -> bool {
    return s == "TRF" || s == "CHK" || s == "TRA";
}

// charge_bearer_ok tells whether the text is a charge bearer code.
fn charge_bearer_ok(s: const u8[:]) -> bool {
    return s == "DEBT" || s == "CRED" || s == "SHAR" || s == "SLEV";
}

// bic_ok tells whether the text has the shape of a BIC: 8 or 11 bytes,
// capital letters and digits only.
fn bic_ok(s: const u8[:]) -> bool {
    if s.len != 8 && s.len != 11 { return false; }
    var i: i64 = 0;
    while i < s.len {
        let c = s[i];
        if !((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) { return false; }
        i += 1;
    }
    return true;
}

// settle_method_ok tells whether a text is a settlement method of the
// message: INDA, INGA, COVE or CLRG.
fn settle_method_ok(s: const u8[:]) -> bool {
    return s == "INDA" || s == "INGA" || s == "COVE" || s == "CLRG";
}

// country_ok tells whether a text is a country code: two capital
// letters.
fn country_ok(s: const u8[:]) -> bool {
    if s.len != 2 { return false; }
    if s[0] < 'A' || s[0] > 'Z' { return false; }
    if s[1] < 'A' || s[1] > 'Z' { return false; }
    return true;
}

// hex_lower tells whether a byte is a lowercase hexadecimal digit.
fn hex_lower(c: u8) -> bool {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
}

// uetr_ok tells whether a text is a version 4 UUID in lowercase
// hexadecimal: 8-4-4-4-12 with the version nibble 4 and the variant
// nibble 8, 9, a or b.
fn uetr_ok(s: const u8[:]) -> bool {
    if s.len != 36 { return false; }
    var i: i64 = 0;
    while i < 36 {
        let c = s[i];
        if i == 8 || i == 13 || i == 18 || i == 23 {
            if c != '-' { return false; }
        } else if i == 14 {
            if c != '4' { return false; }
        } else if i == 19 {
            if !(c == '8' || c == '9' || c == 'a' || c == 'b') { return false; }
        } else if !hex_lower(c) {
            return false;
        }
        i += 1;
    }
    return true;
}
