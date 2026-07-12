import Foundation

// SMC temperature-key table for Apple Silicon (D-018 follow-up, 2026-07-12).
// Key→role data derived from exelban/stats `Modules/Sensors/values.swift`
// (MIT License, © Serhiy Mytrovtsiy — https://github.com/exelban/stats), the
// community's de-facto canonical map of Apple's undocumented per-generation
// SMC temperature keys. Stats' per-core names collapse here to QSP's
// glanceable detail-card roles (CPU / GPU / SSD / Battery) — the reader
// averages per role, so individual core labels are never displayed.
//
// The table is the UNION of the M1–M5 generation keys, with no chip
// detection: absent keys simply don't respond on a given die (binning — the
// same reason FNum drives fan count), so TemperatureReader probes once at
// init and keeps what answers. The union is safe because every
// cross-generation key collision inside it stays within one role (e.g. Tp09
// is E-core 1 on M1 but P-core 3 on M2/M4 — both "CPU").
//
// arm64-only: Intel SMCs reuse some of these keys with different meanings
// (Tp0P is an M1 CPU core but "Powerboard" on Intel), so the table compiles
// away outside Apple Silicon and Intel keeps the IOHID/Pressure fallback.
//
// Probe-verified on this M4 Pro (2026-07-12, read-only spike): 17/25 M4-gen
// keys answered as type `flt` — 2 E-cores, 7 P-cores, 8 GPU sensors — plus
// TH0x/TB1T/TB2T; values corroborate the IOHID readings (battery 32.5 °C SMC
// vs 31 °C gas gauge).

enum SMCTemperatureTable {
#if arch(arm64)
    /// (SMC key, detail-card role). Probed once at reader init; only keys
    /// answering with a plausible °C are kept for per-tick reads.
    static let sensors: [(key: String, role: String)] = [
        // ── CPU cores ── M1 (Tp0…), M2 (+Tp1…/Tp0f/Tp0j), M3 (Te…/Tf0–4…),
        //                 M4 (+Te09/Te0H/Tp0V/Tp0Y/Tp0e), M5 (Tp00…Tp0y)
        ("Tp01", "CPU"), ("Tp05", "CPU"), ("Tp09", "CPU"), ("Tp0D", "CPU"),
        ("Tp0H", "CPU"), ("Tp0L", "CPU"), ("Tp0P", "CPU"), ("Tp0T", "CPU"),
        ("Tp0X", "CPU"), ("Tp0b", "CPU"),
        ("Tp1h", "CPU"), ("Tp1t", "CPU"), ("Tp1p", "CPU"), ("Tp1l", "CPU"),
        ("Tp0f", "CPU"), ("Tp0j", "CPU"),
        ("Te05", "CPU"), ("Te0L", "CPU"), ("Te0P", "CPU"), ("Te0S", "CPU"),
        ("Te09", "CPU"), ("Te0H", "CPU"),
        ("Tf04", "CPU"), ("Tf09", "CPU"), ("Tf0A", "CPU"), ("Tf0B", "CPU"),
        ("Tf0D", "CPU"), ("Tf0E", "CPU"), ("Tf44", "CPU"), ("Tf49", "CPU"),
        ("Tf4A", "CPU"), ("Tf4B", "CPU"), ("Tf4D", "CPU"), ("Tf4E", "CPU"),
        ("Tp0V", "CPU"), ("Tp0Y", "CPU"), ("Tp0e", "CPU"),
        ("Tp00", "CPU"), ("Tp04", "CPU"), ("Tp08", "CPU"), ("Tp0C", "CPU"),
        ("Tp0G", "CPU"), ("Tp0K", "CPU"), ("Tp0O", "CPU"), ("Tp0R", "CPU"),
        ("Tp0U", "CPU"), ("Tp0a", "CPU"), ("Tp0d", "CPU"), ("Tp0g", "CPU"),
        ("Tp0m", "CPU"), ("Tp0p", "CPU"), ("Tp0u", "CPU"), ("Tp0y", "CPU"),

        // ── GPU ── M1 (Tg05/Tg0D/Tg0L/Tg0T), M2 (Tg0f/Tg0j),
        //           M3 (Tf1…/Tf2…), M4 (Tg0G…Tg0k, Tg1U/Tg1k = Pro/Max),
        //           M5 (Tg0U…Tg1g)
        ("Tg05", "GPU"), ("Tg0D", "GPU"), ("Tg0L", "GPU"), ("Tg0T", "GPU"),
        ("Tg0f", "GPU"), ("Tg0j", "GPU"),
        ("Tf14", "GPU"), ("Tf18", "GPU"), ("Tf19", "GPU"), ("Tf1A", "GPU"),
        ("Tf24", "GPU"), ("Tf28", "GPU"), ("Tf29", "GPU"), ("Tf2A", "GPU"),
        ("Tg0G", "GPU"), ("Tg0H", "GPU"), ("Tg1U", "GPU"), ("Tg1k", "GPU"),
        ("Tg0K", "GPU"), ("Tg0d", "GPU"), ("Tg0e", "GPU"), ("Tg0k", "GPU"),
        ("Tg0U", "GPU"), ("Tg0X", "GPU"), ("Tg0g", "GPU"), ("Tg1Y", "GPU"),
        ("Tg1c", "GPU"), ("Tg1g", "GPU"),

        // ── Storage / battery ── Apple Silicon general keys
        ("TH0x", "SSD"),
        ("TB1T", "Battery"), ("TB2T", "Battery"),
    ]
#else
    static let sensors: [(key: String, role: String)] = []
#endif
}
