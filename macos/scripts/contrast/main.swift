// Entry point for scripts/check-contrast.sh: prints every failing pair and exits 1, or exits 0.
import Foundation
let failures = Contrast.violations()
if failures.isEmpty {
    print("Contrast check passed: \(Contrast.allSelections().count) style, mode and accent combinations.")
} else {
    for f in failures { print("error: Contrast: \(f)") }
    print("Contrast check failed: \(failures.count) pairs below WCAG minimums. Fix the values in Top3/Shared/StyleTokens.swift.")
    exit(1)
}
