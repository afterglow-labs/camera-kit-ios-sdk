//  Copyright Snap Inc. All rights reserved.
//  SCSDKCameraKitReferenceUI

import UIKit

public protocol RingLightColorSelectionViewDelegate: AnyObject {
    /// Notifies the delegate that a color was selected.
    /// - Parameters:
    ///    - view: The ring light color selection view.
    ///    - selectedColor: The color that was just selected.
    func ringLightColorSelectionView(_ view: RingLightColorSelectionView, selectedColor color: UIColor)
}

public class RingLightColorSelectionView: UIView {
    /// Delegate for handling updates to the color selection.
    public weak var delegate: RingLightColorSelectionViewDelegate?

    /// The set of colors to choose from.
    private let colors: [UIColor] = [
        UIColor(hex: 0xFFFFFF),
        UIColor(hex: 0xFFECBB),
        UIColor(hex: 0xFFD166),
        UIColor(hex: 0xFFC7A8),
        UIColor(hex: 0xFFB3C7),
        UIColor(hex: 0xD9C2FF),
        UIColor(hex: 0xD7F8FF),
        UIColor(hex: 0x9AFBFF),
        UIColor(hex: 0xB8FFD9),
    ]

    // MARK: Views

    /// Layout specification for the collection view.
    private let collectionViewLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 48, height: 48)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        return layout
    }()

    /// Collection view which contains the different color options for the ring light.
    public lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.accessibilityIdentifier = FlashControlElements.ringLightColorSelector.id
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(
            RingLightColorSelectionViewCell.self,
            forCellWithReuseIdentifier: RingLightColorSelectionViewCell.reuseIdentifer
        )
        collectionView.backgroundColor = .white.withAlphaComponent(0.1)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        setupCollectionView()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: 31)
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        collectionView.layer.mask = maskLayer
    }

    override public var intrinsicContentSize: CGSize {
        CGSize(
            width: UIView.noIntrinsicMetric,
            height: collectionViewLayout.itemSize.height
        )
    }
}

// MARK: Collection View

extension RingLightColorSelectionView {
    /// To be called the first time the ring light color selection view appears.
    /// - Parameter indexPath: The index path of the color cell to initially select.
    public func performInitialSelection(indexPath: IndexPath = IndexPath(row: 0, section: 0)) {
        guard colors.indices.contains(indexPath.row) else {
            return
        }
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: .centeredHorizontally)
        collectionView(collectionView, didSelectItemAt: indexPath)
    }

    private func setupCollectionView() {
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

// MARK: Collection View Delegate

extension RingLightColorSelectionView: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard colors.indices.contains(indexPath.row),
            let cell = collectionView.cellForItem(at: indexPath) as? RingLightColorSelectionViewCell
        else {
            return
        }

        cell.highlight()

        delegate?.ringLightColorSelectionView(self, selectedColor: colors[indexPath.row])
    }

    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? RingLightColorSelectionViewCell else {
            return
        }

        cell.unhighlight()
    }
}

// MARK: Collection View Data Source

extension RingLightColorSelectionView: UICollectionViewDataSource {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        colors.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        let cell =
            collectionView.dequeueReusableCell(
                withReuseIdentifier: RingLightColorSelectionViewCell.reuseIdentifer, for: indexPath
            )
            as! RingLightColorSelectionViewCell

        guard colors.indices.contains(indexPath.row) else {
            return cell
        }

        cell.setColor(colors[indexPath.row])

        return cell
    }
}
