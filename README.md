# New dwellings since Census 2022, by Local Electoral Area

An interactive map showing how many new dwellings have been completed in each
of Ireland's 166 Local Electoral Areas (LEAs) since Census 2022, as a share of
the LEA's housing stock at the census.

**Map:** https://barraroantree.github.io/ireland-housing-completions-map/

**Data behind it:** [`data/ndq09_completions_lea.csv`](data/ndq09_completions_lea.csv)

The map updates itself. On the 1st of each month a GitHub Action checks for a
new CSO release and, if there is one, rebuilds and republishes the map. See
[`last_checked.txt`](last_checked.txt) for the date of the last check and the
latest quarter included.

## What the map shows

- **Completions:** new dwelling completions from CSO table
  [NDQ09](https://data.cso.ie/table/NDQ09), summed from 2022Q2 to the latest
  quarter published. The map and its popups state the exact period, for
  example "Census 2022 (April 2022) to end-September 2026".
- **Denominator:** total housing stock (permanent dwellings, occupied and
  vacant) in each LEA on Census night, 3 April 2022, from Census 2022 Small
  Area Population Statistics (SAPS), table T6_8. The LEA totals sum to
  2,112,121 dwellings, the published national figure.

## Caveats

- **Start date:** NDQ09 is quarterly, so the count starts on 1 April 2022 and
  includes completions from the two days before Census night. That's roughly
  250 dwellings nationally, which is negligible.
- **Completions are not net change in the stock.** NDQ09 counts new dwellings
  connected to the ESB network. It doesn't subtract demolitions or count
  vacant dwellings brought back into use, so it measures new supply, not the
  change in the total stock.
- **Matching LEAs:** NDQ09's LEA identifiers match the census boundary
  identifiers for 139 LEAs. The other 27 are matched on LEA name and county.
  The script checks that all 166 match one-to-one and that the LEA totals
  add up to the State total.

## Repository

| Path | What it is |
|---|---|
| `index.html` | The map (self-contained leaflet page; OpenStreetMap basemap) |
| `data/ndq09_completions_lea.csv` | Completions, Census 2022 stock and % by LEA |
| `R/build_map.R` | Fetches NDQ09 and builds the map and CSV |
| `publish.sh` | Rebuilds, then commits and pushes if anything changed |
| `.github/workflows/update.yml` | Runs `publish.sh` monthly; can also be run by hand from the Actions tab (tick *force* to rebuild regardless) |
| `inputs/census2022_lea_housing_stock.csv` | Census 2022 SAPS T6_8_T by LEA GUID |
| `inputs/lea_2022_simplified.geojson` | CSO LEA 2022 boundaries, repaired and simplified to 60 m |

To rebuild locally: `Rscript R/build_map.R --force`. This needs R with the
`csodata`, `dplyr`, `sf`, `leaflet` and `htmlwidgets` packages, plus pandoc.

## Sources and licences

- **CSO:** NDQ09 *New Dwelling Completions*; Census 2022 SAPS by LEA; Local
  Electoral Areas 2022 boundaries (ungeneralised). All under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- **Basemap:** © [OpenStreetMap](https://www.openstreetmap.org/copyright)
  contributors.

Maintained by Barra Roantree, Trinity College Dublin.
