// payment_file - the files that start a payment, for Goose.
//
// The package writes and reads the SEPA pain.001 credit transfer
// initiation and the pain.008 direct debit initiation. Money is an integer count of minor units. The package
// uses no float. Every parse is one linear pass with no recursion and
// bounded sizes.
//
// The repository is goose-payment-file. The import name is
// "payment_file".
namespace payment_file;

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
import fault;
import model;
import model_debit;
import enums;
import charset;
import control;
import write_pain;
import read_pain;
import write_pain008;
import read_pain008;

// Limits bounds every size the package touches. The defaults are
// safe; a caller may lower them.
struct Limits {
    max_input: i64,
    max_payments: i64,
    max_items: i64,
    max_nesting: i64,
    max_text: i64,
}

// default_limits gives the limits of the package. A caller may lower
// them, never raise them.
fn default_limits() -> Limits {
    return Limits {
        max_input: 16777216,
        max_payments: 100,
        max_items: 10000,
        max_nesting: 16,
        max_text: 140,
    };
}
