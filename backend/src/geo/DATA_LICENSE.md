Kazakhstan address data and updated settlement names are derived from OpenStreetMap,
© OpenStreetMap contributors, licensed under Open Data Commons Open Database License
(ODbL) 1.0: https://opendatacommons.org/licenses/odbl/1-0/ .

The country extract and boundary were obtained from Geofabrik:
https://download.geofabrik.de/asia/kazakhstan.html . Snapshot date, source checksum,
record count and generated archive SHA-256 are in data/kz-metadata.json.
The indexed database is available in machine-readable form through
/api/geo/data/kz/download; license and source metadata through /api/geo/data/kz/info.
Maps display attribution linking to https://www.openstreetmap.org/copyright .

Unmatched GeoNames settlements and region metadata remain under CC BY 4.0:
https://www.geonames.org/about.html . See CITY_CATALOG_LICENSE.md.

Rebuild the public dataset with an isolated Python environment containing
osmium==4.1.1 and shapely==2.1.1. Download kazakhstan-latest.osm.pbf, its publisher's
.md5 file, kazakhstan.poly, GeoNames cities500.zip, admin1CodesASCII.txt, KZ.zip, RU.zip and
country archives from export/dump/alternatenames/{KZ,RU}.zip (save as
KZ-alternatenames.zip and RU-alternatenames.zip) into a
working directory outside the checkout; preserve TLS and verify the source checksum.
Save the exact OSM national boundary (relation 214665) as kz-boundary.json from
https://nominatim.openstreetmap.org/lookup?osm_ids=R214665&format=json&polygon_geojson=1 .
The Geofabrik extract polygon is buffered and must not define country membership.
The raw extraction produces kz-osm-places.json, kz-osm-addresses.json and
kz-osm-roads.json with scripts/extract_kz_geodata.py.
Run scripts/build_kz_address_index.py --raw-dir <directory> to rebuild assets,
then scripts/build_settlement_catalog.py --raw-dir <directory>. Russian names
come from the ru language records, including preferred modern names, rather than
selecting an arbitrary Cyrillic translation. Source archive hashes are recorded
in data/settlement-sources.json. Then run backend build, tests and the country audit. Do not treat a sampled
address audit as proof that every real-world address exists in the source.
SQLite is read-only at runtime; no user records or wallets are imported or modified.

City records are imported transactionally with import-city-catalog.js after schema
migration. The import retains existing IDs, coordinates, activation states and
tariffs. Cities with the same name remain separate by country and coordinates.
No city search requests are sent to map providers; street and house providers are
independent. Newly added settlements need their own city tariff in the admin UI.
