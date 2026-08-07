//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import UIKit

/// Loading view footer for media picker view
class MediaPickerViewLoadingFooter: UICollectionReusableView {
    let loadingIndicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(loadingIndicator)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addConstraints([
            centerXAnchor.constraint(equalTo: loadingIndicator.centerXAnchor),
            centerYAnchor.constraint(equalTo: loadingIndicator.centerYAnchor),
        ])
        loadingIndicator.startAnimating()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
