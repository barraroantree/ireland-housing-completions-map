# ------------------------------------------------------------------------
# New dwellings completed since Census 2022 as a share of the Census 2022
# housing stock, by Local Electoral Area (LEA): interactive leaflet map.
#
# Run from the repo root:  Rscript R/build_map.R [--force]
# Normally run via publish.sh (monthly, by GitHub Actions).
#
# Data:  CSO NDQ09 (New Dwelling Completions by LEA, quarterly), fetched live.
#        inputs/census2022_lea_housing_stock.csv: Census 2022 SAPS by LEA,
#          table T6_8, T6_8_T = total housing stock (sums to 2,112,121, equal
#          to PxStat F2095 "Total housing stock").
#        inputs/lea_2022_simplified.geojson: CSO LEA boundaries 2022 (166
#          LEAs), ungeneralised layer simplified to 60m.
# Completions are summed from 2022Q2 (Census night was 3 April 2022, so the
#   quarter includes 1-3 April) to the latest quarter published.
# Join: NDQ09's LEA GUID matches the boundary LEA_GUID for most LEAs; the
#   rest are matched on LEA name and county.
#
# Outputs: index.html, data/ndq09_completions_lea.csv, last_checked.txt.
# The map and CSV are only rewritten when NDQ09 has new or revised figures
# (or with --force); last_checked.txt is updated on every run.
# ------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(csodata)
  library(dplyr)
  library(sf)
  library(leaflet)
  library(htmlwidgets)
})

force    <- "--force" %in% commandArgs(trailingOnly = TRUE)
start_q  <- "2022Q2"
csv_file <- "data/ndq09_completions_lea.csv"

# "2026Q3" -> "end-September 2026"
quarter_end <- function(q) {
  month <- c("March", "June", "September", "December")[as.integer(substr(q, 6, 6))]
  paste0("end-", month, " ", substr(q, 1, 4))
}

# ---- 1. Completions since Census 2022 ------------------------------------
meta    <- cso_get_meta("NDQ09")
vintage <- format(as.Date(substr(meta$Date_last_modified, 1, 10)), "%d %B %Y")

nd <- cso_get_data("NDQ09", pivot_format = "long", include_ids = TRUE) |>
  mutate(across(where(is.factor), as.character))
last_q <- max(nd$Quarter)
state_total <- nd |>
  filter(Local.Electoral.Area == "State", Quarter >= start_q) |>
  summarise(v = sum(value)) |> pull(v)

comp <- nd |>
  filter(Local.Electoral.Area.id != "-", Quarter >= start_q) |>
  group_by(nd_id = Local.Electoral.Area.id, nd_name = Local.Electoral.Area) |>
  summarise(completions = sum(value, na.rm = TRUE),
            quarters = n_distinct(Quarter), .groups = "drop")
stopifnot(nrow(comp) == 166, all(comp$quarters == max(comp$quarters)))
stopifnot(abs(sum(comp$completions) - state_total) <= 5)

# ---- 2. LEA boundaries and match ----------------------------------------
lea <- st_read("inputs/lea_2022_simplified.geojson", quiet = TRUE)
stopifnot(nrow(lea) == 166, all(st_geometry_type(lea) == "MULTIPOLYGON"))

# Key = LEA name; where a name occurs in two counties (Athlone: Westmeath
# and Roscommon) the county is added. Boundary COUNTY uses traditional
# counties (e.g. DUBLIN), so it is only used for those duplicated names.
norm <- function(x) gsub("[^A-Z]", "", toupper(iconv(x, to = "ASCII//TRANSLIT")))
lea <- lea |>
  mutate(name_key = norm(CSO_LEA),
         key = if_else(name_key %in% name_key[duplicated(name_key)],
                       paste0(name_key, "_", norm(COUNTY)), name_key))
dup_names <- unique(lea$name_key[duplicated(lea$name_key)])
comp <- comp |>
  mutate(lea_part = sub(",[^,]*$", "", nd_name),
         county_part = sub("^.*,\\s*", "", nd_name),
         key = if_else(norm(lea_part) %in% dup_names,
                       paste0(norm(lea_part), "_", norm(county_part)), norm(lea_part)))
stopifnot(!anyDuplicated(lea$key))

by_guid <- comp |> filter(nd_id %in% lea$LEA_GUID) |> mutate(LEA_GUID = nd_id)
by_name <- comp |> filter(!nd_id %in% lea$LEA_GUID) |>
  inner_join(st_drop_geometry(lea) |> select(LEA_GUID, key), by = "key")
matched <- bind_rows(by_guid, by_name)
stopifnot(nrow(matched) == 166, !anyDuplicated(matched$LEA_GUID))

