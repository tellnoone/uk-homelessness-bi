| Check | Category | What is tested | Rows tested | Failed | Status | Action taken |
|---|---|---|---:|---:|---|---|
| CM01 | Comparability | Landlord uses a single non-emergency repair target (RP02 comparable) | 356 | 282 | WARN | RP02 is not ranked across landlords in the report; targets are shown next to it. |
| CP01 | Completeness | Every LCRA survey has a headline TP01 result | 353 | 0 | PASS | - |
| CP02 | Completeness | Every applicable result has a usable value | 10,016 | 11 | WARN | Kept in the fact table with their status; the value is left empty, so averages and counts skip them. Most are RSH exclusions ([E]) explained in RSH's comments. |
| CP03 | Completeness | [U] appears only where the measure does not apply to the landlord | 2,673 | 0 | PASS | - |
| CS01 | Consistency | Landlord name, type, size and region agree across tables | 363 | 0 | PASS | - |
| DU01 | Duplication | Each landlord appears once per published table | 1,136 | 0 | PASS | - |
| DU02 | Duplication | Fact grain (landlord x measure x tenure x period) is unique | 10,016 | 0 | PASS | - |
| RC01 | Reconciliation | Published % satisfied = (very + fairly satisfied) / all ratings | 4,789 | 0 | PASS | - |
| RC02 | Reconciliation | Published management measure = numerator / denominator | 5,216 | 0 | PASS | - |
| RC03 | Reconciliation | Responses by survey method add up to the survey total | 414 | 0 | PASS | - |
| RG01 | Range | Percentages are between 0 and 100 | 8,457 | 0 | PASS | - |
| RG02 | Range | Numerator never exceeds a positive denominator | 3,668 | 0 | PASS | - |
| RG03 | Range | Per-1,000 rates are not extreme outliers (over upper quartile + 3 IQR) | 1,548 | 27 | WARN | Kept: they reconcile to their own numerator and denominator (RC02), so they are what the landlord reported. Medians, not means, are used in the report so they cannot dominate. Flagged for review, since they may reflect different recording practice. |
| RG04 | Range | Each survey met its required minimum sample | 414 | 11 | WARN | Kept: RSH published them. Their results carry a wider margin of error than required; margin_of_error_pts is in fact_survey for the report to show. |
| RG05 | Range | No survey has more responses than tenants sampled | 414 | 0 | PASS | - |
| RI01 | Referential integrity | Every landlord in a measure table is in the coverage file | 773 | 0 | PASS | - |
| RI02 | Referential integrity | Coverage flags match the landlords actually in each table | 1,452 | 0 | PASS | - |
| RI03 | Referential integrity | Every excluded landlord is on RSH's exclusion list with a reason | 9 | 6 | WARN | Kept in dim_landlord with both exclusion flags set and no note; they hold no results, so no measure is affected. Reported here because a reader of the exclusion lists alone would miss them. |
| RI04 | Referential integrity | Every staged result is loaded into the fact table | 10,016 | 0 | PASS | - |
