import SwiftUI

/// Maps backend category icon names (Material icon names) / codes to SF Symbols.
enum CategorySymbol {
    static func of(icon: String?, name: String? = nil, type: TransactionType? = nil) -> String {
        let key = "\(icon ?? "") \(name ?? "")".lowercased()
        let table: [(String, String)] = [
            ("restaurant", "fork.knife"), ("food", "fork.knife"), ("comida", "fork.knife"), ("aliment", "cart"),
            ("grocer", "cart"), ("supermerc", "cart"), ("shopping", "bag"), ("compra", "bag"),
            ("transport", "car"), ("car", "car"), ("fuel", "fuelpump"), ("gas", "fuelpump"), ("taxi", "car"),
            ("home", "house"), ("house", "house"), ("hogar", "house"), ("rent", "house"), ("alquiler", "house"),
            ("health", "cross.case"), ("salud", "cross.case"), ("medical", "cross.case"), ("pharm", "pills"),
            ("education", "graduationcap"), ("school", "graduationcap"), ("educa", "graduationcap"),
            ("entertain", "popcorn"), ("movie", "film"), ("ocio", "popcorn"), ("game", "gamecontroller"),
            ("travel", "airplane"), ("flight", "airplane"), ("viaje", "airplane"),
            ("salary", "briefcase"), ("salario", "briefcase"), ("sueldo", "briefcase"), ("work", "briefcase"),
            ("invest", "chart.line.uptrend.xyaxis"), ("crypto", "bitcoinsign.circle"),
            ("bill", "doc.text"), ("utilit", "bolt"), ("servicio", "bolt"), ("electric", "bolt"), ("water", "drop"),
            ("phone", "iphone"), ("internet", "wifi"), ("subscri", "repeat"), ("suscrip", "repeat"),
            ("gift", "gift"), ("regalo", "gift"), ("pet", "pawprint"), ("mascota", "pawprint"),
            ("cloth", "tshirt"), ("ropa", "tshirt"), ("sport", "figure.run"), ("gym", "dumbbell"),
            ("coffee", "cup.and.saucer"), ("cafe", "cup.and.saucer"), ("bank", "building.columns"),
            ("saving", "banknote"), ("ahorro", "banknote"), ("tax", "percent"), ("impuesto", "percent"),
        ]
        if let hit = table.first(where: { key.contains($0.0) }) { return hit.1 }
        switch type {
        case .income: return "arrow.down.left.circle"
        case .transfer: return "arrow.left.arrow.right"
        default: return "tag"
        }
    }

    /// Backend category icons are emojis (e.g. "🍲"); returns it when present.
    static func emoji(_ icon: String?) -> String? {
        guard let icon, !icon.isEmpty, icon.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value > 0x2000 }) else { return nil }
        return icon
    }

    static func color(for key: String) -> Color {
        // Stable across launches (String.hashValue is seeded per process).
        let idx = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff } % VexiaColor.categoryPalette.count
        return VexiaColor.categoryPalette[idx]
    }
}

struct IconBadge: View {
    let symbol: String
    var color: Color = .accentColor
    var size: CGFloat = 40
    var emoji: String? = nil
    var body: some View {
        Group {
            if let emoji { Text(emoji).font(.system(size: size * 0.5)) }
            else { Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(color) }
        }
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: .rect(cornerRadius: size * 0.3))
    }
}

