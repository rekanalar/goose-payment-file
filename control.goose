// The control sum and the amount text.
//
// The control sum of a payment block is the sum of the item amounts.
// The amounts are exact minor units, so the sum adds integers with an
// overflow check. The text of an amount holds the decimal point of
// the currency exponent, with no float.
namespace payment_file;

import std;
import finance from "rekanalar/goose-finance@v0.1.0";
import fault;
import model;
import model_debit;

// checked_add gives the sum of two values. It gives false when the
// sum does not fit in an i64.
fn checked_add(a: i64, b: i64) -> i64, bool {
    if b > 0 && a > 9223372036854775807 - b { return 0, false; }
    if b < 0 && a < -9223372036854775807 - 1 - b { return 0, false; }
    return a + b, true;
}

// add_minor adds one amount to a running sum. The schema allows no
// negative amount, and the sum must fit in an i64.
fn add_minor(sum: i64, minor: i64) -> i64, Fault {
    if minor < 0 { return 0, fault(F_AMOUNT, 0, 0, "Amt", "the schema allows no negative amount"); }
    let s, ok = checked_add(sum, minor);
    if !ok { return 0, fault(F_OVERFLOW, 0, 0, "CtrlSum", "the sum of the amounts does not fit"); }
    return s, no_fault();
}

// fold_item adds one item to a running sum. The item must hold the
// currency of the first item of the range.
fn fold_item(sum: i64, ccy: const u8[:], code: const u8[:], minor: i64) -> i64, Fault {
    if code != ccy { return 0, fault(F_AMOUNT, 0, 0, "Amt", "the items hold two currencies"); }
    return add_minor(sum, minor);
}

// range_fault checks that an item range sits inside the items.
fn range_fault(start: i64, count: i64, len: i64) -> Fault {
    if start < 0 || count < 0 || start + count > len {
        return fault(F_LIMIT, 0, 0, "PmtInf", "the item range of the block reaches past the items");
    }
    return no_fault();
}

// sum_range gives the sum of the items items[start .. start + count] as
// minor units. The items must hold one currency and no negative amount.
fn sum_range(items: CreditTransfer[>..]&, start: i64, count: i64) -> i64, Fault {
    let rf = range_fault(start, count, items.len);
    if rf.kind != F_NONE { return 0, rf; }
    if count == 0 { return 0, no_fault(); }
    let ccy = items[start].amount.code;
    var sum: i64 = 0;
    var k: i64 = 0;
    while k < count {
        let s, af = fold_item(sum, ccy, items[start + k].amount.code, items[start + k].amount.minor);
        if af.kind != F_NONE { return 0, af; }
        sum = s;
        k += 1;
    }
    return sum, no_fault();
}

// sum_debits is sum_range for the items of a direct debit.
fn sum_debits(items: DirectDebit[>..]&, start: i64, count: i64) -> i64, Fault {
    let rf = range_fault(start, count, items.len);
    if rf.kind != F_NONE { return 0, rf; }
    if count == 0 { return 0, no_fault(); }
    let ccy = items[start].amount.code;
    var sum: i64 = 0;
    var k: i64 = 0;
    while k < count {
        let s, af = fold_item(sum, ccy, items[start + k].amount.code, items[start + k].amount.minor);
        if af.kind != F_NONE { return 0, af; }
        sum = s;
        k += 1;
    }
    return sum, no_fault();
}

// amount_text writes the text of an amount: minor units with the
// decimal point of the currency exponent. The schema allows no
// negative amount. A currency with no minor unit in the table is a fault.
fn amount_text(out: u8[>..]&, minor: i64, code: const u8[:]) -> Fault {
    let exp = finance::currency_exponent(code) as i64;
    if exp < 0 { return fault(F_AMOUNT, 0, 0, "Amt", "the currency is not in the currency table"); }
    if minor < 0 { return fault(F_AMOUNT, 0, 0, "Amt", "the schema allows no negative amount"); }
    var v = minor;
    var digits: u8[>..] = [];
    if v == 0 { digits.push('0'); }
    while v > 0 {
        digits.push(('0' + (v % 10)) as u8);
        v = v / 10;
    }
    // The integer part needs at least one digit before the point.
    while digits.len <= exp { digits.push('0'); }
    var k = digits.len;
    while k > 0 {
        k -= 1;
        out.push(digits[k]);
        if k == exp && exp > 0 { out.push('.'); }
    }
    return no_fault();
}
