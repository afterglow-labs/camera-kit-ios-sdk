//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import UIKit

/// Carousel collection view cell which represents a single lens item/icon
public class CarouselCollectionViewCell: UICollectionViewCell {
    public let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Activity indicator view that should activate when lens content is loading
    public let activityIndicatorView: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView()
        view.style = .medium
        view.color = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    public init() {
        super.init(frame: .zero)
        commonInit()
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        imageView.layer.cornerRadius = min(imageView.bounds.width, imageView.bounds.height) / 2
    }

    private func commonInit() {
        backgroundColor = .clear
        isAccessibilityElement = true
        contentView.addSubview(imageView)
        contentView.addSubview(activityIndicatorView)
        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            activityIndicatorView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
}
