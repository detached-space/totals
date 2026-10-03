# Ethiopian cities offline place gazetteer

`ethiopia_city_places.json` is the Spending Map's bundled, on-device place
index. Its detail is deliberately capped at:

- the 11 official subcities inside Addis Ababa; and
- the city name in every other supported Ethiopian city.

It contains no neighbourhood, woreda, landmark, business, restaurant, user,
or transaction records. A coordinate outside an Addis subcity polygon can
only match one of the city anchors; the app does not guess a lower-level name.

The 23 city anchors cover Addis Ababa, Adama, Bahir Dar, Bishoftu, Dire Dawa,
Hawassa, Gondar, Mekelle, Jimma, Dessie, Harar, Jigjiga, Arba Minch,
Shashamane, Debre Birhan, Kombolcha, Nekemte, Asella, Axum, Lalibela, Semera,
Gambela, and Assosa.

## Sources

- City anchors come from the Overture Maps `2026-07-22.0` release. The
  Divisions theme is ODbL and requires attribution to OpenStreetMap
  contributors and Overture Maps Foundation. Overture currently has no
  Shashamane locality in Divisions, so that one approximate anchor uses an
  Overture Places record in central Shashamane under its recorded source
  terms. See https://docs.overturemaps.org/attribution/.
- Addis Ababa polygons come from the public `Subcity_Boundary` WFS exposed by
  Addis Ababa Cadaster. Its WFS capabilities state `fees: NONE` and
  `access constraints: NONE`:
  https://geos.addiscadaster.gov.et/geoserver/ncrprs_cadaster/ows?service=WFS&version=2.0.0&request=GetCapabilities

Source IDs, attribution, terms, and data timestamps are retained in the JSON
asset. The app never queries Overture or Addis Ababa Cadaster at runtime.

## Refreshing the asset

From `app/`, run:

```sh
node scripts/generate_offline_place_gazetteer.mjs
```

The generator downloads the current official Addis subcity GeoJSON, validates
that all 11 expected subcities are present exactly once, and rewrites the
asset. Pass `--source path/to/Subcity_Boundary.geojson` to use a previously
downloaded response. Update the generator's Overture release and city records
when refreshing the Overture subset.
