import SwiftUI

/// Tema "carta & inchiostro": carta calda chiara, testo inchiostro quasi nero,
/// un solo accento rosso cinema. Superfici piatte, bordi hairline scuri.
enum Theme {
    // MARK: - Colori
    static let bg = Color(hex: "#F4F1EA")            // carta calda
    static let surface = Color(hex: "#FBFAF6")       // carta più chiara (card)
    static let surfaceAlt = Color(hex: "#EAE6DC")    // carta scura (campi, track)
    static let border = Color(hex: "#DDD8CC")        // hairline d'inchiostro chiaro
    static let text = Color(hex: "#191817")          // inchiostro
    static let textDim = Color(hex: "#77726A")       // inchiostro diluito
    static let accent = Color(hex: "#C93B2F")        // rosso cinema
    static let onAccent = Color(hex: "#FDFCF9")      // carta: testo sopra il rosso
    static let accentDark = Color(hex: "#3A1814")    // track scuro per switch attivi
    static let danger = Color(hex: "#B42318")
    static let warn = Color(hex: "#A66A1E")
    static let ok = Color(hex: "#2F7D5B")

    static let bgGradTop = Color(hex: "#F6F3EC")
    static let bgGradBottom = Color(hex: "#EFEBE2")
    static let surfaceRaised = Color(hex: "#F1EDE4")

    // MARK: - Font (volto editoriale)
    /// Display: sans pesante per masthead e titoli.
    static let display = Font.system(size: 27, weight: .heavy).width(.condensed)
    /// Serif di lettura (corpo articolo, titoli pagina).
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Famiglia UI.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: - Spaziature / raggi
    static let radiusSm: CGFloat = 12
    static let radiusMd: CGFloat = 16
    static let radiusLg: CGFloat = 22
    static let radiusXl: CGFloat = 28
    static let pad: CGFloat = 16
}

// MARK: - Hex color init

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Colore con alpha (equivalente di theme.colors.x + "1A").
    func alpha(_ v: Double) -> Color { opacity(v) }
}

// MARK: - Componenti condivisi di stile

/// Card minimal: una sola superficie piatta con hairline, angoli calmi, niente ombre.
struct CardSurface: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface)
            .cornerRadius(Theme.radiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }
}

extension View {
    func cardSurface(padding: CGFloat = 18) -> some View { modifier(CardSurface(padding: padding)) }
}

/// Occhiello editoriale (uppercase, tracking largo).
struct EyebrowText: View {
    let text: String
    var color: Color = Theme.textDim
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .kerning(2.2)
            .foregroundColor(color)
    }
}

/// Header condiviso: occhiello + titolo display + azioni a destra.
struct ScreenHeader<Right: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    var right: Right

    init(eyebrow: String, title: String, subtitle: String? = nil, right: Right) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.right = right
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                EyebrowText(text: eyebrow)
                Spacer()
                right
            }
            Text(title)
                .font(Theme.display)
                .foregroundColor(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.ui(12.5))
                    .foregroundColor(Theme.textDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ScreenHeader where Right == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, right: EmptyView())
    }
}

/// Badge a tonalità.
struct Badge: View {
    let label: String
    var tone: Color = Theme.accent

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy))
            .kerning(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.alpha(0.10))
            .cornerRadius(8)
            .foregroundColor(tone)
    }
}

/// Bottone pill primario (accento pieno, testo carta).
struct PillButton: View {
    let label: String
    var filled: Bool = true
    var role: Role = .normal
    let action: () -> Void

    enum Role { case normal, destructive }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.ui(14, .semibold))
                .lineLimit(1)
        }
        .buttonStyle(PillStyle(filled: filled, role: role))
    }

    struct PillStyle: ButtonStyle {
        var filled: Bool
        var role: Role
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(.vertical, 15)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
                .foregroundColor(textColor)
                .background(
                    RoundedRectangle(cornerRadius: 999)
                        .fill(fillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(strokeColor, lineWidth: 0.5)
                )
                .opacity(configuration.isPressed ? 0.7 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
        }
        private var fillColor: Color {
            if filled { return role == .destructive ? Theme.danger : Theme.accent }
            return Theme.surfaceAlt
        }
        private var strokeColor: Color {
            filled ? Color.clear : Theme.border
        }
        private var textColor: Color {
            filled ? Theme.onAccent : (role == .destructive ? Theme.danger : Theme.text)
        }
    }
}

/// Bottone minimale (vetro finto: superficie alt + hairline).
struct GhostButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.ui(14, .semibold))
                .foregroundColor(Theme.text)
                .padding(.vertical, 15)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
                .background(Theme.surfaceAlt.cornerRadius(999))
                .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/// Stato vuoto: icona in pozzetto, titolo serif, sottotitolo.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.surfaceAlt)
                    .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                Text(icon).font(.system(size: 28))
            }
            .frame(width: 64, height: 64)
            .padding(.bottom, 8)

            Text(title)
                .font(Theme.serif(18))
                .foregroundColor(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.ui(13))
                    .foregroundColor(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity)
    }
}

/// Campo testo pill (superficie alt, bordo accento se attivo).
struct InputField: View {
    var placeholder: String
    @Binding var value: String
    var secure: Bool = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $value)
            } else {
                TextField(placeholder, text: $value)
            }
        }
        .font(Theme.ui(16))
        .foregroundColor(Theme.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surfaceAlt.cornerRadius(999))
        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
    }
}

/// Meta testo (fonte · tempo).
struct MetaText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.textDim)
    }
}

/// Poster con fallback.
struct PosterView: View {
    let url: String?
    var corner: CGFloat = Theme.radiusSm

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init)) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    Theme.surfaceAlt
                    Text("🎬").font(.system(size: 26))
                }
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

/// Data lunga italiana (masthead): "venerdì 26 settembre".
func todayItalian() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "EEEE d MMMM"
    let s = f.string(from: Date())
    return s.prefix(1).uppercased() + s.dropFirst()
}

/// Data di uscita formattata: "12 settembre 2026".
func fmtReleaseDate(_ iso: String?) -> String {
    guard let iso else { return "data non disponibile" }
    let inF = ISO8601DateFormatter()
    inF.formatOptions = [.withFullDate]
    if let d = inF.date(from: iso) {
        return longIT(d)
    }
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "yyyy-MM-dd"
    if let d = f.date(from: String(iso.prefix(10))) {
        return longIT(d)
    }
    return iso
}

private func longIT(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "it_IT")
    f.dateFormat = "d MMMM yyyy"
    return f.string(from: d)
}
