import SCSDKCameraKit
import UIKit

public enum LensLayerContextMenu {
    public static func make(
        for lens: Lens,
        controller: CameraController,
        supplemental: UIMenu?
    ) -> UIMenu? {
        let current = controller.currentLens.map {
            $0.id == lens.id && $0.groupId == lens.groupId
        } ?? false
        let elements = makeElements(
            isCurrent: current,
            isPinnedBase: controller.isPinnedBase(lens),
            hasPinnedBase: controller.pinnedBaseLens != nil,
            pin: { [weak controller] in
                controller?.pinCurrentLensAsBase()
            },
            unpin: { [weak controller] in
                controller?.unpinBaseLens()
            },
            supplemental: supplemental
        )
        return elements.isEmpty ? nil : UIMenu(children: elements)
    }

    static func makeElements(
        isCurrent: Bool,
        isPinnedBase: Bool,
        hasPinnedBase: Bool = false,
        pin: @escaping () -> Void,
        unpin: @escaping () -> Void,
        supplemental: UIMenu?
    ) -> [UIMenuElement] {
        var elements: [UIMenuElement] = []
        if isPinnedBase {
            elements.append(
                UIAction(title: "Unpin Base Layer", image: UIImage(systemName: "pin.slash")) { _ in
                    unpin()
                }
            )
        } else if isCurrent, !hasPinnedBase {
            elements.append(
                UIAction(title: "Pin as Base Layer", image: UIImage(systemName: "pin")) { _ in
                    pin()
                }
            )
        }

        if let supplemental {
            if supplemental.title.isEmpty {
                elements.append(contentsOf: supplemental.children)
            } else {
                elements.append(supplemental)
            }
        }
        return elements
    }
}
