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

// currency_code_ok tells whether a text is an ISO currency code:
// three capital letters.
fn currency_code_ok(s: const u8[:]) -> bool {
    if s.len != 3 { return false; }
    var i: i64 = 0;
    while i < 3 {
        if s[i] < 'A' || s[i] > 'Z' { return false; }
        i += 1;
    }
    return true;
}

// branch_country_ok tells whether a text is a branch country code of
// an IAT addenda: two or three capital letters or digits.
fn branch_country_ok(s: const u8[:]) -> bool {
    if s.len != 2 && s.len != 3 { return false; }
    var i: i64 = 0;
    while i < s.len {
        let c = s[i];
        if !((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) { return false; }
        i += 1;
    }
    return true;
}

// fx_indicator_ok tells whether a text is a foreign exchange
// indicator of an IAT batch.
fn fx_indicator_ok(s: const u8[:]) -> bool {
    return s == "FV" || s == "VF" || s == "FF";
}

// noc_code_ok tells whether a text is a notice of change code of the
// list: C01 to C09, C13, C14 and C61 to C69.
fn noc_code_ok(s: const u8[:]) -> bool {
    if s.len != 3 { return false; }
    if s[0] != 'C' { return false; }
    if !(s[1] >= '0' && s[1] <= '6') { return false; }
    if s[1] == '0' { return s[2] >= '1' && s[2] <= '9'; }
    if s[1] == '1' { return s[2] == '3' || s[2] == '4'; }
    if s[1] == '6' { return s[2] >= '1' && s[2] <= '9'; }
    return false;
}

// return_code_ok tells whether a text is a return reason code of the
// list of the package: R01 to R47, R50 to R53, R61, R62, R67 to R77,
// R80 to R85 and R90.
fn return_code_ok(s: const u8[:]) -> bool {
    if s.len != 3 { return false; }
    if s[0] != 'R' { return false; }
    if !(s[1] >= '0' && s[1] <= '9') { return false; }
    if !(s[2] >= '0' && s[2] <= '9') { return false; }
    let v = (s[1] - '0') as i64 * 10 + (s[2] - '0') as i64;
    if v <= 47 { return v >= 1; }
    if v <= 53 { return v >= 50; }
    if v == 61 || v == 62 { return true; }
    if v <= 77 { return v >= 67; }
    if v <= 85 { return v >= 80; }
    return v == 90;
}

// dishonor_code_ok tells whether a text is a dishonored return
// reason code: R61, R62 and R67 to R70.
fn dishonor_code_ok(s: const u8[:]) -> bool {
    if s.len != 3 { return false; }
    if s[0] != 'R' { return false; }
    if !(s[1] >= '0' && s[1] <= '9') { return false; }
    if !(s[2] >= '0' && s[2] <= '9') { return false; }
    let v = (s[1] - '0') as i64 * 10 + (s[2] - '0') as i64;
    if v == 61 || v == 62 { return true; }
    if v <= 70 { return v >= 67; }
    return false;
}

// contest_code_ok tells whether a text is a contested return reason
// code: R71 to R77.
fn contest_code_ok(s: const u8[:]) -> bool {
    if s.len != 3 { return false; }
    if s[0] != 'R' { return false; }
    if !(s[1] >= '0' && s[1] <= '9') { return false; }
    if !(s[2] >= '0' && s[2] <= '9') { return false; }
    let v = (s[1] - '0') as i64 * 10 + (s[2] - '0') as i64;
    return v >= 71 && v <= 77;
}

// us_state_ok tells whether a text is a postal abbreviation of a
// state or territory of the United States.
fn us_state_ok(s: const u8[:]) -> bool {
    if s.len != 2 { return false; }
    if s == "AK" || s == "AL" || s == "AR" || s == "AS" || s == "AZ" { return true; }
    if s == "CA" || s == "CO" || s == "CT" || s == "DC" || s == "DE" { return true; }
    if s == "FL" || s == "FT" || s == "GA" || s == "GU" || s == "HI" { return true; }
    if s == "IA" || s == "ID" || s == "IL" || s == "IN" || s == "KS" { return true; }
    if s == "KY" || s == "LA" || s == "MA" || s == "MD" || s == "ME" { return true; }
    if s == "MI" || s == "MN" || s == "MO" || s == "MP" || s == "MS" { return true; }
    if s == "MT" || s == "NC" || s == "ND" || s == "NE" || s == "NH" { return true; }
    if s == "NJ" || s == "NM" || s == "NV" || s == "NY" || s == "OH" { return true; }
    if s == "OK" || s == "OR" || s == "PA" || s == "PR" || s == "RI" { return true; }
    if s == "SC" || s == "SD" || s == "TN" || s == "TX" || s == "UT" { return true; }
    if s == "VA" || s == "VI" || s == "VT" || s == "WA" || s == "WI" { return true; }
    return s == "WV" || s == "WY";
}

// card_type_ok tells whether a text is a card transaction type of a
// SHR or POS entry.
fn card_type_ok(s: const u8[:]) -> bool {
    if s.len != 2 { return false; }
    return s == "01" || s == "02" || s == "03" || s == "11"
        || s == "12" || s == "13" || s == "21" || s == "99";
}

// txn_type_code_ok tells whether a text is a transaction type code of
// the list of addenda 10.
fn txn_type_code_ok(s: const u8[:]) -> bool {
    if s == "ANN" || s == "BUS" || s == "DEP" || s == "LOA" { return true; }
    if s == "MIS" || s == "MOR" || s == "PEN" || s == "REM" { return true; }
    if s == "RLS" || s == "SAL" || s == "TAX" || s == "PAY" { return true; }
    if s == "ARC" || s == "BOC" || s == "IAT" || s == "MTE" { return true; }
    if s == "POP" || s == "POS" || s == "RCK" || s == "SHR" { return true; }
    return s == "TEL" || s == "WEB";
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

// doc_type_ok tells whether the text is a document type code of the
// creditor reference of a structured remittance.
fn doc_type_ok(code: const u8[:]) -> bool {
    return code == "RADM" || code == "RPIN" || code == "FXDR"
        || code == "DISP" || code == "PUOR" || code == "SCOR";
}
