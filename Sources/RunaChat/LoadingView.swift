import UIKit

/// The chat screen while its page loads (1.1.1): the mark of Ask Quicklly in search's working line — the sparkle in a
/// spinning ring — and the assistant's name under it, on white, a little above the middle. It fades out once the page
/// says the chat has drawn (`shown`).
final class LoadingView: UIView {

    // The Runa sparkle as the search answer draws it (its logo in #111), 96 px.
    private static let sparkPNG = """
        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
        """

    private let ringHost = RingView()

    init(title: String) {
        super.init(frame: .zero)
        backgroundColor = .white
        isAccessibilityElement = true
        accessibilityLabel = "Loading \(title)"
        accessibilityIdentifier = "runa-loading"

        let ink = UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1)
        let spark = UIImageView(image: Data(base64Encoded: Self.sparkPNG).flatMap { UIImage(data: $0, scale: 96.0 / 20.0) })
        let name = UILabel()
        name.text = title
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        name.textColor = ink

        let mark = UIView()
        for v in [ringHost, spark] { v.translatesAutoresizingMaskIntoConstraints = false; mark.addSubview(v) }
        let group = UIStackView(arrangedSubviews: [mark, name])
        group.axis = .vertical
        group.alignment = .center
        group.spacing = 14
        group.translatesAutoresizingMaskIntoConstraints = false
        addSubview(group)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 44),
            mark.heightAnchor.constraint(equalToConstant: 44),
            ringHost.topAnchor.constraint(equalTo: mark.topAnchor),
            ringHost.bottomAnchor.constraint(equalTo: mark.bottomAnchor),
            ringHost.leadingAnchor.constraint(equalTo: mark.leadingAnchor),
            ringHost.trailingAnchor.constraint(equalTo: mark.trailingAnchor),
            spark.widthAnchor.constraint(equalToConstant: 20),
            spark.heightAnchor.constraint(equalToConstant: 20),
            spark.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
            spark.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            group.centerXAnchor.constraint(equalTo: centerXAnchor),
            // the group's middle at 42 % of the screen, where the eye lands
            NSLayoutConstraint(item: group, attribute: .centerY, relatedBy: .equal, toItem: self, attribute: .centerY, multiplier: 0.84, constant: 0),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(title:)") }

    var isShowing: Bool { !isHidden }

    func show() {
        layer.removeAllAnimations()
        alpha = 1
        isHidden = false
        startSpin()
    }

    /// Fades out over 0.2 s, or at once (an error screen takes its place).
    func hide(animated: Bool) {
        guard !isHidden else { return }
        guard animated else { finish(); return }
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }, completion: { _ in self.finish() })
    }

    private func finish() {
        isHidden = true
        alpha = 1
        ringHost.layer.removeAnimation(forKey: "spin")
    }

    private func startSpin() {
        // one turn every 0.9 s, like the search answer; still when the phone asks for reduced motion
        guard !UIAccessibility.isReduceMotionEnabled, ringHost.layer.animation(forKey: "spin") == nil else { return }
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = 0
        a.toValue = 2 * Double.pi
        a.duration = 0.9
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false          // keeps spinning after the app returns from the background
        ringHost.layer.add(a, forKey: "spin")
    }
}

/// The ring: a black head fading back into a clear tail (clear to 120°, 35 % at 220°, black at 340°), 2.5 pt — the search
/// answer's conic gradient. Its layers follow its own size.
private final class RingView: UIView {
    private let gradient = CAGradientLayer()
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)            // 0° at 12 o'clock, clockwise
        let ink = UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1)
        gradient.colors = [ink.withAlphaComponent(0), ink.withAlphaComponent(0), ink.withAlphaComponent(0.35), ink, ink.withAlphaComponent(0), ink.withAlphaComponent(0)].map { $0.cgColor }
        gradient.locations = [0, 120.0 / 360, 220.0 / 360, 340.0 / 360, 341.0 / 360, 1].map { NSNumber(value: $0) }
        shape.fillColor = UIColor.clear.cgColor
        shape.strokeColor = UIColor.black.cgColor
        shape.lineWidth = 2.5
        gradient.mask = shape
        layer.addSublayer(gradient)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        shape.frame = bounds
        shape.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 1.25, dy: 1.25)).cgPath
    }
}
