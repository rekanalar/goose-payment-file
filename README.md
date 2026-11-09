# goose-payment-file

[![ci](https://github.com/rekanalar/goose-payment-file/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-payment-file/actions/workflows/ci.yml)

The files that start a payment, for the [Goose](https://github.com/aardappel/goose) language.
The package writes and reads three files. They are the SEPA `pain.001`
credit transfer, the `pain.008` direct debit and the NACHA ACH file.
The SEPA writers emit the pain.001.001.03 and pain.008.001.02 forms
that the bank portals take. The readers take the versions `.001.03` to `.001.10` and
`.001.02` to `.001.08` by element name.

Money is an integer count of minor units with the exponent of its
currency. The package uses no float.
Every parse is one linear pass with no recursion. Every size has a limit.

## Install

Add these lines to the root file of the program that uses it:

```goose
import payment_file from "rekanalar/goose-payment-file@v0.3.0";
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
| `write_pain008(header, blocks, items, opts, lim, out)` | writes the direct debit as pain.008.001.02 XML |
| `parse_pain008(input, lim, opts, header, blocks, items, buf)` | reads a direct debit of `.001.02` to `.001.08` |
| `DebitInfo` | one debit block: the creditor, the scheme id, the sequence type, the instrument, the collection date, the item range |
| `DirectDebit` | one collection: the amount, the mandate, the debtor, the remittance |
| `new_debit_info()`, `new_direct_debit()` | the zero values of the two debit structs |
| `GrpHeader` | the message id, the creation time, the count, the control sum, the initiator |
| `PaymentInfo` | one payment block: the id, the flags, the debtor, the execution date, the item range |
| `CreditTransfer` | one item: the ids, the amount, the creditor, the purpose, the remittance |
| `new_header()`, `new_payment()`, `new_transfer()` | the zero values of the three structs |
| `default_limits()` | the safe limits |
| `PainOptions` | the reader switches: `skip_control_sum_check`, `check_iban`, `epc_charset` |
| `PainWriteOptions` | the writer switches: `epc_charset`, `indent` |
| `write_ach(header, batches, entries, addenda, lim, out)` | writes the NACHA file with all totals computed |
| `parse_ach(input, opts, lim, header, batches, entries, addenda)` | reads a NACHA file and checks the control records |
| `AchFileHeader` | record 1: the routing number, the origin id, the creation time, the names |
| `AchBatch` | records 5 and 8: the service class, the company, the SEC code, the effective date, the entry range |
| `AchEntry` | record 6: the transaction code, the routing number, the account, the amount in cents, the trace number |
| `AchAddenda` | record 7, type 05: the payment related text |
| `AchOptions` | the reader switches: `skip_total_check`, `check_routing` |
| `new_ach_file_header()`, `new_ach_batch()`, `new_ach_entry()`, `new_ach_addenda()`, `new_ach_options()` | the zero values of the ACH structs |
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

The direct debit checks the sequence type against `FRST`, `RCUR`,
`OOFF` and `FNAL`. It checks the local instrument against `CORE`,
`COR1` and `B2B`. The writer needs a sequence type, the mandate id and
the mandate signature date. The reader accepts an absent sequence type,
because later schema versions place it elsewhere. The reader takes the
creditor scheme id from the block or from the transaction.

The writer needs the creation time and the execution date, because the
schema makes both mandatory. It writes the elements in schema order.
An amount below zero is a fault in the reader and in the writer.

The reader passes every IBAN to the check digits of
`goose-payment-identifier`. A failure is a fault. The option
`check_iban` turns the check off.

## The NACHA file

Every record holds exactly 94 columns and ends with a line feed. The
writer pads the file with records of nines to a multiple of ten. The
reader takes a line feed or a carriage return with a line feed. The
last record may have no record end.

The writer computes six values from the data. They are the entry count,
the entry hash, the debit total, the credit total and the batch count.
The sixth is the block count.

The caller cannot set these values. The reader compares each batch control and the file
control with the data. A mismatch is a fault with both values. The
option `skip_total_check` turns this off.

The routing numbers pass the check digit with the weights 3, 7 and 1.
The option `check_routing` turns the check off in the reader. The
writer always checks.

The trace number starts with the ODFI id of its batch. A batch of class 220 holds credits only. A batch of class 225
holds debits only. A prenote holds an amount of zero.

Each SEC code has its own rules. PPD, CCD and WEB hold one addendum
at most. CTX holds many addenda. TEL, ARC, BOC, POP and RCK hold debits
only and no addendum. A batch with the description `REVERSAL` holds the
opposite direction.

An ARC entry holds 25000.00 at most. An RCK entry holds 2500.00 at most.
The trace numbers of a batch ascend.

The SEC code is PPD, CCD, WEB, TEL, CTX, ARC, BOC, POP or RCK. The
transaction codes are the checking, savings, general ledger and loan
codes. The file holds two digits of the year, so the dates run from
2000 to 2099.

## Limits

- **The writers emit one form each: pain.001.001.03 and
  pain.008.001.02.** The readers take the later versions too. Python
  `sepaxml` writes the same forms.
- **The writer computes the control sum from the items.** The caller
  cannot set it. A caller who needs another total writes the file by
  hand.
- **`pacs.008` stays out.** A later release adds it.
- **The NACHA file takes nine SEC codes.** They are PPD, CCD, WEB,
  TEL, CTX, ARC, BOC, POP and RCK. It holds addenda of type 05 only. IAT batches, ADV
  records, returns and notices of change stay out. The reader refuses
  them.
- **A reversal is a batch with the description `REVERSAL`.** The
  package does not check the other reversal rules of NACHA.
- **The writer needs each batch to hold an entry.** The reader refuses
  an empty batch too.
- **The writer writes the amendment flag alone.** It writes no
  amendment details, no ultimate party and no pre-notification. The
  reader ignores them.
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
- **The code lists are checked.** Five values must match their lists.
  They are the sequence type, the instrument, the method, the charge
  bearer and the BIC shape. `sepaxml` passes any text.
- **The blocks must cover the items.** The writer refuses a range that
  skips an item. It refuses an overlap too. The header total then
  matches the blocks.
- **A 64-bit overflow is a fault.** The reader checks each digit step.
  The value `92233720368547758.08` is a fault, not a negative number.
- **The amounts are exact.** An amount is minor units of the
  currency. No call of the package puts a float into an amount.
- **Every size has a limit.** The limits cover the input, the payment
  blocks, the items and the texts. `default_limits()` holds safe
  values.
- **No entity expands.** The package `goose-xml` skips a doctype and
  never expands an entity.
- **No recursion, linear time.** A hostile file cannot overflow the
  stack or make the parser slow down.

NACHA protections beyond the reference library `moov-io/ach`:

- **A record that is not 94 columns is a fault.** The reader checks
  every record. It refuses a line end inside a record.
- **The whole record holds printable ASCII.** A control byte in any
  column, even a reserved one, is a fault.
- **A bad total is a fault, not a warning.** The reader checks the
  counts, the hash and the totals. The writer computes them.
- **Amounts are exact cents.** Every sum has an overflow check. A
  number that does not fit its field is a fault.
- **The writer never truncates.** A text longer than its field is a
  fault.
- **The writer and the reader agree.** A file that the writer
  accepts, the reader accepts.
- **The writer writes all or nothing.** A fault leaves the output
  buffer as it was. The addenda ranges of the entries must follow each
  other, so no addendum text is lost or written twice.

Risks that stay:

- **The names and the remittance texts are untrusted.** The package
  checks the character set. Escape them yourself for HTML, SQL, a
  path or a command.
- **The package never connects to a bank.** It checks the form of the
  file. It does not check the right of the sender.
- **The default input limit is 16 MiB.** Lower it when you read from
  a form upload.

## License

MIT. See the LICENSE file.
