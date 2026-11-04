#!/usr/bin/env python3
"""Build Prism's offline country index from the unmodified DB-IP Country Lite CSV.

Usage: python3 scripts/build-country-database.py 2026-11 [--source /path/to.csv.gz]
The script only uses the Python standard library. No download occurs at app runtime.
"""

import argparse
import csv
import gzip
import hashlib
import io
import ipaddress
import json
from pathlib import Path
import re
import struct
import urllib.request


# ISO 3166-1 alpha-2; DB-IP's ZZ (unknown) and unassigned XK do not become countries.
ISO_COUNTRIES = set("""
AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ
BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM
DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS
GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN
KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ
MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM
PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV
SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI
VN VU WF WS YE YT ZA ZM ZW
""".split())


def build(source: bytes, month: str) -> tuple[bytes, dict]:
    codes = sorted(ISO_COUNTRIES)
    indices = {code: index + 1 for index, code in enumerate(codes)}
    transitions = {4: [], 6: []}
    previous_end = {4: -1, 6: -1}

    def append(version: int, address: int, country: int) -> None:
        rows = transitions[version]
        if not rows or rows[-1][1] != country:
            rows.append((address, country))

    with gzip.GzipFile(fileobj=io.BytesIO(source)) as compressed:
        for row in csv.reader(io.TextIOWrapper(compressed, encoding="utf-8", newline="")):
            if len(row) != 3:
                raise ValueError("Unexpected DB-IP CSV columns")
            start, end = ipaddress.ip_address(row[0]), ipaddress.ip_address(row[1])
            if start.version != end.version or int(start) > int(end):
                raise ValueError("Invalid address range")
            version = start.version
            if int(start) <= previous_end[version]:
                raise ValueError("DB-IP ranges must be sorted and non-overlapping")
            if int(start) > previous_end[version] + 1:
                append(version, previous_end[version] + 1, 0)
            append(version, int(start), indices.get(row[2], 0))
            previous_end[version] = int(end)

    for version, width in ((4, 4), (6, 16)):
        if previous_end[version] < 0:
            raise ValueError("Both IPv4 and IPv6 data are required")
        if previous_end[version] < (1 << (width * 8)) - 1:
            append(version, previous_end[version] + 1, 0)

    # Each record starts a country range ending just before the next record.
    # Explicit country 0 records preserve unknown ranges and gaps.
    body = bytearray("".join(codes).encode("ascii"))
    for version, width in ((4, 4), (6, 16)):
        for address, country in transitions[version]:
            body.extend(address.to_bytes(width, "big"))
            body.append(country)
    prefix = struct.pack(
        ">8sII8sHH", b"PRCN0001", len(transitions[4]), len(transitions[6]),
        (month + "\0").encode("ascii"), len(codes), 0,
    )
    digest = hashlib.sha256(prefix + body).digest()
    data = prefix + digest + body
    return data, {
        "format": "PRCN0001", "dataset_month": month,
        "ipv4_boundaries": len(transitions[4]), "ipv6_boundaries": len(transitions[6]),
        "countries": len(codes), "bytes": len(data),
        "source_sha256": hashlib.sha256(source).hexdigest(),
        "index_sha256": hashlib.sha256(data).hexdigest(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("month", help="DB-IP release month, YYYY-MM")
    parser.add_argument("--source", type=Path, help="Use an already downloaded official CSV.gz")
    args = parser.parse_args()
    if not re.fullmatch(r"20\d{2}-(0[1-9]|1[0-2])", args.month):
        parser.error("month must be YYYY-MM")
    source_url = f"https://download.db-ip.com/free/dbip-country-lite-{args.month}.csv.gz"
    if args.source:
        source = args.source.read_bytes()
    else:
        with urllib.request.urlopen(source_url, timeout=90) as response:
            source = response.read()
    data, metadata = build(source, args.month)
    metadata.update({
        "source_url": source_url,
        "source_page": "https://db-ip.com/db/download/ip-to-country-lite",
        "attribution": "IP Geolocation by DB-IP (https://db-ip.com)",
        "license": "CC BY 4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "modifications": "Country-only boundary index; adjacent equal countries merged; non-ISO country codes treated as unknown.",
    })
    destination = Path(__file__).resolve().parent.parent / "Prism/Resources/GeoIP"
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "country-dbip.prismdb").write_bytes(data)
    (destination / "country-dbip.source.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
