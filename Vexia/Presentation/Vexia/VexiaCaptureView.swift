import SwiftUI
import PhotosUI

struct VexiaCaptureView: View {
    @State var vm: VexiaCaptureViewModel
    var mode: Mode = .voice
    /// Called with the AI draft + notes; the parent presents the transaction form.
    var onDraft: (TransactionDraft, [String], String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    enum Mode { case voice, receipt }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                orb
                Text(statusText).font(.headline).multilineTextAlignment(.center)
                if !vm.transcript.isEmpty {
                    Text("“\(vm.transcript)”").font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                if case .error(let m) = vm.phase {
                    Label(m, systemImage: "exclamationmark.triangle").foregroundStyle(VexiaColor.error)
                        .multilineTextAlignment(.center).padding(.horizontal)
                        .fixedSize(horizontal: false, vertical: true) // short sheet detent was truncating the reason
                }
                Spacer()
                controls
            }
            .padding()
            .navigationTitle("Vexia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar", systemImage: "xmark") { Task { await vm.cancel(); dismiss() } }
                }
            }
            .task {
                await vm.prepare()
                if mode == .voice { await vm.startListening() }
            }
            .onChange(of: vm.phase) { _, p in
                if p == .review, let d = vm.draft { onDraft(d, vm.notes, vm.transcript.isEmpty ? vm.typedText : vm.transcript); dismiss() }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let jpeg = UIImage(data: data)?.downscaled(maxSide: 1600).jpegData(compressionQuality: 0.7) {
                        await vm.processReceipt(jpeg)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var statusText: String {
        switch vm.phase {
        case .idle: mode == .voice ? String(localized: "Toca el micrófono y dime tu gasto o ingreso") : String(localized: "Elige la foto de tu comprobante")
        case .listening: String(localized: "Te escucho… (ej. “gasté 50 en almuerzo”)")
        case .thinking: String(localized: "Analizando…")
        case .review: String(localized: "¡Listo!")
        case .error: String(localized: "No pude procesarlo")
        }
    }

    private var orb: some View {
        ZStack {
            Circle().fill(VexiaColor.heroGradient).frame(width: 120, height: 120)
                .scaleEffect(vm.phase == .listening ? 1.08 : 1)
                .animation(vm.phase == .listening ? .easeInOut(duration: 0.8).repeatForever() : .default, value: vm.phase)
            Image(systemName: vm.phase == .thinking ? "sparkles" : mode == .voice ? "waveform" : "doc.text.viewfinder")
                .font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: vm.phase == .listening || vm.phase == .thinking)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            if mode == .voice {
                if vm.phase == .listening {
                    Button { Task { await vm.stopAndProcess() } } label: {
                        Label("Terminar", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.glassProminent).controlSize(.large)
                } else if vm.phase != .thinking {
                    Button { Task { await vm.startListening() } } label: {
                        Label("Hablar", systemImage: "mic.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.glassProminent).controlSize(.large)
                }
                HStack {
                    TextField("O escríbelo aquí…", text: $vm.typedText).textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await vm.processTyped() } }
                    Button("Enviar", systemImage: "arrow.up.circle.fill") { Task { await vm.processTyped() } }
                        .labelStyle(.iconOnly).font(.title2).disabled(vm.typedText.isEmpty)
                }
            } else {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Elegir comprobante", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).controlSize(.large).disabled(vm.phase == .thinking)
            }
        }
    }
}

extension UIImage {
    func downscaled(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
