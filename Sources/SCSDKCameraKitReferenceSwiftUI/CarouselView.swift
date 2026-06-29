//  Copyright Snap Inc. All rights reserved.

import SCSDKCameraKit
import SCSDKCameraKitReferenceUI
import SwiftUI

/// SwiftUI wrapper for the reference UI carousel view.
public struct CarouselView: UIViewRepresentable {
    /// The lenses that should be visible in the carousel
    @Binding var availableLenses: [Lens]

    /// The currently selected lens, if one is selected.
    @Binding var selectedLens: Lens?

    let orientation: SCSDKCameraKitReferenceUI.CarouselView.Orientation

    public init(
        availableLenses: Binding<[Lens]>,
        selectedLens: Binding<Lens?>,
        orientation: SCSDKCameraKitReferenceUI.CarouselView.Orientation = .horizontal
    ) {
        self._availableLenses = availableLenses
        self._selectedLens = selectedLens
        self.orientation = orientation
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> SCSDKCameraKitReferenceUI.CarouselView {
        let inner = SCSDKCameraKitReferenceUI.CarouselView()
        inner.orientation = orientation
        inner.delegate = context.coordinator
        inner.dataSource = context.coordinator
        return inner
    }

    public func updateUIView(_ uiView: SCSDKCameraKitReferenceUI.CarouselView, context: Context) {
        context.coordinator.parent = self
        uiView.orientation = orientation
        let item = context.coordinator.item(for: selectedLens)
        if context.coordinator.availableLenses.map(\.id) != availableLenses.map(\.id) {
            context.coordinator.availableLenses = availableLenses
            uiView.reloadData()
        }
        if uiView.selectedItem != item {
            uiView.selectItem(item)
        }
    }
}

public extension CarouselView {
    class Coordinator: NSObject, CarouselViewDelegate, CarouselViewDataSource {
        var parent: CarouselView
        var availableLenses: [Lens] = []

        init(_ parent: CarouselView) {
            self.parent = parent
        }

        // MARK: CarouselViewDelegate

        public func carouselView(
            _ view: SCSDKCameraKitReferenceUI.CarouselView, didSelect item: CarouselItem, at index: Int
        ) {
            let lensIndex = index - 1
            if lensIndex >= 0, lensIndex < availableLenses.count {
                parent.selectedLens = availableLenses[lensIndex]
            } else {
                parent.selectedLens = nil
            }
        }

        // MARK: CarouselViewDataSource

        public func itemsForCarouselView(_ view: SCSDKCameraKitReferenceUI.CarouselView) -> [CarouselItem] {
            [EmptyItem()]
                + availableLenses.map {
                    item(for: $0)
                }
        }

        public func item(for lens: Lens?) -> CarouselItem {
            guard let lens else { return EmptyItem() }
            return CarouselItem(lensId: lens.id, groupId: lens.groupId, imageUrl: lens.iconUrl)
        }
    }
}
