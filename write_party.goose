// The writer of a party of the pain.001 credit transfer.
//
// A party is a name, a postal address and an identification, in this
// order. Every text passes its length limit and the EPC switch. An
// empty text writes no element. The writer never truncates a text.
namespace payment_file;

import std;
import fault;
import model_party;
import charset;
import enums;
import write_pain;

// opt_leaf writes a leaf when the text is not empty.
fn opt_leaf(out: u8[>..]&, tag: const u8[:], text: const u8[:], max: i64, depth: i64,
            opts: PainWriteOptions, lim: Limits&) -> Fault {
    if text.len == 0 { return no_fault(); }
    return text_leaf(out, tag, text, max, true, depth, opts, lim);
}

// write_address writes the postal address. An empty address writes
// nothing. The second line needs the first.
fn write_address(out: u8[>..]&, a: PostalAddress&, depth: i64, opts: PainWriteOptions,
                 lim: Limits&) -> Fault {
    if address_empty(a) { return no_fault(); }
    if a.country.len > 0 && !country_ok(a.country) {
        return fault(F_SYNTAX, 0, 0, "Ctry", "the country is not two capital letters");
    }
    if a.line_2.len > 0 && a.line_1.len == 0 {
        return fault(F_SYNTAX, 0, 0, "AdrLine", "the second address line needs the first");
    }
    open(out, "PstlAdr", depth, opts);
    var f = opt_leaf(out, "Dept", a.department, MAX_70, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, "SubDept", a.sub_department, MAX_70, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, "StrtNm", a.street_name, MAX_70, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, "BldgNb", a.building_number, MAX_16, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, "PstCd", a.post_code, MAX_16, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, "TwnNm", a.town_name, MAX_35, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, "CtrySubDvsn", a.country_subdivision, MAX_35, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    if a.country.len > 0 { leaf(out, "Ctry", a.country, depth + 1, opts); }
    f = opt_leaf(out, "AdrLine", a.line_1, MAX_70, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, "AdrLine", a.line_2, MAX_70, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    close(out, "PstlAdr", depth, opts);
    return no_fault();
}

// write_other writes the Othr element of an identification.
fn write_other(out: u8[>..]&, o: OtherId&, depth: i64, opts: PainWriteOptions,
               lim: Limits&) -> Fault {
    if o.id.len == 0 {
        return fault(F_SYNTAX, 0, 0, "Othr", "the other identifier holds no id");
    }
    if o.scheme_code.len > 0 && o.scheme_proprietary.len > 0 {
        return fault(F_SYNTAX, 0, 0, "SchmeNm", "the scheme holds a code and a proprietary text");
    }
    open(out, "Othr", depth, opts);
    var f = text_leaf(out, "Id", o.id, MAX_35, true, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    if o.scheme_code.len > 0 || o.scheme_proprietary.len > 0 {
        f = write_code_or_prtry(out, "SchmeNm", o.scheme_code, o.scheme_proprietary, depth + 1, opts, lim);
        if f.kind != F_NONE { return f; }
    }
    f = opt_leaf(out, "Issr", o.issuer, MAX_35, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    close(out, "Othr", depth, opts);
    return no_fault();
}

// write_birth writes the date and the place of birth. The date, the
// city and the country are required.
fn write_birth(out: u8[>..]&, b: BirthData&, depth: i64, opts: PainWriteOptions,
               lim: Limits&) -> Fault {
    if b.city.len == 0 {
        return fault(F_SYNTAX, 0, 0, "CityOfBirth", "the birth data holds no city");
    }
    if b.country.len == 0 || !country_ok(b.country) {
        return fault(F_SYNTAX, 0, 0, "CtryOfBirth", "the birth country is not two capital letters");
    }
    open(out, "DtAndPlcOfBirth", depth, opts);
    var f = date_leaf(out, "BirthDt", b.year, b.month, b.day, depth + 1, opts);
    if f.kind != F_NONE { return f; }
    f = opt_leaf(out, "PrvcOfBirth", b.province, MAX_35, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    f = text_leaf(out, "CityOfBirth", b.city, MAX_35, true, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    leaf(out, "CtryOfBirth", b.country, depth + 1, opts);
    close(out, "DtAndPlcOfBirth", depth, opts);
    return no_fault();
}

// write_party_id writes the Id element of a party. A party with no
// identification writes nothing.
fn write_party_id(out: u8[>..]&, p: PartyId&, depth: i64, opts: PainWriteOptions,
                  lim: Limits&) -> Fault {
    if p.lei.len > 0 {
        return fault(F_SYNTAX, 0, 0, "Id", "the written forms hold no element for an LEI");
    }
    if p.kind == PARTY_NONE {
        if p.bic.len > 0 || !other_empty(p.other) || !birth_empty(p.birth) {
            return fault(F_SYNTAX, 0, 0, "Id", "the identification holds a value and no kind");
        }
        return no_fault();
    }
    if p.kind != PARTY_ORG && p.kind != PARTY_PERSON {
        return fault(F_SYNTAX, 0, 0, "Id", "the identification kind is not none, organisation or person");
    }
    if p.kind == PARTY_PERSON && p.bic.len > 0 {
        return fault(F_SYNTAX, 0, 0, "PrvtId", "a private person holds no BIC");
    }
    if p.kind == PARTY_ORG && !birth_empty(p.birth) {
        return fault(F_SYNTAX, 0, 0, "OrgId", "an organisation holds no birth data");
    }
    if p.bic.len == 0 && other_empty(p.other) && birth_empty(p.birth) {
        return fault(F_SYNTAX, 0, 0, "Id", "the identification holds nothing");
    }
    if p.bic.len > 0 && !bic_ok(p.bic) {
        return fault(F_SYNTAX, 0, 0, "BICOrBEI", "the BIC is not 8 or 11 capital letters and digits");
    }
    var kind_tag: const u8[:] = "OrgId";
    if p.kind == PARTY_PERSON { kind_tag = "PrvtId"; }
    open(out, "Id", depth, opts);
    open(out, kind_tag, depth + 1, opts);
    if p.bic.len > 0 {
        let f = text_leaf(out, "BICOrBEI", p.bic, 11, true, depth + 2, opts, lim);
        if f.kind != F_NONE { return f; }
    }
    if !birth_empty(p.birth) {
        let fb = write_birth(out, p.birth, depth + 2, opts, lim);
        if fb.kind != F_NONE { return fb; }
    }
    if !other_empty(p.other) {
        let f2 = write_other(out, p.other, depth + 2, opts, lim);
        if f2.kind != F_NONE { return f2; }
    }
    close(out, kind_tag, depth + 1, opts);
    close(out, "Id", depth, opts);
    return no_fault();
}

// party_full writes a party: the name, the address and the identification.
// The name limit is the limit of the caller. A party with no name holds
// no address and no identification. It is a fault when the schema
// requires the party.
fn party_full(out: u8[>..]&, tag: const u8[:], name: const u8[:], name_max: i64,
              d: PartyDetail&, required: bool, depth: i64, opts: PainWriteOptions,
              lim: Limits&) -> Fault {
    if name.len == 0 {
        if !detail_empty(d) {
            return fault(F_SYNTAX, 0, 0, tag, "the party holds an address or an identification and no name");
        }
        if !required { return no_fault(); }
    }
    open(out, tag, depth, opts);
    var f = text_leaf(out, "Nm", name, name_max, true, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    f = write_address(out, d.address, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    f = write_party_id(out, d.id, depth + 1, opts, lim);
    if f.kind != F_NONE { return f; }
    close(out, tag, depth, opts);
    return no_fault();
}
