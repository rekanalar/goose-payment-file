[![ci](https://github.com/rekanalar/goose-payment-file/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-payment-file/actions/workflows/ci.yml)

# payment_file - the files that start a payment, for Goose.

The package writes and reads the SEPA `pain.001` credit transfer
initiation. The writer emits the pain.001.001.03 form that the bank
portals take. The reader takes any schema version from `.001.03` to
`.001.10` by element name.

Money is an integer count of minor units with the exponent of its
currency. The package uses no float.
Every parse is one linear pass with no recursion. Every size has a limit.

## Install

Add these lines to the root file of the program that uses it:

```goose
import payment_file from "rekanalar/goose-payment-file@v0.1.0";
import xml from "rekanalar/goose-xml@v2.0.0";
import finance from "rekanalar/goose-finance@v0.1.0";
import payment_identifier from "rekanalar/goose-payment-identifier@v0.1.0";
```

A package that needs another package must have that package declared in
the root file of the program. If a line is missing, the compiler names
the line to add.

## API

| Name | What it does |
|---|---|
| `write_pain001(header, payments, items, opts, lim, out)` | writes the credit transfer as pain.001.001.03 XML |
| `parse_pain001(input, lim, opts, header, payments, items, buf)` | reads any schema version into the model |
| `GrpHeader` | the message id, the creation time, the count, the control sum, the initiator |
| `PaymentInfo` | one payment block: the id, the flags, the debtor, the execution date, the item range |
| `CreditTransfer` | one item: the ids, the amount, the creditor, the purpose, the remittance |
| `new_header()`, `new_payment()`, `new_transfer()` | the zero values of the three structs |
| `default_limits()` | the safe limits |
| `PainOptions` | the reader switches: `skip_control_sum_check`, `check_iban`, `epc_charset` |
| `PainWriteOptions` | the writer switches: `epc_charset`, `indent` |
| `kind_name(kind)` | the name of a fault kind |

## The checks

The reader and the writer check every text. The EPC
character set takes the Latin letters, the digits, the space and one
punctuation group. A control byte and a line end are never allowed.

The schemas allow 35 bytes for an id, 140 for a name and 140 for a
remittance. The EPC rulebook limits a name to 70. The writer keeps 70,
so a bank accepts the file. The reader takes up to 140.

The reader adds the item amounts. It compares the total with the
control sum of the group header and of each payment block. The compare
uses the value, so `103.0000` equals `103.00`. A mismatch is a fault
with the two sums. The reader also checks the count of each block. The
option `skip_control_sum_check` turns the sum check off.

The writer needs the creation time and the execution date, because the
schema makes both mandatory. It writes the elements in schema order.
An amount below zero is a fault in the reader and in the writer.

The reader passes every IBAN to the check digits of
`goose-payment-identifier`. A failure is a fault. The option
`check_iban` turns the check off.

## Limits

- **The writer emits the pain.001.001.03 form only.** The reader takes
  the versions `.001.03` to `.001.10`. Python `sepaxml` writes the
  same form.
- **The writer computes the control sum from the items.** The caller
  cannot set it. A caller who needs another total writes the file by
  hand.
- **pain.008, NACHA and `pacs.008` stay out.** A later release adds
  them.
- **The application header, the authorization element and the category
  purpose stay out.** The full external code lists stay out too. The
  reader ignores them.
- **A date holds no timezone of its own.** The execution date is a
  civil date, as the schema says.
- **The reader reads the first remittance text only.** It ignores the
  other texts and the other structured fields.
- **After a fault the arrays hold partial results.** Do not use them.

## Security

Protections beyond the reference libraries:

- **The writer escapes every text.** Python `sepaxml` writes a name
  raw, so a name with `</Nm>` can end the element. This package
  writes `&`, `<` and `>` as entities.
- **The EPC set and the control bytes are faults.** `sepaxml` escapes
  a control byte as an entity. The bank then rejects the file. This
  package refuses the text before the file leaves the program.
- **The control sum and the IBANs are checked.** `sepaxml` sums the
  amounts as a float. It writes the total as it comes. This package
  adds minor units with an overflow check. It faults on a mismatch.
- **The amounts are exact.** An amount is minor units of the
  currency. No call of the package puts a float into an amount.
- **Every size has a limit.** The limits cover the input, the payment
  blocks, the items and the texts. `default_limits()` holds safe
  values.
- **No entity expands.** The package `goose-xml` skips a doctype and
  never expands an entity.
- **No recursion, linear time.** A hostile file cannot overflow the
  stack or make the parser slow down.

Risks that stay:

- **The names and the remittance texts are untrusted.** The package
  checks the character set. Escape them yourself for HTML, SQL, a
  path or a command.
- **The default input limit is 16 MiB.** Lower it when you read from
  a form upload.

## License

MIT. See the LICENSE file.