# ---- 3. Combine with Census 2022 stock -----------------------------------
stock <- read.csv("inputs/census2022_lea_housing_stock.csv")
stopifnot(nrow(stock) == 166, sum(stock$stock) == 2112121)

d <- lea |>
  select(LEA_GUID, CSO_LEA, COUNTY) |>
  left_join(matched |> select(LEA_GUID, nd_name, completions), by = "LEA_GUID") |>
  left_join(stock, by = "LEA_GUID") |>
  mutate(pct = 100 * completions / stock)
stopifnot(!anyNA(d$pct))

nat    <- 100 * sum(d$completions) / sum(d$stock)
period <- paste0("Census 2022 (April 2022) to ", quarter_end(last_q))

out <- d |> st_drop_geometry() |>
  transmute(lea = nd_name, lea_guid = LEA_GUID, county = COUNTY,
            first_quarter = start_q, last_quarter = last_q,
            completions_since_census = completions,
            census_2022_stock = stock, pct_of_stock = round(pct, 2)) |>
  arrange(lea_guid)

writeLines(c(format(Sys.Date()), paste("latest NDQ09 quarter:", last_q),
             paste("NDQ09 last modified:", vintage)), "last_checked.txt")

if (!force && file.exists(csv_file)) {
  old <- read.csv(csv_file) |> arrange(lea_guid)
  if (identical(old$last_quarter, out$last_quarter) &&
      identical(as.numeric(old$completions_since_census),
                as.numeric(out$completions_since_census))) {
    message("No new NDQ09 data (latest quarter ", last_q, "): map unchanged.")
    quit(save = "no", status = 0)
  }
}

message(sprintf("State: %s completions, %s = %.1f%% of 2022 stock",
                format(sum(d$completions), big.mark = ","), period, nat))

# ---- 4. Leaflet map --------------------------------------------------------
bins <- c(0, 2, 3, 4, 5, 6, 8, 10, 15, 20, ceiling(max(d$pct)))
pal  <- colorBin(RColorBrewer::brewer.pal(9, "YlGnBu"), domain = d$pct, bins = bins)
fmt  <- function(x) formatC(x, format = "d", big.mark = ",")
popup <- sprintf(
  "<b>%s</b><br>New dwellings, April 2022 to %s: <b>%s</b><br>Census 2022 housing stock: %s<br>Completions as %% of stock: <b>%.1f%%</b>",
  d$nd_name, quarter_end(last_q), fmt(d$completions), fmt(d$stock), d$pct)
label <- sprintf("%s: %.1f%%", d$nd_name, d$pct)

title_html <- sprintf(paste0(
  "<div style='font: 600 15px/1.3 sans-serif'>New dwellings since Census 2022</div>",
  "<div style='font: 12px/1.4 sans-serif; color:#444; max-width: 290px'>",
  "Dwellings completed from %s, as %% of each LEA's Census 2022 housing stock. ",
  "State: %s dwellings, %.1f%%.</div>"), period, fmt(sum(d$completions)), nat)

# OSM standard tiles: no key needed; OSM requires the attribution below.
osm_url  <- "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
osm_attr <- paste0("&copy; <a href='https://www.openstreetmap.org/copyright'>",
                   "OpenStreetMap</a> contributors")

m <- leaflet(d, options = leafletOptions(minZoom = 6)) |>
  addTiles(urlTemplate = osm_url, attribution = osm_attr,
           options = tileOptions(maxZoom = 19)) |>
  addPolygons(fillColor = ~pal(pct), fillOpacity = 0.8, color = "white",
              weight = 0.8, popup = popup, label = label,
              highlightOptions = highlightOptions(weight = 2.5, color = "#333",
                                                  bringToFront = TRUE)) |>
  addLegend("bottomright", pal = pal, values = ~pct, opacity = 0.9,
            title = "% of 2022 stock", labFormat = labelFormat(suffix = "%")) |>
  addControl(title_html, position = "topright") |>
  addControl(sprintf(paste0(
    "<span style='font: 11px sans-serif; color:#555'>",
    "Source: CSO NDQ09, quarters %s&ndash;%s (data as of %s); Census 2022 SAPS ",
    "T6_8 by LEA; CSO LEA boundaries 2022. ",
    "<a href='https://github.com/barraroantree/ireland-housing-completions-map'>",
    "Code and data</a></span>"), start_q, last_q, vintage),
    position = "bottomleft")

saveWidget(m, "index.html", selfcontained = TRUE,
           title = "New dwellings since Census 2022 by LEA")
unlink("index_files", recursive = TRUE)
# CSV last, so a failed map build leaves it stale and the next run retries
write.csv(out, csv_file, row.names = FALSE)
message("Wrote index.html and ", csv_file)
