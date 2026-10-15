import GitGardenerCore
import SwiftUI

extension Color {
    static let garden = Color(red: 0.46, green: 0.66, blue: 0.30)
}

extension SafetyVerdict {
    var label: String {
        switch self {
        case .safe: "Sûre"
        case .review: "À vérifier"
        case .risky: "Risquée"
        case .blocked: "Bloquée"
        }
    }

    var pluralLabel: String {
        switch self {
        case .safe: "Sûres"
        case .review: "À vérifier"
        case .risky: "Risquées"
        case .blocked: "Bloquées"
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .review: "exclamationmark.triangle.fill"
        case .risky: "xmark.octagon.fill"
        case .blocked: "lock.fill"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .risky: .red
        case .blocked: .secondary
        }
    }
}

/// A small tinted capsule, the building block of every badge.
struct Tag: View {
    let text: String
    var symbol: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct VerdictTag: View {
    let verdict: SafetyVerdict

    var body: some View {
        Tag(text: verdict.label, symbol: verdict.symbol, color: verdict.color)
    }
}

/// Safe, Review and Risky counts; zeros are left out.
struct VerdictCounts: View {
    let reports: [BranchAnalyzer.Report]

    var body: some View {
        HStack(spacing: 4) {
            ForEach([SafetyVerdict.safe, .review, .risky], id: \.self) { verdict in
                let count = reports.filter { $0.verdict == verdict }.count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .foregroundStyle(verdict.color)
                        .background(verdict.color.opacity(0.16), in: Capsule())
                        .help("\(count) \(verdict.label.lowercased())")
                }
            }
        }
    }
}

struct LocationLabel: View {
    let location: Repo.BranchLocation

    var body: some View {
        switch location {
        case .localOnly:
            Label("Local uniquement", systemImage: "laptopcomputer")
        case .gone:
            Label("Origin supprimée", systemImage: "icloud.slash").foregroundStyle(.orange)
        case .tracked(0, 0):
            Label("À jour", systemImage: "checkmark.icloud").foregroundStyle(.secondary)
        case let .tracked(ahead, behind):
            Text("\(Image(systemName: "arrow.up"))\(ahead)  \(Image(systemName: "arrow.down"))\(behind)").monospacedDigit()
        }
    }
}

extension URL {
    /// `~/code/app` rather than `/Users/me/code/app`.
    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
