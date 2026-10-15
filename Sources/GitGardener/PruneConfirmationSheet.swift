import GitGardenerCore
import SwiftUI

struct PruneConfirmationSheet: View {
    let targets: [Pruner.Target]
    let onFinish: ([Pruner.Outcome]) -> Void

    private struct Settings: Hashable {
        var alsoOnOrigin = false
        var keepsBranch: Set<Pruner.Target.ID> = []
    }

    private let pruner = Pruner(analyzer: BranchAnalyzer(), log: PruneLog())

    @Environment(\.dismiss) private var dismiss
    @State private var settings = Settings()
    @State private var plan: Pruner.Plan?
    @State private var errorMessage: String?
    @State private var typedConfirmation = ""
    @State private var isRunning = false

    private var canConfirm: Bool {
        guard let plan, !plan.items.isEmpty, !isRunning else { return false }
        return !plan.requiresTypedConfirmation || typedConfirmation == "supprimer"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supprimer \(plan?.items.count ?? targets.count) éléments").font(.title2.bold())
            if let plan {
                list(plan)
            } else if errorMessage == nil {
                ProgressView("Analyse en cours…")
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Toggle("Supprimer aussi sur origin", isOn: $settings.alsoOnOrigin)
            if plan?.requiresTypedConfirmation == true {
                TextField("Tapez « supprimer » pour confirmer", text: $typedConfirmation)
            }
            HStack {
                Button("Annuler") { dismiss() }
                Spacer()
                Button("Supprimer", role: .destructive, action: confirm).disabled(!canConfirm)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .task(id: settings) { await load() }
    }

    private func list(_ plan: Pruner.Plan) -> some View {
        List {
            if !plan.changedVerdicts.isEmpty {
                Section("Verdicts modifiés") {
                    ForEach(plan.changedVerdicts, id: \.target.id) {
                        Text("\($0.target.name) : \($0.target.verdict.label) → \($0.verdict.label)")
                    }
                }
            }
            section("Risquées", plan.items.filter { $0.verdict == .risky }, color: .red)
            section("Sélection", plan.items.filter { $0.verdict != .risky }, color: .primary)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Pruner.Plan.Item], color: Color) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items, id: \.target.id) { item in
                    HStack {
                        Text(item.target.name).foregroundStyle(color)
                        if item.target.isOriginOnly { Text("(origin uniquement)") }
                        Spacer()
                        if item.target.worktreePath != nil {
                            Toggle("Garder la branche", isOn: keepsBranch(item.target)).toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }
    }

    private func keepsBranch(_ target: Pruner.Target) -> Binding<Bool> {
        Binding(
            get: { settings.keepsBranch.contains(target.id) },
            set: { keeps in
                if keeps { settings.keepsBranch.insert(target.id) } else { settings.keepsBranch.remove(target.id) }
            }
        )
    }

    private func load() async {
        let current = targets.map { target -> Pruner.Target in
            var target = target
            target.keepsBranch = settings.keepsBranch.contains(target.id)
            return target
        }
        do {
            plan = try await pruner.prepare(current, alsoOnOrigin: settings.alsoOnOrigin)
            errorMessage = nil
        } catch {
            plan = nil
            errorMessage = "\(error)"
        }
    }

    private func confirm() {
        guard let plan else { return }
        isRunning = true
        Task {
            let outcomes = await pruner.execute(plan)
            onFinish(outcomes)
            dismiss()
        }
    }
}

extension Pruner.Target {
    var name: String { branch ?? worktreePath?.lastPathComponent ?? "" }
}
