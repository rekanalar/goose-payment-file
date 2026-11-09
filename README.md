# goose-payment-file

[![ci](https://github.com/rekanalar/goose-payment-file/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-payment-file/actions/workflows/ci.yml)

The files that start a payment, for the [Goose](https://github.com/aardappel/goose) language.
The package writes and reads four files.
Three files start at a customer: the SEPA `pain.001` credit transfer,
the `pain.008` direct debit and the NACHA ACH file.
The fourth file moves money between banks: the `pacs.008` customer
credit transfer.

The SEPA writers emit the pain.001.001.03 and pain.008.001.02 forms
that the bank portals take.
The `pacs.008` writer emits the pacs.008.001.08 form.
The readers take the later versions by element name.

Money is an integer count of minor units with the exponent of its
currency. The package uses no float.
Every parse is one linear pass with no recursion. Every size has a limit.

## Install

Add these lines to the root file of the program that uses it:

```goose
import payment_file from "rekanalar/goose-payment-file@v0.9.0";
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
| `write_ach_iat(header, batches, entries, addenda, lim, out)` | writes a NACHA file with one batch of the SEC code IAT |
| `parse_ach_iat(input, opts, lim, header, batches, entries, addenda, iat_batches, iat_entries, iat_addenda)` | reads a NACHA file that holds IAT batches |
| `write_ach_adv(header, batches, entries, lim, out)` | writes a NACHA file with one batch of the SEC code ADV |
| `parse_ach_adv(input, opts, lim, header, batches, entries)` | reads a NACHA file that holds ADV batches |
| `AchFileHeader` | record 1: the routing number, the origin id, the creation time, the names |
| `AchBatch` | records 5 and 8: the service class, the company, the SEC code, the effective date, the entry range |
| `AchEntry` | record 6: the transaction code, the routing number, the account, the amount in cents, the trace number |
| `AchAddenda` | record 7: the payment related text, the terminal record, the notice of change and the three forms of the return |
| `IatBatch` | record 5 of an IAT batch: the foreign exchange fields, the country, the currencies |
| `IatEntry` | record 6 of an IAT batch: the transaction code, the account, the screening indicators, the amount |
| `IatAddenda` | record 7 of an IAT batch: the records of type 02 and 10 to 18 |
| `AchOptions` | the reader switches: `skip_total_check`, `check_routing` |
| `new_ach_file_header()`, `new_ach_batch()`, `new_ach_entry()`, `new_ach_addenda()`, `new_ach_options()` | the zero values of the ACH structs |
| `new_iat_batch()`, `new_iat_entry()`, `new_iat_addenda(kind)` | the zero values of the IAT structs |
| `AdvEntry` | record 6 of an ADV batch: the transaction code, the routing number, the account, the amount, the advice routing number, the name, the Julian day |
| `new_adv_entry()` | the zero value of the ADV struct |
| `write_pacs008(header, txs, opts, lim, out)` | writes the customer credit transfer as pacs.008.001.08 XML |
| `parse_pacs008(input, lim, opts, header, txs, buf)` | reads a customer credit transfer of any `.001.NN` form |
| `Pacs008Header` | the group header, the settlement method, the settlement date, the two agents |
| `Pacs008Tx` | one credit transfer: the ids, the UETR, the amount, the parties, the agents, the remittance |
| `new_pacs008_header()`, `new_pacs008_tx()` | the zero values of the two structs |
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
at most. CTX, ATX and TRX hold many addenda. TEL, ARC, BOC, POP and
RCK hold debits only and no addendum. ACK, CIE, DNE and ENR hold one
addendum. SHR and MTE hold one terminal record.

TRC and XCK hold no addendum.

A batch with the description `REVERSAL` holds the opposite direction.

An ARC entry holds 25000.00 at most. An RCK entry and an XCK entry
hold 2500.00 at most. The trace numbers of a batch ascend.

The SEC codes are PPD, CCD, WEB, TEL, CTX, ARC, BOC, POP and RCK. The
package also takes ACK, ATX, CIE, COR, DNE, ENR, MTE, SHR, TRC, TRX, XCK
and IAT. The SEC code ADV has a layout of its own and a writer and a
reader of its own. The transaction codes are the checking, savings, general ledger
and loan codes. The file
holds two digits of the year. The dates run from 2000 to 2099.

## The newer SEC codes

Ten codes joined the package beside the ten it already held. They
share the entry layout of the first ten. Only their rules differ.

ACK holds zero dollar remittance credit prenotes. The transaction code
is 23 or 33. ATX takes the codes 23, 33 and 21. CIE takes credit codes
only.

COR takes the return codes 21 and 31 only. Every COR entry carries a
notice of change. DNE takes 23 or 33. ENR takes 23, 33, 21 and 31.
DNE and ENR carry exactly one addendum.

TRC, TRX and XCK take their direction from the service class. A batch
of credits only takes credit entries. Every other batch takes debit
entries.

ATX and TRX carry the count of their addenda records in the first
four columns of the individual name. The count must match the records
that follow the entry. SHR carries a card transaction type in its
discretionary data. It carries the card expiration date `MMYY` in the
first four columns of its identification number. The month is `01` to
`12`. The year is `18` to `50`.

An SHR entry and an MTE entry carry exactly one terminal record of
type 02. It holds the reference information, the terminal data and the
terminal state. The state is a postal abbreviation of a state or
territory of the United States. A terminal record rides on an SHR or MTE
entry only.

An MTE entry records a cash withdrawal at a teller machine. It holds an
amount above zero. It takes any transaction code that the service class
allows. Its identification number is not blank and not all zeros.

CIE and MTE swap the two text fields of the entry. The individual name
holds 15 characters in columns 40 to 54. The identification number holds
22 characters in columns 55 to 76. Every other SEC code holds the
identification number first, with 15 characters, and the name second,
with 22 characters.

A blank or all-zero name is a fault for twelve SEC codes. They are ARC,
BOC, CIE, DNE, ENR, MTE, POP, PPD, RCK, SHR, TEL and WEB.

## The ADV batch

The SEC code ADV holds an automated accounting advice. Its batch header
is the normal one, with the service class 280 and the originator
status 0. Its entry record has a layout of its own.

It holds the transaction code of the advice set. It holds the eight
digits of the routing number and its check digit. It holds the account
and the amount with twelve digits. It holds the advice routing number,
the file identification and the operator data.

It holds the name of 22 characters and the discretionary data. It
holds the addenda indicator, the operator routing number, the Julian day
and the sequence number. It holds no trace number.

The transaction codes of the advice set run from 81 to 88. The odd
codes move money into the account. The even codes move money out of
it.

The batch control record of an ADV batch holds twenty digits of debit
total and twenty digits of credit total. The file control record holds
the same wide totals.

Every other SEC code uses twelve digits. A file of one kind never
reads as a file of the other kind.

The writer `write_ach_adv` holds ADV batches only. The reader
`parse_ach_adv` reads ADV files only. The normal writer refuses an ADV
batch. The normal reader refuses one too. The file header and the batch
header keep the normal layout in both.

## The IAT batch

The SEC code IAT holds an international payment. Its batch header holds
the foreign exchange fields, the destination country, the originator
identification and the two currency codes. Its entry holds an account
number of up to 35 characters and the two screening indicators. The
writer computes the trace number and the count of the addenda records.

The entry of an IAT batch carries seven mandatory addenda records. They
are the records of types 10 to 16. They stand in that order. One record
of type 02 may stand before them. Two records of type 17 and one record
of type 18 may follow them. A missing record and a wrong order are
faults.

The addenda of type 10 holds the name, the transaction type code, the
foreign amount and the foreign trace number. The records of types 11 to
16 hold the addresses and the date of birth. They also hold the
identification numbers and the receiver relationship. The records of
types 17 and 18 hold the payment information and the foreign exchange
descriptor.

The record of type 98 is a notice of change. It holds the change code
and the corrected data. The change codes are `C01` to `C09`, `C13`,
`C14` and `C61` to `C69`.

The record of type 99 is a return. It holds the return code, the trace
number of the original entry and the information text. The return codes
are `R01` to `R47`, `R50` to `R53`, `R61`, `R62`, `R67` to `R77`,
`R80` to `R85` and `R90`. A return may hold the date of death of the
receiver.

The return has two more forms. The dishonored form holds the code
`R61`, `R62` or `R67` to `R70`. It holds the trace numbers, the
settlement dates and the reason code of the dishonor.

The contested form holds the code `R71` to `R77`. It holds those fields
and the date of the returned entry. The plain form takes none of these
codes. The reader picks the form from the code, as the reference
library does.

A notice of change, a return or a terminal record rides on a normal
entry. They stand alone. The package accepts them on any SEC code.

The writer of the IAT batch writes one batch kind per file. The writer
of the normal batches writes the other batches. The reader takes a file
of both kinds. The reader of the normal batches refuses a file with an
IAT batch.

## The pacs.008 message

The `pacs.008` message moves a customer credit transfer from one bank
to the next bank. The message holds one group header and a flat list of
transactions. It holds no payment block.

The group header holds the message id, the creation time and the batch
booking flag. It holds the count of the transactions, the control sum
and the total of the settlement amounts. It holds the settlement date
and the settlement method. The writer computes the count and the
control sum from the transactions. The caller cannot set them.

The settlement method is one of `INDA`, `INGA`, `COVE` and `CLRG`. Any
other value is a fault in the reader and in the writer.

A transaction holds the payment id, the settlement amount, the
settlement date and the charge bearer. It holds the debtor, the debtor
account and the debtor agent. It holds the creditor agent, the
creditor, the creditor account and the remittance. The payment id holds
the instruction id, the end-to-end id, the transaction id and the
UETR.

The UETR is a version 4 UUID in lowercase hexadecimal with hyphens. The
writer and the reader refuse any other shape, because a bank rejects a
UETR that is no UUID.

The writer emits the `pacs.008.001.08` form. The reader takes every
`.001.NN` form by element name. The names of the versions `.001.06`,
`.001.08` and `.001.09` are verified against Go `moov-io/iso20022` and
the ISO schemas.

The reader compares the count of the group header with the
transactions. It compares the control sum with the sum of the amounts.
It compares the total of the group with the same sum. The compare uses
the value, so `103.0000` equals `103.00`. The option
`skip_control_sum_check` turns the sum compares off.

The total of the group names the currency of the transactions. A total
in another currency is a fault. A message with two currencies has no
sum, so the reader checks the count only.

## Limits

- **The writers emit one form each: pain.001.001.03,
  pain.008.001.02 and pacs.008.001.08.** The readers take the later
  versions too. Python `sepaxml` writes the same SEPA forms.
- **The writer computes the control sum from the items.** The caller
  cannot set it. A caller who needs another total writes the file by
  hand.
- **The `pacs.008` reader takes three verified versions.** They are
  `.001.06`, `.001.08` and `.001.09`. The other versions use the same
  names. No schema validator ran, because none is installed.
- **The `pacs.008` model holds no settlement account.** It holds no
  ultimate party, no intermediary agent and no charges information. The
  writer emits none of them. The reader skips them.
- **The `pacs.008` writer emits no structured remittance.** It writes
  the first remittance text only. The reader reads the first text only.
- **The `pacs.008` reader refuses a two-currency message with a sum.**
  A sum over two currencies means nothing. The writer writes no sum for
  such a message.
- **The `pacs.008` reader refuses a group header with no count.** The
  count is mandatory in the schema.
- **The ADV entry takes no addenda record.** The reference library
  takes an addenda 99 record, which returns an advice entry. This
  release refuses it. The addenda indicator of an ADV entry is 0.
- **The ADV writer writes one batch kind per file.** The ADV writer
  holds ADV batches only. The normal writer holds the other batches.
  The normal reader refuses an advice batch. The advice reader refuses
  a normal batch.
- **The advice routing numbers hold digits now.** The old form let an
  advice routing number hold fewer than nine digits. It is a fault
  now. The old form let a total of twenty digits wrap around. It is a
  fault now. Re-write such a file with this package.
- **The CIE layout changed.** The old form held the identification
  number first, in columns 40 to 54. The new form holds the name first,
  with 15 characters. A file in the old form
  reads without a fault when both fields fit. The values land in the
  swapped fields. Re-write such a file with this package.
- **The terminal record is now mandatory for SHR.** The old form
  allowed an SHR entry with no terminal record. Such an entry is now a
  fault in the writer and in the reader.
- **The name rule is new.** A blank or all-zero individual name was
  legal before. It is now a fault for twelve SEC codes.
- **The IAT writer writes one batch kind per file.** The IAT writer
  holds IAT batches only. The normal writer holds the other batches.
  The normal reader refuses an IAT batch. The IAT reader takes a file
  of both kinds.
- **A code sets the return form.** An old file can
  hold such a code in the plain layout. The reader reads it as the
  other form. Re-write that file with this package.
- **The SHR and MTE entries take no addendum of type 05.** They take
  the terminal record only. The card reference number holds 11 columns
  beside the expiration date.
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
  The wide totals of an advice file hold twenty digits. A total that
  does not fit an i64 is a fault too. The reader checks every digit
  step of those totals.
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
- **The code lists of the IAT batch are checked.** The reference
  library takes any text.
- **The newer SEC codes check their codes.** Each SEC code takes the
  transaction codes of its rule and no others. The contested and the
  dishonored returns take their own lists.
- **The card fields of SHR are checked.** The transaction type takes
  the eight codes of the list. The expiration date takes the month
  `01` to `12` and the year `18` to `50`. The terminal state takes the
  postal abbreviations of the states and territories.
- **The count of the addenda of ATX and TRX must match.** The count
  stands in the file. The writer and the reader compare it with the
  records. A hostile count cannot hide or invent records.
- **The amount cap of XCK holds.** An XCK entry holds 2500.00 at
  most, as the rule of the code demands.
- **The terminal record binds to its entry.** The reader refuses a
  terminal record with another trace number.
- **MTE and SHR need a terminal record.** The writer and the reader
  refuse an entry with none or with two.
- **The name and the ID are checked.** A blank or all-zero
  value is a fault when the code needs one. A zero MTE amount is also
  a fault.
- **The two text widths are exact.** The writer refuses a CIE or MTE
  name above 15 characters. It refuses an identification number above
  22.
- **The advice control record agrees with its header.** The reader
  checks the service class against the header. It checks the ODFI id
  against the header. It checks the batch number against the header.
- **An advice batch holds an entry.** The reader refuses a batch
  without one. The writer refuses it too.
- **The advice fields are checked.** An advice entry holds no blank
  account. It holds no blank file identification. It holds no blank
  name. The reader holds the same rules as the writer.
- **The service class 280 goes with the SEC code ADV.** One without
  the other is a fault.
- **The two advice routing numbers hold digits.** The advice routing
  number holds nine digits. The operator routing number holds eight
  digits. The reference library takes any text in these two fields.
  It fills a short advice routing number with zeros. This package
  refuses a short one.
- **Every numeric field checks its digits.** A number that does not
  fit an i64 is a fault. The reader and the writer of every message
  share one guard for it. The twenty digit totals of an advice file
  need it too.
- **The plain return refuses the codes of the two forms.** A plain
  record with such a code is a fault. The reader would read the file
  as the other form, so the writer refuses it first.

| List | The values |
|---|---|
| The foreign exchange indicator | `FV`, `VF` or `FF` |
| The currency codes | three capital letters |
| The country codes | two capital letters |
| The branch country codes | two or three capital letters or digits |
| The transaction type codes | the 22 codes of the list |
| The change codes | the 20 codes of the list |
| The return codes | the 71 codes of the list |
| The dishonored return codes | `R61`, `R62`, `R67` to `R70` |
| The contested return codes | `R71` to `R77` |
| The card transaction types | `01`, `02`, `03`, `11`, `12`, `13`, `21`, `99` |
| The terminal states | the 57 postal abbreviations |
- **The reader checks the records of an IAT entry.** A missing
  mandatory record and a wrong order are faults. The reference library
  reads the records in any order.
- **The date of birth is a date.** A malformed date is a fault in the
  writer and in the reader. The reference library takes any text.
- **The writer writes all or nothing.** A fault leaves the output
  buffer as it was. The addenda ranges of the entries must follow each
  other, so no addendum text is lost or written twice.

`pacs.008` protections beyond the reference library `moov-io/iso20022`:

- **The UETR has the shape of a version 4 UUID.** The reference library
  takes any text. A bank rejects a UETR that is no UUID.
- **The settlement method is checked against its list.** The four
  codes are `INDA`, `INGA`, `COVE` and `CLRG`. The reference library
  takes any text.
- **The country of a party is two capital letters.** The writer and the
  reader refuse any other form.
- **The count of the group header must stand.** A message with no count
  is a fault. A count that differs from the transactions is a fault.
- **The total of the group names the currency of the transactions.** A
  total in another currency is a fault. The reference library stores the
  amount as a float and never compares it.
- **A group header with no sum is a fault.** The reader compares both
  sums with the transactions.
- **The amounts are exact.** No call of the package puts a float into
  an amount. The reference library stores the control sum as a float64.
- **The writer writes all or nothing.** A fault leaves the output
  buffer as it was.

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