struct TransactionRow: View {
    let tx: Transaction
    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: tx.isCurrencyExchange ? "dollarsign.arrow.circlepath" : CategorySymbol.of(icon: tx.categoryIcon, name: tx.categoryName, type: tx.type),
                      color: color, emoji: tx.type == .transfer ? nil : CategorySymbol.emoji(tx.categoryIcon))
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.description.isEmpty ? (tx.categoryName ?? tx.type.title) : tx.description)
                    .font(.body.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(VexiaColor.textSecondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(amountColor)
                if tx.isCurrencyExchange, let to = tx.toAmount {
                    Text("→ \(Fmt.money(abs(to), currency: tx.fxTargetCode ?? ""))").font(.caption.monospacedDigit()).foregroundStyle(VexiaColor.brandGreen)
                    if let r = tx.exchangeRate, r > 0 { Text(fxRateText(r)).font(.caption2.monospacedDigit()).foregroundStyle(VexiaColor.textSecondary) }
                }
                if tx.isRecurring { Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch tx.type { case .income: VexiaColor.income; case .expense: CategorySymbol.color(for: tx.categoryName ?? "x"); case .transfer: tx.isCurrencyExchange ? VexiaColor.brandGreen : VexiaColor.info }
    }
    /// USD-anchored when one side is USD ("1 USD = 10,00 Bs"), else "1 BOB = 0,1300 EUR".
    private func fxRateText(_ r: Double) -> String {
        let from = tx.displayCurrency.uppercased(), to = tx.fxTargetCode ?? ""
        if to == "USD" { return "1 USD = \(Fmt.grouped(1 / r)) \(Fmt.symbol(from) ?? from)" }
        if from == "USD" { return "1 USD = \(Fmt.grouped(r)) \(Fmt.symbol(to) ?? to)" }
        return "1 \(from) = \(Fmt.grouped(r, decimals: 4)) \(to)"
    }

    private var subtitle: String {
        if tx.type == .transfer { return "\(tx.fromAccountName ?? tx.accountName ?? "") → \(tx.toAccountName ?? "")" }
        return [tx.categoryName, tx.accountName].compactMap { $0 }.joined(separator: " · ")
    }
    private var amountText: String {
        tx.type == .transfer ? Fmt.money(abs(tx.amount), currency: tx.displayCurrency)
            : Fmt.signedMoney(tx.amount, currency: tx.displayCurrency, isIncome: tx.isIncome)
    }
    private var amountColor: Color {
        switch tx.type { case .income: VexiaColor.incomeText; case .expense: .primary; case .transfer: tx.isCurrencyExchange ? VexiaColor.brandGreen : VexiaColor.brandBlue }
    }
}

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var symbol: String
    var tint: Color = .accentColor
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(tint)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 16))
    }
}

struct GainText: View {
    let value: Double
    var percent: Double? = nil
    var currency: String = "USD"
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
            Text(Fmt.money(value, currency: currency))
            if let percent { Text("(\(Fmt.percent(percent)))") }
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(value >= 0 ? VexiaColor.success : VexiaColor.error)
    }
}

/// Avatar with initials.
struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 32
    var body: some View {
        Text(initials).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(VexiaColor.heroGradient, in: .circle)
    }
}

/// App-wide "saved" banner state, injected by `MainTabView`. A reference type keeps the environment
/// value stable (a stored closure would invalidate every reader on each update).
@Observable final class SavedBannerCenter {
    var message: String?
    func announce(_ message: String) { self.message = message }
}

/// Transient confirmation after a save. Forms dismiss on success, so without it nothing tells the
/// user the data was stored.
struct SavedBanner: ViewModifier {
    @Bindable var center: SavedBannerCenter

    static func summary(type: TransactionType, isEditing: Bool, isExchange: Bool, amount: String, account: String?) -> String {
        let what: String = if isEditing { String(localized: "Cambios guardados") } else {
            switch type {
            case .expense: String(localized: "Gasto guardado")
            case .income: String(localized: "Ingreso guardado")
            case .transfer: isExchange ? String(localized: "Cambio registrado") : String(localized: "Transferencia registrada")
            }
        }
        return ([what, amount] + [account].compactMap { $0 }).joined(separator: " · ")
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = center.message {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(VexiaColor.incomeText)
                        Text(message).lineLimit(2)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal).padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { center.message = nil }
                }
            }
            .animation(.snappy, value: center.message)
            .sensoryFeedback(.success, trigger: center.message) { _, new in new != nil }
            .task(id: center.message) {
                guard let message = center.message else { return }
                AccessibilityNotification.Announcement(message).post()
                try? await Task.sleep(for: .seconds(3))
                if center.message == message { center.message = nil }
            }
    }
}

extension View {
    /// Standard alert for ViewModel error strings.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Error", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message.wrappedValue ?? "") }
    }
}
