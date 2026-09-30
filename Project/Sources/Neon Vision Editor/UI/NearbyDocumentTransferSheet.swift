import SwiftUI

extension Notification.Name {
    static let nearbyDocumentTransferRequested = Notification.Name("nearbyDocumentTransferRequested")
}

struct NearbyDocumentTransferPresentation: ViewModifier {
    enum Mode: String, Identifiable {
        case send, receive
        var id: String { rawValue }
    }
    let viewModel: EditorViewModel
    @State private var mode: Mode?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .nearbyDocumentTransferRequested)) { notification in
                guard let target = notification.object as? EditorViewModel, target === viewModel,
                      let value = notification.userInfo?["mode"] as? String,
                      let requested = Mode(rawValue: value) else { return }
                mode = requested
            }
            .sheet(item: $mode) { mode in
                NearbyDocumentTransferSheet(mode: mode, viewModel: viewModel)
            }
    }
}

private struct NearbyDocumentTransferSheet: View {
    let mode: NearbyDocumentTransferPresentation.Mode
    let viewModel: EditorViewModel
    @StateObject private var transfer = NearbyDocumentTransfer()
    @State private var snapshot: NearbyDocumentSnapshot?
    @State private var selectedPeerID: String?
    @State private var code = ""
    @State private var preparationError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .send ? "Send to Nearby Device" : "Receive Document")
                .font(.title2.bold())
            if mode == .send {
                if let snapshot {
                    Text("\(snapshot.offer.name) · \(snapshot.offer.byteCount.formatted()) bytes")
                    Text("The receiving device must accept before document contents are sent.")
                        .font(.callout)
                    if transfer.peers.isEmpty && !transfer.isBusy && !transfer.didComplete {
                        Text("Open Receive Document on the other device to make it discoverable.")
                    }
                    ForEach(transfer.peers) { peer in
                        Button {
                            selectedPeerID = peer.id
                        } label: {
                            Label(peer.name, systemImage: selectedPeerID == peer.id ? "checkmark.circle.fill" : "circle")
                        }
                        .disabled(transfer.isBusy)
                        .accessibilityIdentifier("nearby-peer-\(peer.id)")
                    }
                    SecureField("Pairing code from the receiving device", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .disabled(transfer.isBusy)
                        .accessibilityIdentifier("nearby-pairing-code")
                    Button("Send Document") {
                        guard let peer = transfer.peers.first(where: { $0.id == selectedPeerID }) else { return }
                        transfer.send(snapshot, to: peer.endpoint, code: code)
                    }
                    .disabled(selectedPeerID == nil || code.isEmpty || transfer.isBusy || transfer.didComplete)
                    .accessibilityIdentifier("nearby-send")
                }
            } else if !transfer.pairingCode.isEmpty {
                Text("Receiving device: \(transfer.advertisedName)")
                Text("Pairing code")
                Text(transfer.pairingCode)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel("Pairing code: \(transfer.pairingCode)")
                    .accessibilityIdentifier("nearby-receive-code")
                Text("Device names are labels. Confirm the code on the device you intend to receive from.")
                    .font(.callout)
            }
            if let preparationError {
                Text(preparationError).foregroundStyle(.red)
            }
            Text(transfer.status)
                .font(.callout)
                .accessibilityIdentifier("nearby-status")
                .accessibilityAddTraits(.updatesFrequently)
            HStack {
                Spacer()
                Button(transfer.didComplete ? "Done" : "Cancel") {
                    transfer.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("nearby-cancel")
            }
        }
        .padding(24)
        .frame(idealWidth: 480)
        .alert("Receive document?", isPresented: Binding(
            get: { transfer.pendingOffer != nil },
            set: { if !$0 { transfer.answerOffer(accept: false) } }
        )) {
            Button("Accept") { transfer.answerOffer(accept: true) }
            Button("Decline", role: .cancel) { transfer.answerOffer(accept: false) }
        } message: {
            if let offer = transfer.pendingOffer {
                Text("Receive \(offer.name) (\(offer.byteCount.formatted()) bytes) as an independent copy?")
            }
        }
        .task {
            transfer.onReceive = { document in
                _ = viewModel.openFile(url: document.url, preferredEncoding: document.encoding, usesAutomaticEncoding: false)
            }
            if mode == .receive {
                transfer.receive()
            } else {
                guard let tab = viewModel.selectedTab, !tab.isLoadingContent, !tab.isReadOnlyPreview,
                      !tab.isPartialFilePreview,
                      tab.document.utf16Length <= NearbyDocumentOffer.maximumBytes else {
                    preparationError = NearbyDocumentTransferError.invalidDocument.localizedDescription
                    return
                }
                let name = tab.name.contains(".") ? tab.name : tab.name + ".txt"
                let text = tab.document.string()
                let encoding = tab.fileEncoding
                let lineEnding = tab.lineEnding
                do {
                    let prepared = try await Task.detached(priority: .userInitiated) {
                        try NearbyDocumentSnapshot.make(name: name, text: text, encoding: encoding, lineEnding: lineEnding)
                    }.value
                    guard !Task.isCancelled else { return }
                    snapshot = prepared
                    transfer.browse()
                } catch {
                    preparationError = error.localizedDescription
                }
            }
        }
        .onDisappear { transfer.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { transfer.cancel(); dismiss() }
        }
    }
}

extension ContentView {
    var nearbyDocumentTransferMenu: some View {
        Group {
            Button("Send to Nearby Device…") { requestNearbyTransfer(.send) }
                .disabled(viewModel.selectedTab == nil)
                .accessibilityIdentifier("nearby-open-send")
            Button("Receive Document…") { requestNearbyTransfer(.receive) }
                .accessibilityIdentifier("nearby-open-receive")
        }
    }
    private func requestNearbyTransfer(_ mode: NearbyDocumentTransferPresentation.Mode) {
        NotificationCenter.default.post(name: .nearbyDocumentTransferRequested, object: viewModel,
                                        userInfo: ["mode": mode.rawValue])
    }
}
