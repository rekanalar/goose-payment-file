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
