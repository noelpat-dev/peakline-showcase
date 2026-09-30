// Excerpt from Peakline (private repository), shared for portfolio review.
// © 2026 Noel Patricks. All rights reserved. Not licensed for reuse.
// Source: GymTracker/Views/Shared/SummitToolbarButton.swift

import SwiftUI
import UIKit

// On-theme navigation buttons for pushed Summit screens: a plain ink glyph in a
// thin hairline circle on the paper, drawn like `SummitLoggerHeader`'s round
// buttons. Use a `Label` in a toolbar `Button`/`Menu` with
// `.labelStyle(.summitToolbarGlyph)` (or `.summitToolbarPill` for words), give
// each toolbar item `.summitToolbarBare()`, and add `.summitSwipeBackEnabled()`
// on any screen that hides the system back button.

/// Icon-only label: the glyph inside a 44pt hairline circle.
struct SummitToolbarGlyphLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        SummitToolbarGlyph(icon: configuration.icon)
    }
}

/// Icon and words inside a 44pt-high hairline capsule, like the logger's End
/// button.
struct SummitToolbarPillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        SummitToolbarPill(icon: configuration.icon, title: configuration.title)
    }
}

extension LabelStyle where Self == SummitToolbarGlyphLabelStyle {
    static var summitToolbarGlyph: SummitToolbarGlyphLabelStyle { SummitToolbarGlyphLabelStyle() }
}

extension LabelStyle where Self == SummitToolbarPillLabelStyle {
    static var summitToolbarPill: SummitToolbarPillLabelStyle { SummitToolbarPillLabelStyle() }
}

struct SummitToolbarGlyph<Icon: View>: View {
    @Environment(\.appTheme) private var appTheme
    let icon: Icon

    var body: some View {
        icon
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(appTheme.colors.summitInk)
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(appTheme.colors.summitInk.opacity(0.14), lineWidth: 1))
            .contentShape(Circle())
    }
}

struct SummitToolbarPill<Icon: View, Title: View>: View {
    @Environment(\.appTheme) private var appTheme
    let icon: Icon
    let title: Title

    var body: some View {
        HStack(spacing: 6) {
            icon
            title
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(appTheme.colors.summitInk)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .overlay(Capsule().stroke(appTheme.colors.summitInk.opacity(0.14), lineWidth: 1))
        .contentShape(Capsule())
    }
}

extension ToolbarContent {
    /// Drops the iOS 26 Liquid Glass bubble and grouped capsule so the drawn
    /// Summit button sits straight on the paper. No-op before iOS 26.
    @ToolbarContentBuilder
    func summitToolbarBare() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

extension View {
    /// Hiding the system back button also switches off the edge swipe. This
    /// keeps the interactive pop gesture working with a redrawn back button.
    func summitSwipeBackEnabled() -> some View {
        background(SummitSwipeBackEnabler().frame(width: 0, height: 0))
    }

    /// Redraws a pushed screen's back button as the Summit glyph instead of the
    /// system Liquid Glass bubble, with the edge swipe kept alive. The button
    /// calls `dismiss`, so use it only where the screen is pushed, never on a
    /// sheet's root.
    func summitBackButton(identifier: String) -> some View {
        modifier(SummitBackButtonModifier(identifier: identifier))
    }
}

private struct SummitBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let identifier: String

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .summitSwipeBackEnabled()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .labelStyle(.summitToolbarGlyph)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier(identifier)
                }
                .summitToolbarBare()
            }
    }
}

private struct SummitSwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var previousDelegate: UIGestureRecognizerDelegate?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let recognizer = navigationController?.interactivePopGestureRecognizer,
                  recognizer.delegate !== self else { return }
            previousDelegate = recognizer.delegate
            recognizer.delegate = self
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if let recognizer = navigationController?.interactivePopGestureRecognizer,
               recognizer.delegate === self {
                recognizer.delegate = previousDelegate
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
