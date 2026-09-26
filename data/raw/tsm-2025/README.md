# TSM 2025 — Tenant Satisfaction Measures (full data)

Raw, unmodified extract as downloaded from the Regulator of Social Housing (RSH).
Files are kept under their original published names so they stay traceable to the
source release. **Do not edit these in place** — write derived outputs to
`data/processed/` instead.

| File | Contents | Rows | Cols |
| --- | --- | ---: | ---: |
| File 01 — LCRA_perception | Low Cost Rental Accommodation: tenant perception measures | 353 | 135 |
| File 02 — LCHO_perception | Low Cost Home Ownership: tenant perception measures | 59 | 111 |
| File 03 — COMB_perception | Combined LCRA + LCHO perception measures | 2 | 135 |
| File 04 — Management_info | Landlord-reported management information measures | 359 | 104 |
| File 05 — Perception_not_inc | Landlords whose perception data RSH excluded, with reasons | 2 | 3 |
| File 06 — Man_not_inc | Landlords whose management info RSH excluded, with reasons | 1 | 3 |
| File 0A — Data_dictionary | Field-level definitions for all measures | 521 | 8 |
| File 0B — Table_coverage | Which tables each landlord appears in | 363 | 9 |

## Joining

`Landlord_code` / `ProviderNumber` is the key across files (e.g. `L4240` for private
registered providers, ONS-style codes such as `00GL` for local authorities).
Start from **File 0B — Table_coverage** to see which landlords are present in
which table before joining.

## Gotchas

- Files are UTF-8 **with BOM**. Read with `encoding="utf-8-sig"` in pandas, or the
  first column name will come through as `ï»¿ProviderName`.
- Suppression markers appear in place of numbers: `[X]` (not applicable / not
  collected) and `[S]` (suppressed). These make otherwise-numeric columns parse as
  strings — coerce explicitly rather than relying on dtype inference.
- Some fields are quoted and contain commas and newlines (notably the RSH notes in
  Files 05 and 06), so use a real CSV parser, not a line split.
- Files 05 and 06 are exclusion lists, not measures. Landlords listed there are
  absent or partial in the main tables; treat them as known gaps, not missing data.

## Source

Regulator of Social Housing, Tenant Satisfaction Measures 2024–25 publication.
Confirm the current licensing terms on the RSH publication page before
redistributing or publishing derived figures.
