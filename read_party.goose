// The reader of a party of the pain.001 credit transfer.
//
// A party holds a name, a postal address and an identification. The
// reader ignores an element that the model does not name. It refuses
// an element that the model names and cannot hold, so no value is
// lost in silence.
namespace payment_file;

import std;
import xml from "rekanalar/goose-xml@v2.0.0";
import fault;
import model_party;
import enums;
import charset;
import read_pain;

// read_address reads the postal address of a party. The texts point
// into the buffer of the caller.
fn read_address(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                buf: u8[>..]&) -> PostalAddress, Fault {
    var a = new_address();
    let adr = child(doc, id, "PstlAdr");
    if adr < 0 { return a, no_fault(); }
    // One pass over the children fills every field. The package keeps
    // two address lines. A third line is a fault. A second copy of a
    // field is a fault too, so no value is lost in silence. The bit
    // for each field marks the first copy.
    var line: i64 = 0;
    var seen: i64 = 0;
    var c = doc.nodes[adr].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT {
            if n.local == "Dept" {
                if seen & 1 != 0 { return a, fault(F_SYNTAX, 0, 0, "Dept", "the address holds two department elements"); }
                seen |= 1;
                let t, f = opt_text(doc, c, "Dept", MAX_70, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.department = t;
            } else if n.local == "SubDept" {
                if seen & 2 != 0 { return a, fault(F_SYNTAX, 0, 0, "SubDept", "the address holds two sub department elements"); }
                seen |= 2;
                let t, f = opt_text(doc, c, "SubDept", MAX_70, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.sub_department = t;
            } else if n.local == "StrtNm" {
                if seen & 4 != 0 { return a, fault(F_SYNTAX, 0, 0, "StrtNm", "the address holds two street names"); }
                seen |= 4;
                let t, f = opt_text(doc, c, "StrtNm", MAX_70, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.street_name = t;
            } else if n.local == "BldgNb" {
                if seen & 8 != 0 { return a, fault(F_SYNTAX, 0, 0, "BldgNb", "the address holds two building numbers"); }
                seen |= 8;
                let t, f = opt_text(doc, c, "BldgNb", MAX_16, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.building_number = t;
            } else if n.local == "PstCd" {
                if seen & 16 != 0 { return a, fault(F_SYNTAX, 0, 0, "PstCd", "the address holds two post codes"); }
                seen |= 16;
                let t, f = opt_text(doc, c, "PstCd", MAX_16, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.post_code = t;
            } else if n.local == "TwnNm" {
                if seen & 32 != 0 { return a, fault(F_SYNTAX, 0, 0, "TwnNm", "the address holds two town names"); }
                seen |= 32;
                let t, f = opt_text(doc, c, "TwnNm", MAX_35, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.town_name = t;
            } else if n.local == "CtrySubDvsn" {
                if seen & 64 != 0 { return a, fault(F_SYNTAX, 0, 0, "CtrySubDvsn", "the address holds two country subdivisions"); }
                seen |= 64;
                let t, f = opt_text(doc, c, "CtrySubDvsn", MAX_35, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.country_subdivision = t;
            } else if n.local == "Ctry" {
                if seen & 128 != 0 { return a, fault(F_SYNTAX, 0, 0, "Ctry", "the address holds two country elements"); }
                seen |= 128;
                let t, f = opt_text(doc, c, "Ctry", MAX_35, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                if t.len > 0 && !country_ok(t) {
                    return a, fault(F_SYNTAX, 0, 0, "Ctry", "the country is not two capital letters");
                }
                a.country = t;
            } else if n.local == "AdrLine" {
                let t, f = opt_text(doc, c, "AdrLine", MAX_70, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                if t.len == 0 {
                    return a, fault(F_SYNTAX, 0, 0, "AdrLine", "the address line holds no text");
                }
                line += 1;
                if line > 2 {
                    return a, fault(F_LIMIT, 0, 0, "AdrLine", "the address holds more than two lines");
                }
                if line == 1 { a.line_1 = t; } else { a.line_2 = t; }
            }
        }
        c = n.next_sibling;
    }
    return a, no_fault();
}

// read_other reads the Othr element of an identification.
fn read_other(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
               buf: u8[>..]&) -> OtherId, Fault {
    var o = new_other_id();
    let oid, f0 = opt_text(doc, child(doc, id, "Id"), "Id", MAX_35, opts, lim, buf);
    if f0.kind != F_NONE { return o, f0; }
    if oid.len == 0 {
        return o, fault(F_SYNTAX, 0, 0, "Othr", "the other identifier holds no id");
    }
    o.id = oid;
    let sch = child(doc, id, "SchmeNm");
    if sch >= 0 {
        let code, prop, f = read_code_or_prtry(doc, sch, "SchmeNm", opts, lim, buf);
        if f.kind != F_NONE { return o, f; }
        o.scheme_code = code;
        o.scheme_proprietary = prop;
    }
    let issr, f3 = opt_text(doc, child(doc, id, "Issr"), "Issr", MAX_35, opts, lim, buf);
    if f3.kind != F_NONE { return o, f3; }
    o.issuer = issr;
    return o, no_fault();
}

// read_party_id reads the Id element of a party. A party with no
// identification writes nothing. A party that names both an
// organisation and a private person is a fault.
fn read_party_id(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                  buf: u8[>..]&) -> PartyId, Fault {
    var p = new_party_id();
    let pid = child(doc, id, "Id");
    if pid < 0 { return p, no_fault(); }
    let org = child(doc, pid, "OrgId");
    let per = child(doc, pid, "PrvtId");
    if org >= 0 && per >= 0 {
        return p, fault(F_SYNTAX, 0, 0, "Id", "the party holds an organisation and a private identification");
    }
    if org < 0 && per < 0 {
        return p, fault(F_SYNTAX, 0, 0, "Id", "the identification names no organisation and no private person");
    }
    var holder = org;
    p.kind = PARTY_ORG;
    if per >= 0 { holder = per; p.kind = PARTY_PERSON; }
    // A second container of the same kind is a fault. The child
    // lookup takes the first, so the later one would be lost.
    var orgs: i64 = 0;
    var pers: i64 = 0;
    var k = doc.nodes[pid].first_child;
    while k >= 0 {
        let m = doc.nodes[k];
        if m.kind == xml::KIND_ELEMENT {
            if m.local == "OrgId" { orgs += 1; }
            else if m.local == "PrvtId" { pers += 1; }
        }
        k = m.next_sibling;
    }
    if orgs > 1 { return p, fault(F_SYNTAX, 0, 0, "OrgId", "the identification holds two organisation identifications"); }
    if pers > 1 { return p, fault(F_SYNTAX, 0, 0, "PrvtId", "the identification holds two private identifications"); }
    // One pass over the children. The package holds one other
    // identifier. A second one is a fault. The BIC has two names: the
    // older BICOrBEI and the later AnyBIC.
    var count: i64 = 0;
    var c = doc.nodes[holder].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT {
            if n.local == "BICOrBEI" || n.local == "AnyBIC" {
                let bic, f0 = opt_text(doc, c, "BIC", 11, opts, lim, buf);
                if f0.kind != F_NONE { return p, f0; }
                if bic.len > 0 {
                    if p.kind == PARTY_PERSON {
                        return p, fault(F_SYNTAX, 0, 0, "PrvtId", "a private person holds no BIC");
                    }
                    if p.bic.len > 0 {
                        return p, fault(F_SYNTAX, 0, 0, "BIC", "the identification holds two BICs");
                    }
                    if !bic_ok(bic) {
                        return p, fault(F_SYNTAX, 0, 0, "BIC", "the BIC is not 8 or 11 capital letters and digits");
                    }
                    p.bic = bic;
                }
            } else if n.local == "LEI" {
                let lei, f2 = opt_text(doc, c, "LEI", 20, opts, lim, buf);
                if f2.kind != F_NONE { return p, f2; }
                if lei.len > 0 {
                    if p.kind == PARTY_PERSON {
                        return p, fault(F_SYNTAX, 0, 0, "LEI", "a private person holds no LEI");
                    }
                    if !lei_ok(lei) {
                        return p, fault(F_SYNTAX, 0, 0, "LEI", "the LEI is not 20 letters and digits with two digits at the end");
                    }
                    if p.lei.len > 0 {
                        return p, fault(F_SYNTAX, 0, 0, "LEI", "the identification holds two LEIs");
                    }
                    p.lei = lei;
                }
            } else if n.local == "Othr" {
                count += 1;
                if count > 1 {
                    return p, fault(F_LIMIT, 0, 0, "Othr", "the identification holds more than one other identifier");
                }
                let oth, f1 = read_other(doc, c, opts, lim, buf);
                if f1.kind != F_NONE { return p, f1; }
                p.other = oth;
            }
        }
        c = n.next_sibling;
    }
    if p.bic.len == 0 && p.lei.len == 0 && other_empty(p.other) {
        return p, fault(F_SYNTAX, 0, 0, "Id", "the identification holds nothing");
    }
    return p, no_fault();
}

// read_detail reads what a party holds beyond its name. The caller
// gives the place to fill.
fn read_detail(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                buf: u8[>..]&, d: PartyDetail&) -> Fault {
    let a, f0 = read_address(doc, id, opts, lim, buf);
    if f0.kind != F_NONE { return f0; }
    d.address = a;
    let p, f1 = read_party_id(doc, id, opts, lim, buf);
    if f1.kind != F_NONE { return f1; }
    d.id = p;
    return no_fault();
}

// read_party_full reads a party: the name, the address and the
// identification. The name limit is the limit of the caller. A party
// that holds an address or an identification and no name is a fault.
// The flag says that the schema needs the name.
fn read_party_full(doc: xml::Doc&, id: i32, name_max: i64, required: bool,
                    opts: PainOptions&, lim: Limits&, buf: u8[>..]&,
                    d: PartyDetail&, tag: const u8[:]) -> const u8[:], Fault {
    // A second name is a fault. The child lookup takes the first, so
    // the later one would be lost.
    var names: i64 = 0;
    var k = doc.nodes[id].first_child;
    while k >= 0 {
        let m = doc.nodes[k];
        if m.kind == xml::KIND_ELEMENT && m.local == "Nm" { names += 1; }
        k = m.next_sibling;
    }
    if names > 1 { return "", fault(F_SYNTAX, 0, 0, tag, "the party holds two names"); }
    let nm, f0 = opt_text(doc, child(doc, id, "Nm"), "Nm", name_max, opts, lim, buf);
    if f0.kind != F_NONE { return "", f0; }
    let f1 = read_detail(doc, id, opts, lim, buf, d);
    if f1.kind != F_NONE { return "", f1; }
    if nm.len == 0 {
        if !detail_empty(d) {
            return "", fault(F_SYNTAX, 0, 0, tag, "the party holds an address or an identification and no name");
        }
        if required {
            return "", fault(F_SYNTAX, 0, 0, tag, "the party holds no name");
        }
    }
    return nm, no_fault();
}

// read_purpose reads the purpose code of an item. An empty code is a
// fault. The text points into the buffer of the caller.
fn read_purpose(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                buf: u8[>..]&) -> const u8[:], Fault {
    let purp = child(doc, id, "Purp");
    if purp < 0 { return "", no_fault(); }
    let cd = child(doc, purp, "Cd");
    if cd < 0 { return "", no_fault(); }
    let t = text_of(doc, cd, buf);
    if t.len == 0 { return "", fault(F_SYNTAX, 0, 0, "Purp", "the purpose code is empty"); }
    let f = check_text(t, MAX_4, "Purp", opts.epc_charset, lim);
    if f.kind != F_NONE { return "", f; }
    return t, no_fault();
}

// read_cdtr_ref reads the structured creditor reference: the type
// with its code and issuer, then the reference. The schema makes the
// three parts optional. The texts point into the buffer of the caller.
fn read_cdtr_ref(doc: xml::Doc&, refi: i32, opts: PainOptions&, lim: Limits&,
                  buf: u8[>..]&) -> CdtrRef, Fault {
    var r = new_cdtr_ref();
    let tp = child(doc, refi, "Tp");
    if tp >= 0 {
        let cdp = child(doc, tp, "CdOrPrtry");
        if cdp >= 0 {
            let code, prop, f0 = read_code_or_prtry(doc, cdp, "CdOrPrtry", opts, lim, buf);
            if f0.kind != F_NONE { return r, f0; }
            if code.len == 0 && prop.len == 0 {
                return r, fault(F_SYNTAX, 0, 0, "CdOrPrtry", "the reference type holds no code and no proprietary text");
            }
            r.code = code;
            r.proprietary_type = prop;
            if code.len > 0 && !doc_type_ok(code) {
                return r, fault(F_SYNTAX, 0, 0, "Cd", "the document type is not RADM, RPIN, FXDR, DISP, PUOR or SCOR");
            }
        }
        let issr = child(doc, tp, "Issr");
        if issr >= 0 {
            if cdp < 0 {
                return r, fault(F_SYNTAX, 0, 0, "Issr", "the reference type holds an issuer and no code");
            }
            r.issuer = text_of(doc, issr, buf);
            let isf = check_text(r.issuer, MAX_35, "Issr", opts.epc_charset, lim);
            if isf.kind != F_NONE { return r, isf; }
        }
    }
    let rf = child(doc, refi, "Ref");
    if rf >= 0 {
        r.ref = text_of(doc, rf, buf);
        let rff = check_text(r.ref, MAX_35, "Ref", opts.epc_charset, lim);
        if rff.kind != F_NONE { return r, rff; }
    }
    return r, no_fault();
}
