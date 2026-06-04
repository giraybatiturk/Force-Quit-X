import AppKit

/// A menu row that shows an app's icon + name on the left and a dedicated
/// force-quit button on the right. Clicking the row body does nothing — only the
/// kill button terminates the app, so a stray click on the name can't fat-finger
/// a force-quit. The row itself has no hover highlight (that would falsely signal
/// the whole row is clickable); only the kill button reacts to the cursor.
/// Used for both the running-apps and background-processes sections.
final class AppMenuItemView: NSView {

    private let onKill: () -> Void

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let killButton = HoverKillButton()

    init(
        icon: NSImage?,
        title: String,
        isFrontmost: Bool,
        isBackground: Bool,
        onKill: @escaping () -> Void
    ) {
        self.onKill = onKill
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: isBackground ? 24 : 28))
        // The root view stays frame-based — the menu sizes the row from this frame.
        // Only the subviews below use Auto Layout. (Setting translatesAutoresizing-
        // MaskIntoConstraints = false on the root collapses the row to zero size.)

        let iconSize: CGFloat = isBackground ? 16 : 18
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        configureTitle(title, isFrontmost: isFrontmost, isBackground: isBackground)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        killButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Force quit \(title)")
        killButton.isBordered = false
        killButton.imagePosition = .imageOnly
        killButton.setButtonType(.momentaryChange)
        killButton.contentTintColor = .tertiaryLabelColor
        killButton.target = self
        killButton.action = #selector(killTapped)
        killButton.toolTip = "Force quit \(title)"
        killButton.setAccessibilityLabel("Force quit \(title)")
        killButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(killButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: killButton.leadingAnchor, constant: -8),

            killButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            killButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            killButton.widthAnchor.constraint(equalToConstant: 16),
            killButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureTitle(_ title: String, isFrontmost: Bool, isBackground: Bool) {
        let baseSize: CGFloat = isBackground ? 11 : 13
        let baseColor: NSColor = isBackground ? .secondaryLabelColor : .labelColor

        guard isFrontmost else {
            titleLabel.stringValue = title
            titleLabel.font = NSFont.systemFont(ofSize: baseSize, weight: .regular)
            titleLabel.textColor = baseColor
            return
        }

        // Frontmost app: bold name + a muted "(Frontmost)" tag.
        let attributed = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: baseSize, weight: .semibold),
                .foregroundColor: baseColor,
            ])
        attributed.append(
            NSAttributedString(
                string: "  (Frontmost)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: baseSize, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
        titleLabel.attributedStringValue = attributed
    }

    /// The initial frame width is only a minimum — once inserted, stretch to the
    /// menu's actual width so the kill button stays flush to the right edge even
    /// when a longer standard item (e.g. "Force Quit All Except Frontmost") widens
    /// the menu. Never grows past the superview, so it can't enlarge the menu.
    override func layout() {
        super.layout()
        if let width = superview?.bounds.width, width > frame.width {
            setFrameSize(NSSize(width: width, height: frame.height))
        }
    }

    @objc private func killTapped() {
        // Close the menu like a normal selection would, then terminate.
        enclosingMenuItem?.menu?.cancelTracking()
        onKill()
    }
}

/// A borderless icon button that brightens to red and shows a pointing-hand
/// cursor while hovered, so the cursor's only highlight target is the real action.
private final class HoverKillButton: NSButton {

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
    }

    override func mouseEntered(with event: NSEvent) {
        contentTintColor = .systemRed
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = .tertiaryLabelColor
        NSCursor.arrow.set()
    }
}
