#if os(iOS) || os(macOS)
import SwiftUI
#if os(iOS)
import UIKit
#endif

public extension View {
    /// Uses the same discard choice for Cancel and an attempted interactive dismissal.
    func planBaseDiscardConfirmation(
        isPresented: Binding<Bool>,
        hasUnsavedChanges: Bool,
        isSaving: Bool = false,
        message: String = "저장하지 않은 변경사항이 사라집니다.",
        onDiscard: @escaping () -> Void
    ) -> some View {
        modifier(PlanBaseDiscardConfirmation(
            isPresented: isPresented,
            hasUnsavedChanges: hasUnsavedChanges,
            isSaving: isSaving,
            message: message,
            onDiscard: onDiscard
        ))
    }
}

private struct PlanBaseDiscardConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    var hasUnsavedChanges: Bool
    var isSaving: Bool
    var message: String
    var onDiscard: () -> Void

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .background {
                PlanBaseSheetDismissGuard(isBlocked: hasUnsavedChanges || isSaving) {
                    guard hasUnsavedChanges, !isSaving else { return }
                    isPresented = true
                }
            }
            #else
            .interactiveDismissDisabled(hasUnsavedChanges || isSaving)
            #endif
            .alert("변경사항을 버릴까요?", isPresented: $isPresented) {
                Button("변경사항 버리기", role: .destructive, action: onDiscard)
                Button("계속 작성", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

#if os(iOS)
private struct PlanBaseSheetDismissGuard: UIViewControllerRepresentable {
    var isBlocked: Bool
    var onAttempt: () -> Void

    func makeUIViewController(context: Context) -> PlanBaseDismissGuardController {
        let controller = PlanBaseDismissGuardController()
        controller.isBlocked = isBlocked
        controller.onAttempt = onAttempt
        return controller
    }

    func updateUIViewController(_ controller: PlanBaseDismissGuardController, context: Context) {
        controller.isBlocked = isBlocked
        controller.onAttempt = onAttempt
        controller.installDelegate()
    }
}

private final class PlanBaseDismissGuardController: UIViewController, UIAdaptivePresentationControllerDelegate {
    var isBlocked = false
    var onAttempt: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installDelegate()
    }

    func installDelegate() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.parent?.presentationController?.delegate = self
        }
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        !isBlocked
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        onAttempt?()
    }
}
#endif
#endif
