// The model of a party of the pain.001 credit transfer.
//
// A party holds a name, a postal address and an identification. The
// texts point at the input of the reader or at string literals of the
// caller. An empty text means the file holds no such element. The zero
// value of every struct here means the party holds nothing beyond the
// name, so a model that never sets these fields writes the same bytes
// as before.
namespace payment_file;

import std;

// The length limits of the texts. The reader and the writer both use
// them. The schema allows 140 for a name. The EPC rulebook allows
// 70. The writer keeps 70. The reader takes 140.
const MAX_140: i64 = 140;
const MAX_70: i64 = 70;
const MAX_35: i64 = 35;
const MAX_16: i64 = 16;
const MAX_4: i64 = 4;

// The kinds of a party identification. The zero is no identification.
const PARTY_NONE: i32 = 0;
const PARTY_ORG: i32 = 1;
const PARTY_PERSON: i32 = 2;

// PostalAddress holds the fields of a postal address. The country holds
// two capital letters. The package keeps two address lines, as the EPC
// rulebook does.
struct PostalAddress {
    department: const u8[:],
    sub_department: const u8[:],
    street_name: const u8[:],
    building_number: const u8[:],
    post_code: const u8[:],
    town_name: const u8[:],
    country_subdivision: const u8[:],
    country: const u8[:],
    line_1: const u8[:],
    line_2: const u8[:],
}

// OtherId holds one other identifier: the id, the scheme as a code or
// as a proprietary text, and the issuer. The scheme code and the
// proprietary text exclude each other.
struct OtherId {
    id: const u8[:],
    scheme_code: const u8[:],
    scheme_proprietary: const u8[:],
    issuer: const u8[:],
}

// PartyId holds the identification of a party. The kind tells whether
// it is an organisation or a private person. Only an organisation
// holds a BIC or BEI.
struct PartyId {
    kind: i32,
    bic: const u8[:],
    other: OtherId,
}

// PartyDetail holds what a party carries beyond its name.
struct PartyDetail {
    address: PostalAddress,
    id: PartyId,
}

// address_empty tells whether an address holds no field.
fn address_empty(a: PostalAddress) -> bool {
    return a.department.len == 0 && a.sub_department.len == 0 && a.street_name.len == 0
        && a.building_number.len == 0 && a.post_code.len == 0 && a.town_name.len == 0
        && a.country_subdivision.len == 0 && a.country.len == 0
        && a.line_1.len == 0 && a.line_2.len == 0;
}

// other_empty tells whether an other identifier holds no field.
fn other_empty(o: OtherId) -> bool {
    return o.id.len == 0 && o.scheme_code.len == 0 && o.scheme_proprietary.len == 0
        && o.issuer.len == 0;
}

// detail_empty tells whether a party detail holds nothing. The reader
// and the writer share this rule.
fn detail_empty(d: PartyDetail) -> bool {
    return address_empty(d.address) && d.id.kind == PARTY_NONE && d.id.bic.len == 0
        && other_empty(d.id.other);
}

// new_address gives an address with no field.
fn new_address() -> PostalAddress {
    return PostalAddress {
        department: "", sub_department: "", street_name: "", building_number: "",
        post_code: "", town_name: "", country_subdivision: "", country: "",
        line_1: "", line_2: "",
    };
}

// new_other_id gives an other identifier with no field.
fn new_other_id() -> OtherId {
    return OtherId { id: "", scheme_code: "", scheme_proprietary: "", issuer: "" };
}

// new_party_id gives an identification that holds nothing.
fn new_party_id() -> PartyId {
    return PartyId { kind: PARTY_NONE, bic: "", other: new_other_id() };
}

// new_party_detail gives a party detail that holds nothing.
fn new_party_detail() -> PartyDetail {
    return PartyDetail { address: new_address(), id: new_party_id() };
}
