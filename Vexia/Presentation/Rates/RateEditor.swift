import SwiftUI

/// Rate editor sheet (design "Editar tasa"): big input, one-tap references, deviation vs. day rate,
/// live preview, and two clearly named outcomes. Replaces the old alert.
@Observable
final class RateEditorViewModel {
    struct Reference: Identifiable, Equatable { var id: String { name }; let name: String; let meta: String; let value: Double }

    let code: String
    let previewAmount: Double?          // amount in `code` for the "Este gasto" preview
    var text: String
    private(set) var references: [Reference] = []
    private(set) var dayRate: Double?
    private(set) var isRefreshing = false
    private let catalog: CatalogRepository

    init(code: String, current: Double?, previewAmount: Double?, catalog: CatalogRepository) {
        self.code = code.uppercased(); self.previewAmount = previewAmount; self.catalog = catalog
        text = current.map { Fmt.editable($0, digits: 0...4) } ?? ""
    }

    var value: Double? { RateParsing.parse(text).flatMap { $0 > 0 ? $0 : nil } }
    var deviation: Double? { guard let v = value, let d = dayRate, d > 0 else { return nil }; return (v - d) / d * 100 }
    var deviationText: String {
        guard let dev = deviation else { return " " }
        if abs(dev) < 0.05 { return "Igual a la tasa del día" }
        return (dev > 0 ? "+" : "−") + Fmt.grouped(abs(dev), decimals: 1) + "% frente a la tasa del día"
    }
    var previewText: String? {
        guard let a = previewAmount, let v = value else { return nil }
        return "\(Fmt.money(a, currency: code)) = \(Fmt.money(a / v, currency: "USD"))"
    }

    func load() async {
        async let ext = try? catalog.externalUSDRate(code: code)
        async let stored = try? catalog.storedUSDRate(code: code)
        let e = await ext ?? nil, s = await stored ?? nil
        dayRate = e ?? s
        var refs: [Reference] = []
        if let e { refs.append(.init(name: "Del día (fuente externa)", meta: "Consultada ahora", value: e)) }
        if let s, s != e { refs.append(.init(name: "Guardada por ti", meta: "Usada en tus movimientos", value: s)) }
        if let last = RateMemory.lastManual(code), !refs.contains(where: { $0.value == last }) {
            refs.append(.init(name: "Tu última tasa manual", meta: "Solo esta vez", value: last))
        }
        references = refs
        if text.isEmpty, let d = dayRate { text = Fmt.editable(d, digits: 0...4) }
    }

    func pick(_ r: Reference) { text = Fmt.editable(r.value, digits: 0...4) }
    func isPicked(_ r: Reference) -> Bool { value.map { abs($0 - r.value) < 0.00001 } ?? false }
}

/// Remembers the last per-transaction rate per currency (for the "última manual" reference).
enum RateMemory {
    static func lastManual(_ code: String) -> Double? {
        let v = UserDefaults.standard.double(forKey: "rate_last_manual_\(code)"); return v > 0 ? v : nil
    }
    static func remember(_ code: String, _ v: Double) { UserDefaults.standard.set(v, forKey: "rate_last_manual_\(code)") }
}

enum RateParsing {
    /// Locale-tolerant: "1.234,5", "1,234.5", "9,96".
    static func parse(_ s: String) -> Double? {
        var t = s.filter { "0123456789.,".contains($0) }
        if let c = t.lastIndex(of: ","), let d = t.lastIndex(of: ".") {
            t = c > d ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") : t.replacingOccurrences(of: ",", with: "")
        } else { t = t.replacingOccurrences(of: ",", with: ".") }
        return Double(t)
    }
}

struct RateEditorSheet: View {
    @State var vm: RateEditorViewModel
    /// nil hides "solo esta vez" (global editing from Tasas del día).
    var onApplyOnce: ((Double) -> Void)?
    var onSaveGlobal: (Double) async -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text("1 dólar equivale a").font(.subheadline).foregroundStyle(VexiaColor.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            TextField("0", text: $vm.text)
                                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                                .keyboardType(.decimalPad).multilineTextAlignment(.center).fixedSize()
                                .focused($focused)
                                .accessibilityLabel("\(vm.code) por dólar")
                            Text(Fmt.symbol(vm.code) ?? vm.code).font(.title3.weight(.semibold)).foregroundStyle(VexiaColor.textSecondary)
                        }
                        Text(vm.deviationText).font(.footnote.weight(.semibold))
                            .foregroundStyle(abs(vm.deviation ?? 0) > 10 ? VexiaColor.cautionText : VexiaColor.textSecondary)
                    }
                    .padding(16).frame(maxWidth: .infinity)
                    .background(.background, in: .rect(cornerRadius: 22))

                    if !vm.references.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("REFERENCIAS").font(.footnote.weight(.semibold)).foregroundStyle(VexiaColor.textSecondary).padding(.leading, 4)
                            ForEach(vm.references) { r in
                                Button { vm.pick(r) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(r.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                            Text(r.meta).font(.caption).foregroundStyle(VexiaColor.textSecondary)
                                        }
                                        Spacer()
                                        Text(Fmt.grouped(r.value)).font(.headline.monospacedDigit()).foregroundStyle(.primary)
                                    }
                                    .padding(.horizontal, 14).frame(minHeight: 56)
                                    .background(.background, in: .rect(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(vm.isPicked(r) ? VexiaColor.brandBlue : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let p = vm.previewText {
                        HStack { Text("Este movimiento"); Spacer(); Text(p).fontWeight(.bold).monospacedDigit() }
                            .font(.subheadline).foregroundStyle(VexiaColor.brandBlue)
                            .padding(14).background(VexiaColor.tintSoft, in: .rect(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let onApplyOnce {
                        Button {
                            guard let v = vm.value else { return }
                            RateMemory.remember(vm.code, v); onApplyOnce(v); dismiss()
                        } label: { Text("Usar solo en este movimiento").font(.headline).frame(maxWidth: .infinity, minHeight: 34) }
                        .buttonStyle(.glassProminent).controlSize(.large)
                    }
                    Button {
                        guard let v = vm.value else { return }
                        saving = true
                        Task { await onSaveGlobal(v); saving = false; dismiss() }
                    } label: {
                        Text(saving ? "Guardando…" : "Guardar como tasa de hoy para todo").font(.headline).frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(onApplyOnce == nil ? AnyPrimitiveButtonStyle(.glassProminent) : AnyPrimitiveButtonStyle(.glass))
                    .controlSize(.large)
                }
                .disabled(vm.value == nil || saving)
                .padding(.horizontal).padding(.bottom, 8)
            }
            .navigationTitle("Tasa \(vm.code)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar", systemImage: "xmark") { dismiss() } } }
            .task { await vm.load() }
        }
        .presentationDetents([.large])
    }
}

/// Type-erased primitive button style (to switch glass / glassProminent conditionally).
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
