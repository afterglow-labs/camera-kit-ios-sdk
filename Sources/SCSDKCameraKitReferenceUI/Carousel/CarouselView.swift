//  Copyright Snap Inc. All rights reserved.
//  CameraKit

import UIKit

/// A set of functions implemented by the delegate to be notified when the carousel responds to user interactions.
public protocol CarouselViewDelegate: AnyObject {
    /// Notifies the delegate that a given carousel's specific index was selected.
    /// - Parameters:
    ///   - view: The carousel view which contains the item that was just selected.
    ///   - item: The carousel item which was just selected.
    ///   - index: The index at which the carousel item was selected.
    func carouselView(_ view: CarouselView, didSelect item: CarouselItem, at index: Int)
}

/// A set of functions that an object adopts to manage data and provide items for a carousel view.
public protocol CarouselViewDataSource: AnyObject {
    /// Returns a list of items to show in the carousel view.
    /// - Parameters:
    ///   - view: The carousel view which will show the list of items returned.
    /// - Returns: A list of items to show in the carousel view.
    func itemsForCarouselView(_ view: CarouselView) -> [CarouselItem]
}

/// A view that manages an ordered collection of data items (eg. lenses) and displays them in a swipeable row with one item always selected.
public class CarouselView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    /// The delegate for the carousel view which will be notified of the carousel view actions.
    public weak var delegate: CarouselViewDelegate?

    /// The object that manages data and provides items for the carousel view.
    public weak var dataSource: CarouselViewDataSource? {
        didSet {
            reloadData()
        }
    }

    /// Reloads all of the data in the carousel view to display the latest carousel items.
    public func reloadData() {
        items = dataSource?.itemsForCarouselView(self) ?? []
        collectionView.reloadData()
    }

    /// Current selected item or nil if none are selected (ie. when carousel is empty).
    public private(set) var selectedItem: CarouselItem = EmptyItem()

    /// Current list of items in the carousel.
    private var items = [CarouselItem]()

    /// list of items before hiding carousel to record.
    private var storedItems = [CarouselItem]()

    private var lastLaidOutBoundsSize: CGSize = .zero

    /// Image loader instance used to load each item icon.
    private let imageLoader = DefaultCarouselImageLoader()

    // MARK: Views

    /// Custom carousel collection view layout.
    private lazy var collectionViewLayout: CarouselCollectionViewLayout = {
        let layout = CarouselCollectionViewLayout()
        layout.delegate = self
        layout.dataSource = self
        layout.minimumInteritemSpacing = 8.0
        layout.minimumLineSpacing = 8.0
        layout.scrollDirection = .horizontal
        return layout
    }()

    /// Collection view which is the "carousel" itself.
    private lazy var collectionView: UICollectionView = {
        let view = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        view.accessibilityIdentifier = CarouselElements.collectionView.id
        view.contentInsetAdjustmentBehavior = .never
        view.delegate = self
        view.dataSource = self
        view.backgroundColor = .clear
        view.decelerationRate = .fast
        view.register(CarouselCollectionViewCell.self, forCellWithReuseIdentifier: Constants.cellIdentifier)
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    /// Ring imitating the camera button.
    /// Since the carousel is on top of the camera button, this is needed in order to make the carousel appear behind the camera button as before.
    private lazy var facadeSelectionRingView: UIView = {
        let view = UIView()
        view.layer.addSublayer(ringLayer)
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = CarouselElements.facadeSelectionRingView.id
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private let ringLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.white.cgColor
        layer.lineWidth = 6.0

        return layer
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
        setupFacadeSelectionRingView()
        setContentHuggingPriority(.required, for: .vertical)
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

    private func setupFacadeSelectionRingView() {
        addSubview(facadeSelectionRingView)
        NSLayoutConstraint.activate([
            facadeSelectionRingView.centerXAnchor.constraint(equalTo: centerXAnchor),
            facadeSelectionRingView.centerYAnchor.constraint(equalTo: centerYAnchor),
            facadeSelectionRingView.heightAnchor.constraint(equalTo: heightAnchor),
            facadeSelectionRingView.widthAnchor.constraint(equalTo: widthAnchor),
        ])
    }

    override public var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 62)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        guard bounds.size != lastLaidOutBoundsSize else { return }
        lastLaidOutBoundsSize = bounds.size

        // collection view padding is half of frame - half of item size (frame height)
        let padding = (frame.size.width / 2.0) - (frame.size.height / 2.0)
        collectionView.contentInset.left = padding
        collectionView.contentInset.right = padding

        let cameraRingX = frame.midX
        let cameraRingY = frame.size.height / 2.0
        let radius = CameraButton.Constants.ringSize / 2
        let path = UIBezierPath(
            arcCenter: CGPoint(x: cameraRingX, y: cameraRingY), radius: radius, startAngle: CGFloat.pi / -2.0,
            endAngle: 3 * CGFloat.pi / 2.0, clockwise: true
        )

        ringLayer.path = path.cgPath

        collectionViewLayout.itemSize = CGSize(width: frame.size.height, height: frame.size.height)
        collectionViewLayout.invalidateLayout()
        selectItem(selectedItem, animated: false)
    }

    // MARK: Items

    /// Select carousel item
    /// Returns true if item exists in carousel and is selected or false if failed to select item
    /// - Parameter selected: carousel item to select
    @discardableResult
    public func selectItem(_ selected: CarouselItem) -> Bool {
        selectItem(selected, animated: true)
    }

    @discardableResult
    private func selectItem(_ selected: CarouselItem, animated: Bool) -> Bool {
        if let index = items.firstIndex(where: { $0.id == selected.id }) {
            selectedItem = selected
            collectionView.scrollToItem(
                at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: animated
            )
            return true
        } else {
            selectedItem = EmptyItem()
            return false
        }
    }

    /// Hide lens carousel.
    /// Sets Items to selected item and saves list to show later.
    public func hideCarousel() {
        facadeSelectionRingView.isHidden = true
        storedItems = items
        items = [selectedItem]
        collectionView.reloadData()
    }

    /// Show lens carousel.
    /// Sets Items to previous stored item list and reloads collectionView.
    public func showCarousel() {
        facadeSelectionRingView.isHidden = false
        items = storedItems
        collectionView.reloadData()
        selectItem(selectedItem)
    }

    // MARK: Collection View

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        let cell =
            collectionView.dequeueReusableCell(withReuseIdentifier: Constants.cellIdentifier, for: indexPath)
                as! CarouselCollectionViewCell

        let item = items[indexPath.item]
        cell.imageView.image =
            item.image
                ?? UIImage(named: Constants.imagePlaceholder, in: BundleHelper.resourcesBundle, compatibleWith: nil)
        if item.image == nil, item.imageUrl != nil {
            cell.activityIndicatorView.startAnimating()
        } else {
            cell.activityIndicatorView.stopAnimating()
        }

        cell.contentView.alpha = 1.0
        cell.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)

        cell.accessibilityIdentifier = CarouselElements.lensCell.id
        cell.accessibilityLabel = item.lensId

        // handle initial state edge case issues
        // normal lens: don't transform initial state
        // empty lens: set alpha to 0
        if selectedItem.id == item.id {
            if item is EmptyItem {
                cell.contentView.alpha = 0.0
            } else {
                cell.transform = .identity
            }
        }

        return cell
    }

    public func collectionView(
        _ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        guard items[indexPath.item].image == nil else {
            return
        }

        fetchImage(indexPath: indexPath)
    }

    public func collectionView(
        _ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath
    ) {
        guard
            indexPath.item < items.count,
            let url = items[indexPath.item].imageUrl
        else { return }
        imageLoader.cancelImageLoad(from: url)
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        selectItemHelper(at: indexPath.item)
    }

    // MARK: Scroll View

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // add back scroll padding
        let offset = scrollView.contentOffset.x + scrollView.contentInset.left
        // total item size = item size + spacing
        let totalItemSize = collectionViewLayout.itemSize.height + collectionViewLayout.minimumInteritemSpacing

        // get indicies for closest two items
        let index = offset / totalItemSize
        let prev = floor(index)
        let next = ceil(index)

        updateCellItem(curr: prev, offset: offset, totalItemSize: totalItemSize)
        updateCellItem(curr: next, offset: offset, totalItemSize: totalItemSize)
    }

    private func updateCellItem(curr: CGFloat, offset: CGFloat, totalItemSize: CGFloat) {
        // calculate offsets
        let currOffset = curr * totalItemSize

        // calculate offset delta
        let delta = min(abs(currOffset - offset) / totalItemSize, 1.0)

        // cell transform and alpha
        var transform: CGFloat
        var alpha: CGFloat = 1.0

        // item index
        let currIndex = Int(curr)

        // check if items are empty items (as they are special/inverse cases)
        // normal: transform is max diff (in this case 0.20) multiplied by offset delta
        // empty: transform scale decreases as cell gets closer to center
        if currIndex >= 0, currIndex < items.count, items[currIndex] is EmptyItem {
            transform = 0.6 + delta * 0.20
            alpha = pow(delta, 7) * 1.0 // exponential alpha change
        } else {
            transform = 1.0 - (delta * 0.20)
        }

        // collection cell
        let cell = collectionView.cellForItem(at: IndexPath(item: Int(curr), section: 0))

        // transform items and update alpha
        cell?.transform = CGAffineTransform(scaleX: transform, y: transform)
        cell?.contentView.alpha = alpha
    }

    // MARK: Helper

    /// Helper method to fetch image for cell at index path and update cell on completion
    /// - Parameter indexPath: index path of cell
    private func fetchImage(indexPath: IndexPath) {
        guard let url = items[indexPath.item].imageUrl else { return }
        let id = items[indexPath.item].id

        imageLoader.loadImage(url: url) { [weak self] image, error in
            guard
                let strongSelf = self,
                indexPath.item < strongSelf.items.count,
                strongSelf.items[indexPath.item].id == id
            else {
                // ensure cell index path still exists after image finishes downloading
                // since carousel data can be reloaded in that time
                return
            }
            strongSelf.items[indexPath.item].image = image

            guard let cell = strongSelf.collectionView.cellForItem(at: indexPath) as? CarouselCollectionViewCell else {
                return
            }
            cell.imageView.image = image
            cell.activityIndicatorView.stopAnimating()
        }
    }

    /// Select item at index and notify delegate
    /// - Parameter index: index of item
    private func selectItemHelper(at index: Int) {
        guard
            index >= 0,
            index < items.count
        else {
            return
        }

        selectedItem = items[index]
        delegate?.carouselView(self, didSelect: items[index], at: index)
    }
}

// MARK: Collection View Layout

extension CarouselView: CarouselCollectionViewLayoutDelegate {
    public func carouselLayout(_ layout: CarouselCollectionViewLayout, willTargetIndex index: Int) {
        selectItemHelper(at: index)
    }
}

extension CarouselView: CarouselCollectionViewLayoutDataSource {
    public func carouselLayout(_ layout: CarouselCollectionViewLayout, transformForItemAt indexPath: IndexPath)
        -> CGAffineTransform
    {
        let item = items[indexPath.item]
        guard
            selectedItem.id == item.id,
            !(selectedItem is EmptyItem)
        else {
            return CGAffineTransform(scaleX: 0.8, y: 0.8)
        }

        return .identity
    }
}

// MARK: Constants

private extension CarouselView {
    enum Constants {
        static let cellIdentifier = "SCCameraKitCarouselCollectionViewCell"
        static let imagePlaceholder = "ck_lens_placeholder"
    }
}
