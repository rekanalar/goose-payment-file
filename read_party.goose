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
    // two address lines. A third line is a fault.
    var line: i64 = 0;
    var c = doc.nodes[adr].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT {
            if n.local == "Dept" {
                let t, f = opt_text(doc, c, "Dept", MAX_70, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.department = t;
            } else if n.local == "SubDept" {
                let t, f = opt_text(doc, c, "SubDept", MAX_70, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.sub_department = t;
            } else if n.local == "StrtNm" {
                let t, f = opt_text(doc, c, "StrtNm", MAX_70, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.street_name = t;
            } else if n.local == "BldgNb" {
                let t, f = opt_text(doc, c, "BldgNb", MAX_16, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.building_number = t;
            } else if n.local == "PstCd" {
                let t, f = opt_text(doc, c, "PstCd", MAX_16, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.post_code = t;
            } else if n.local == "TwnNm" {
                let t, f = opt_text(doc, c, "TwnNm", MAX_35, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.town_name = t;
            } else if n.local == "CtrySubDvsn" {
                let t, f = opt_text(doc, c, "CtrySubDvsn", MAX_35, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                a.country_subdivision = t;
            } else if n.local == "Ctry" {
                let t, f = opt_text(doc, c, "Ctry", MAX_35, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
                if t.len > 0 && !country_ok(t) {
                    return a, fault(F_SYNTAX, 0, 0, "Ctry", "the country is not two capital letters");
                }
                a.country = t;
            } else if n.local == "AdrLine" {
                let t, f = opt_text(doc, c, "AdrLine", MAX_70, opts, lim, buf);
                if f.kind != F_NONE { return a, f; }
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
        let cd = child(doc, sch, "Cd");
        let prtry = child(doc, sch, "Prtry");
        if cd >= 0 && prtry >= 0 {
            return o, fault(F_SYNTAX, 0, 0, "SchmeNm", "the scheme holds a code and a proprietary text");
        }
        if cd >= 0 {
            let t, f1 = opt_text(doc, cd, "Cd", MAX_4, opts, lim, buf);
            if f1.kind != F_NONE { return o, f1; }
            o.scheme_code = t;
        } else if prtry >= 0 {
            let t, f2 = opt_text(doc, prtry, "Prtry", MAX_35, opts, lim, buf);
            if f2.kind != F_NONE { return o, f2; }
            o.scheme_proprietary = t;
        }
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
    // One pass over the children. The package holds one other
    // identifier. A second one is a fault.
    var count: i64 = 0;
    var c = doc.nodes[holder].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == xml::KIND_ELEMENT {
            if n.local == "BICOrBEI" {
                let bic, f0 = opt_text(doc, c, "BICOrBEI", 11, opts, lim, buf);
                if f0.kind != F_NONE { return p, f0; }
                if bic.len > 0 {
                    if p.kind == PARTY_PERSON {
                        return p, fault(F_SYNTAX, 0, 0, "PrvtId", "a private person holds no BIC");
                    }
                    if !bic_ok(bic) {
                        return p, fault(F_SYNTAX, 0, 0, "BICOrBEI", "the BIC is not 8 or 11 capital letters and digits");
                    }
                    p.bic = bic;
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
    if p.bic.len == 0 && other_empty(p.other) {
        return p, fault(F_SYNTAX, 0, 0, "Id", "the identification holds nothing");
    }
    return p, no_fault();
}

// read_detail reads what a party holds beyond its name.
fn read_detail(doc: xml::Doc&, id: i32, opts: PainOptions&, lim: Limits&,
                buf: u8[>..]&) -> PartyDetail, Fault {
    var d = new_party_detail();
    let a, f0 = read_address(doc, id, opts, lim, buf);
    if f0.kind != F_NONE { return d, f0; }
    d.address = a;
    let p, f1 = read_party_id(doc, id, opts, lim, buf);
    if f1.kind != F_NONE { return d, f1; }
    d.id = p;
    return d, no_fault();
}

// read_party_full reads a party: the name, the address and the
// identification. The name limit is the limit of the caller. A party
// that holds an address or an identification and no name is a fault.
// The flag says that the schema needs the name.
fn read_party_full(doc: xml::Doc&, id: i32, name_max: i64, required: bool,
                    opts: PainOptions&, lim: Limits&, buf: u8[>..]&,
                    tag: const u8[:]) -> const u8[:], PartyDetail, Fault {
    var d = new_party_detail();
    let nm, f0 = opt_text(doc, child(doc, id, "Nm"), "Nm", name_max, opts, lim, buf);
    if f0.kind != F_NONE { return "", d, f0; }
    let det, f1 = read_detail(doc, id, opts, lim, buf);
    if f1.kind != F_NONE { return "", d, f1; }
    if nm.len == 0 {
        if !detail_empty(det) {
            return "", d, fault(F_SYNTAX, 0, 0, tag, "the party holds an address or an identification and no name");
        }
        if required {
            return "", d, fault(F_SYNTAX, 0, 0, tag, "the party holds no name");
        }
    }
    return nm, det, no_fault();
}

// read_cdtr_ref reads the structured creditor reference: the type
// with its code and issuer, then the reference. The schema makes the
// three parts optional.
fn read_cdtr_ref(doc: xml::Doc&, refi: i32, opts: PainOptions&, lim: Limits&,
                  buf: u8[>..]&, t: CreditTransfer&) -> Fault {
    let tp = child(doc, refi, "Tp");
    if tp >= 0 {
        let cdp = child(doc, tp, "CdOrPrtry");
        if cdp >= 0 {
            let cd = child(doc, cdp, "Cd");
            if cd >= 0 {
                t.structured_type = text_of(doc, cd, buf);
                let tf = check_text(t.structured_type, MAX_4, "Cd", opts.epc_charset, lim);
                if tf.kind != F_NONE { return tf; }
                if !doc_type_ok(t.structured_type) {
                    return fault(F_SYNTAX, 0, 0, "Cd", "the document type is not RADM, RPIN, FXDR, DISP, PUOR or SCOR");
                }
            }
        }
        let issr = child(doc, tp, "Issr");
        if issr >= 0 {
            t.structured_issuer = text_of(doc, issr, buf);
            let isf = check_text(t.structured_issuer, MAX_35, "Issr", opts.epc_charset, lim);
            if isf.kind != F_NONE { return isf; }
        }
    }
    let rf = child(doc, refi, "Ref");
    if rf >= 0 {
        t.structured_ref = text_of(doc, rf, buf);
        let rff = check_text(t.structured_ref, MAX_35, "Ref", opts.epc_charset, lim);
        if rff.kind != F_NONE { return rff; }
    }
    return no_fault();
}
