# Data provenance

## Source

**Regulator of Social Housing (RSH), Tenant Satisfaction Measures, full data
release for the 2024/25 reporting year** (the "TSM 2025" release). Published on
GOV.UK. Social housing landlords with 1,000 or more homes must submit the 22
TSMs to RSH each year; this release is RSH's compilation of those submissions
after its own review.

Downloaded from the RSH publication on GOV.UK and committed unmodified in
commit `66dd990` (26 September 2026). The files keep their published names.

## Files

| File | SHA-256 | Bytes |
|---|---|---:|
| `TSM_2025_Full_Data - File 01 - LCRA_perception.csv` | `432d71134c7cf04df6dccfb9bf0a8be59e4335d250d7deb82d15ff4b868721f7` | 292,705 |
| `TSM_2025_Full_Data - File 02 - LCHO_perception.csv` | `19f3dd38390993adcbb3750f744c7524d491309dbd4afabb6c79283a8ed2ec47` | 43,772 |
| `TSM_2025_Full_Data - File 03 - COMB_perception.csv` | `5b2f129cb16ca4171fbc06383a914e60d4769d6793942463f7dd2ac76241a53a` | 3,984 |
| `TSM_2025_Full_Data - File 04 - Management_info.csv` | `8599ad16ee8f8832a1d0dbb01336baa2fbc8bb6edd7c56512a1a0117dd38a0a1` | 262,260 |
| `TSM_2025_Full_Data - File 05 - Perception_not_inc.csv` | `f3454135526927c4085461cadfa6f946edef4beb8a7b6480e72d30ca916a7f74` | 529 |
| `TSM_2025_Full_Data - File 06 - Man_not_inc.csv` | `bf918497520111136e42bad6b7f2128d08c25ef122104efc6fab2c8143816b4c` | 318 |
| `TSM_2025_Full_Data - File 0A - Data_dictionary.csv` | `c72fc933918327c1828c2509c3fc83c37d6e3d83c7774903e4d95ff37f57a4ef` | 173,007 |
| `TSM_2025_Full_Data - File 0B - Table_coverage.csv` | `9d441ba6e95f566a62f60ffe44fe2ef84eb2090e38797cab353123b947bf1dab` | 21,645 |

`tests/test_raw_data.py` checks these hashes, so any change to a raw file
fails the build instead of silently changing the results.

## Licence

Statistics published on GOV.UK are released under the
[Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/)
unless the publication says otherwise. The RSH publication page was not
reachable from the environment this repository was built in, so **confirm the
licence on the publication page** before relying on this. Under OGL v3.0,
reuse requires the attribution:

> Contains public sector information licensed under the Open Government
> Licence v3.0. Source: Regulator of Social Housing, Tenant Satisfaction
> Measures 2024/25.

## Known issues in the published files

Found by the data quality layer (`sql/40_data_quality.sql`); full results in
`outputs/data_quality/`.

- Three landlords (Grainger Trust, ReSI Homes, The Abbeyfield Society) are
  marked as excluded in the coverage file but do not appear on either
  published exclusion list, so no reason is given (check RI03).
- Eleven surveys fell short of the minimum sample RSH set for them (check RG04).
- The status markers (`[X]`, `[S]`, `[Z]`, `[E]`, `[U]`) are not defined in the
  files. Their meanings, and the evidence for each, are in
  [`docs/modelling_decisions.md`](../docs/modelling_decisions.md).
- The unit of the repair target timescales (RP02) is not stated.
