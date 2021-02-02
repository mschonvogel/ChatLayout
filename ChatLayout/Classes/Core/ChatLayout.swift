//
// ChatLayout
// ChatLayout.swift
// https://github.com/ekazaev/ChatLayout
//
// Created by Eugene Kazaev in 2020-2021.
// Distributed under the MIT license.
//

import Foundation
import UIKit

/// A collection view layout that can display items in a grid similar to `UITableView` but aligning them
/// to the leading or trailing edge of the `UICollectionView`. Helps to maintain chat like behavior by keeping
/// content offset from the bottom constant. Can deal with autosizing cells and supplementary views.
/// ### Custom Properties:
/// `ChatLayout.delegate`
///
/// `ChatLayout.settings`
///
/// `ChatLayout.keepContentOffsetAtBottomOnBatchUpdates`
///
/// `ChatLayout.visibleBounds`
///
/// `ChatLayout.layoutFrame`
///
/// ### Custom Methods:
/// `ChatLayout.getContentOffsetSnapshot(...)`
///
/// `ChatLayout.restoreContentOffset(...)`
public final class ChatLayout: UICollectionViewLayout {

    // MARK: Custom Properties

    /// `ChatLayout` delegate.
    public weak var delegate: ChatLayoutDelegate?

    /// Additional settings for `ChatLayout`.
    public var settings = ChatLayoutSettings() {
        didSet {
            guard collectionView != nil else {
                return
            }
            invalidateLayout()
        }
    }

    /// Default `UIScrollView` behaviour is to keep content offset constant from the top edge. If this flag is set to `true`
    /// `ChatLayout` should try to compensate batch update changes to keep the current content at the bottom of the visible
    /// part of `UICollectionView`.
    ///
    /// **NB:**
    /// Keep in mind that if during the batch content inset changes also (e.g. keyboard frame changes), `ChatLayout` will usually get that information after
    /// the animation starts and wont be able to compensate that change too. It should be done manually.
    public var keepContentOffsetAtBottomOnBatchUpdates: Bool = false

    /// Represent the currently visible rectangle.
    public var visibleBounds: CGRect {
        guard let collectionView = collectionView else {
            return .zero
        }
        return CGRect(x: adjustedContentInset.left,
                      y: collectionView.contentOffset.y + adjustedContentInset.top,
                      width: collectionView.bounds.width - adjustedContentInset.left - adjustedContentInset.right,
                      height: collectionView.bounds.height - adjustedContentInset.top - adjustedContentInset.bottom)
    }

    /// Represent the rectangle where all the items are aligned.
    public var layoutFrame: CGRect {
        guard let collectionView = collectionView else {
            return .zero
        }
        return CGRect(x: adjustedContentInset.left + settings.additionalInsets.left,
                      y: adjustedContentInset.top + settings.additionalInsets.top,
                      width: collectionView.bounds.width - settings.additionalInsets.left - settings.additionalInsets.right - adjustedContentInset.left - adjustedContentInset.right,
                      height: controller.contentHeight(at: state) - settings.additionalInsets.top - settings.additionalInsets.bottom - adjustedContentInset.top - adjustedContentInset.bottom)
    }

    // MARK: Inherited Properties

    /// The direction of the language you used when designing `ChatLayout` layout.
    public override var developmentLayoutDirection: UIUserInterfaceLayoutDirection {
        return .leftToRight
    }

    /// A Boolean value that indicates whether the horizontal coordinate system is automatically flipped at appropriate times.
    public override var flipsHorizontallyInOppositeLayoutDirection: Bool {
        return _flipsHorizontallyInOppositeLayoutDirection
    }

    /// Custom layoutAttributesClass is `ChatLayoutAttributes`.
    public override class var layoutAttributesClass: AnyClass {
        return ChatLayoutAttributes.self
    }

    /// Custom invalidationContextClass is `ChatLayoutInvalidationContext`.
    public override class var invalidationContextClass: AnyClass {
        return ChatLayoutInvalidationContext.self
    }

    /// The width and height of the collection view’s contents.
    public override var collectionViewContentSize: CGSize {
        let contentSize = controller.contentSize(for: .beforeUpdate)
        return contentSize
    }

    // MARK: Internal Properties

    var adjustedContentInset: UIEdgeInsets {
        guard let collectionView = collectionView else {
            return .zero
        }
        return collectionView.adjustedContentInset
    }

    var viewSize: CGSize {
        guard let collectionView = collectionView else {
            return .zero
        }
        return collectionView.frame.size
    }

    // MARK: Private Properties

    private struct PrepareActions: OptionSet {

        let rawValue: UInt

        static let recreateSectionModels = PrepareActions(rawValue: 1 << 0)
        static let updateLayoutMetrics = PrepareActions(rawValue: 1 << 1)
        static let cachePreviousWidth = PrepareActions(rawValue: 1 << 2)
        static let cachePreviousContentInsets = PrepareActions(rawValue: 1 << 3)
        static let switchStates = PrepareActions(rawValue: 1 << 4)

    }

    private struct InvalidationActions: OptionSet {

        let rawValue: UInt

        static let shouldInvalidateOnBoundsChange = InvalidationActions(rawValue: 1 << 0)

    }

    private lazy var controller = StateController(layoutRepresentation: self)

    private var state: ModelState = .beforeUpdate

    private var prepareActions: PrepareActions = []

    private var invalidationActions: InvalidationActions = []

    private var cachedCollectionViewSize: CGSize?

    private var cachedCollectionViewInset: UIEdgeInsets?

    // These properties are used to keep the layout attributes copies used for insert/delete
    // animations up-to-date as items are self-sized. If we don't keep these copies up-to-date, then
    // animations will start from the estimated height.
    private var attributesForPendingAnimations = [ItemKind: [ItemPath: ChatLayoutAttributes]]()

    private var invalidatedAttributes = [ItemKind: Set<ItemPath>]()

    private var dontReturnAttributes: Bool = true

    private var currentPositionSnapshot: ChatLayoutPositionSnapshot?

    private let _flipsHorizontallyInOppositeLayoutDirection: Bool

    // MARK: Constructors

    /// - Parameters:
    ///   - flipsHorizontallyInOppositeLayoutDirection: Indicates whether the horizontal coordinate
    ///     system is automatically flipped at appropriate times. In practice, this is used to support
    ///     right-to-left layout.
    public init(flipsHorizontallyInOppositeLayoutDirection: Bool = true) {
        self._flipsHorizontallyInOppositeLayoutDirection = flipsHorizontallyInOppositeLayoutDirection
        super.init()
        resetAttributesForPendingAnimations()
        resetInvalidatedAttributes()
    }

    required init?(coder aDecoder: NSCoder) {
        self._flipsHorizontallyInOppositeLayoutDirection = true
        super.init(coder: aDecoder)
        resetAttributesForPendingAnimations()
        resetInvalidatedAttributes()
    }

    // MARK: Custom Methods

    /// Get current offset of the item closest to the provided edge.
    /// - Parameter edge: The edge of the `UICollectionView`
    /// - Returns: `ChatLayoutPositionSnapshot`
    public func getContentOffsetSnapshot(from edge: ChatLayoutPositionSnapshot.Edge) -> ChatLayoutPositionSnapshot? {
        guard let collectionView = collectionView else {
            return nil
        }
        let insets = UIEdgeInsets(top: -collectionView.frame.height,
                                  left: 0,
                                  bottom: -collectionView.frame.height,
                                  right: 0)
        let layoutAttributes = controller.layoutAttributesForElements(in: visibleBounds.inset(by: insets),
                                                                      state: state,
                                                                      ignoreCache: true)
            .sorted(by: { $0.frame.maxY < $1.frame.maxY })

        switch edge {
        case .top:
            guard let firstVisibleItemAttributes = layoutAttributes.first(where: { $0.frame.minY >= visibleBounds.higherPoint.y }) else {
                return nil
            }
            let visibleBoundsTopOffset = firstVisibleItemAttributes.frame.minY - visibleBounds.higherPoint.y - settings.additionalInsets.top
            return ChatLayoutPositionSnapshot(indexPath: firstVisibleItemAttributes.indexPath, kind: firstVisibleItemAttributes.kind, edge: .top, offset: visibleBoundsTopOffset)
        case .bottom:
            guard let lastVisibleItemAttributes = layoutAttributes.last(where: { $0.frame.minY <= visibleBounds.lowerPoint.y }) else {
                return nil
            }
            let visibleBoundsBottomOffset = visibleBounds.lowerPoint.y - lastVisibleItemAttributes.frame.maxY - settings.additionalInsets.bottom
            return ChatLayoutPositionSnapshot(indexPath: lastVisibleItemAttributes.indexPath, kind: lastVisibleItemAttributes.kind, edge: .bottom, offset: visibleBoundsBottomOffset)
        }
    }

    /// Invalidates layout of the `UICollectionView` and trying to keep the offset of the item provided in `ChatLayoutPositionSnapshot`
    /// - Parameter snapshot: `ChatLayoutPositionSnapshot`
    public func restoreContentOffset(with snapshot: ChatLayoutPositionSnapshot) {
        collectionView?.setNeedsLayout()
        collectionView?.layoutIfNeeded()
        currentPositionSnapshot = snapshot
        let context = ChatLayoutInvalidationContext()
        context.invalidateLayoutMetrics = false
        invalidateLayout(with: context)
        collectionView?.setNeedsLayout()
        collectionView?.layoutIfNeeded()
        currentPositionSnapshot = nil
    }

    // MARK: Providing Layout Attributes

    /// Tells the layout object to update the current layout.
    public override func prepare() {
        super.prepare()

        guard let collectionView = collectionView,
            !prepareActions.isEmpty else {
            return
        }

        if collectionView.isPrefetchingEnabled {
            preconditionFailure("UICollectionView with prefetching enabled is not supported due to https://openradar.appspot.com/40926834 bug.")
        }

        if prepareActions.contains(.switchStates) {
            controller.commitUpdates()
            state = .beforeUpdate
            resetAttributesForPendingAnimations()
            resetInvalidatedAttributes()
        }

        if prepareActions.contains(.recreateSectionModels) {
            var sections: [SectionModel] = []
            for sectionIndex in 0..<collectionView.numberOfSections {
                // Header
                let header: ItemModel?
                if delegate?.shouldPresentHeader(self, at: sectionIndex) == true {
                    let headerPath = ItemPath(item: 0, section: sectionIndex)
                    header = ItemModel(with: configuration(for: .header, at: headerPath))
                } else {
                    header = nil
                }

                // Items
                var items: [ItemModel] = []
                for itemIndex in 0..<collectionView.numberOfItems(inSection: sectionIndex) {
                    let itemPath = ItemPath(item: itemIndex, section: sectionIndex)
                    items.append(ItemModel(with: configuration(for: .cell, at: itemPath)))
                }

                // Footer
                let footer: ItemModel?
                if delegate?.shouldPresentFooter(self, at: sectionIndex) == true {
                    let footerPath = ItemPath(item: 0, section: sectionIndex)
                    footer = ItemModel(with: configuration(for: .footer, at: footerPath))
                } else {
                    footer = nil
                }
                var section = SectionModel(header: header, footer: footer, items: items, collectionLayout: self)
                section.assembleLayout()
                sections.append(section)
            }
            controller.set(sections, at: .beforeUpdate)
        }

        if prepareActions.contains(.updateLayoutMetrics),
            !prepareActions.contains(.recreateSectionModels) {

            var sections: [SectionModel] = []
            sections.reserveCapacity(controller.numberOfSections(at: state))
            for sectionIndex in 0..<controller.numberOfSections(at: state) {
                var section = controller.section(at: sectionIndex, at: state)

                // Header
                if delegate?.shouldPresentHeader(self, at: sectionIndex) == true {
                    var header = section.header
                    header?.resetSize()
                    section.set(header: header)
                } else {
                    section.set(header: nil)
                }

                // Items
                var items: [ItemModel] = []
                items.reserveCapacity(section.items.count)
                for rowIndex in 0..<section.items.count {
                    var item = section.items[rowIndex]
                    item.resetSize()
                    items.append(item)
                }
                section.set(items: items)

                // Footer
                if delegate?.shouldPresentFooter(self, at: sectionIndex) == true {
                    var footer = section.footer
                    footer?.resetSize()
                    section.set(footer: footer)
                } else {
                    section.set(footer: nil)
                }

                section.assembleLayout()
                sections.append(section)
            }
            controller.set(sections, at: state)
        }

        if prepareActions.contains(.cachePreviousContentInsets) {
            cachedCollectionViewInset = adjustedContentInset
        }

        if prepareActions.contains(.cachePreviousWidth) {
            cachedCollectionViewSize = collectionView.bounds.size
        }

        prepareActions = []
    }

    /// Retrieves the layout attributes for all of the cells and views in the specified rectangle.
    public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        // This early return prevents an issue that causes overlapping / misplaced elements after an
        // off-screen batch update occurs. The root cause of this issue is that `UICollectionView`
        // expects `layoutAttributesForElementsInRect:` to return post-batch-update layout attributes
        // immediately after an update is sent to the collection view via the insert/delete/reload/move
        // functions. Unfortunately, this is impossible - when batch updates occur, `invalidateLayout:`
        // is invoked immediately with a context that has `invalidateDataSourceCounts` set to `true`.
        // At this time, `ChatLayout` has no way of knowing the details of this data source count
        // change (where the insert/delete/move took place). `ChatLayout` only gets this additional
        // information once `prepareForCollectionViewUpdates:` is invoked. At that time, we're able to
        // update our layout's source of truth, the `StateController`, which allows us to resolve the
        // post-batch-update layout and return post-batch-update layout attributes from this function.
        // Between the time that `invalidateLayout:` is invoked with `invalidateDataSourceCounts` set to
        // `true`, and when `prepareForCollectionViewUpdates:` is invoked with details of the updates,
        // `layoutAttributesForElementsInRect:` is invoked with the expectation that we already have a
        // fully resolved layout. If we return incorrect layout attributes at that time, then we'll have
        // overlapping elements / visual defects. To prevent this, we can return `nil` in this
        // situation, which works around the bug.
        // `UICollectionViewCompositionalLayout`, in classic UIKit fashion, avoids this bug / feature by
        // implementing the private function
        // `_prepareForCollectionViewUpdates:withDataSourceTranslator:`, which provides the layout with
        // details about the updates to the collection view before `layoutAttributesForElementsInRect:`
        // is invoked, enabling them to resolve their layout in time.
        guard !dontReturnAttributes else {
            return nil
        }

        let visibleAttributes = controller.layoutAttributesForElements(in: rect, state: state)
        return visibleAttributes
    }

    /// Retrieves layout information for an item at the specified index path with a corresponding cell.
    public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard !dontReturnAttributes else {
            return nil
        }
        let attributes = controller.itemAttributes(for: indexPath.itemPath, kind: .cell, at: state)

        return attributes
    }

    /// Retrieves the layout attributes for the specified supplementary view.
    public override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard !dontReturnAttributes else {
            return nil
        }

        let kind = ItemKind(elementKind)
        let attributes = controller.itemAttributes(for: indexPath.itemPath, kind: kind, at: state)

        return attributes
    }

    // MARK: Coordinating Animated Changes

    /// Prepares the layout object for animated changes to the view’s bounds or the insertion or deletion of items.
    public override func prepare(forAnimatedBoundsChange oldBounds: CGRect) {
        controller.isAnimatedBoundsChange = true
        controller.process(updateItems: [])
        state = .afterUpdate
        prepareActions.remove(.switchStates)
        guard let collectionView = collectionView,
            oldBounds.width != collectionView.bounds.width,
            keepContentOffsetAtBottomOnBatchUpdates,
            controller.isLayoutBiggerThanVisibleBounds(at: state) else {
            return
        }
        let newBounds = collectionView.bounds
        let heightDifference = oldBounds.height - newBounds.height
        controller.proposedCompensatingOffset += heightDifference + (oldBounds.origin.y - newBounds.origin.y)
    }

    /// Cleans up after any animated changes to the view’s bounds or after the insertion or deletion of items.
    public override func finalizeAnimatedBoundsChange() {
        if controller.isAnimatedBoundsChange {
            controller.isAnimatedBoundsChange = false
            controller.proposedCompensatingOffset = 0
            controller.batchUpdateCompensatingOffset = 0
            controller.commitUpdates()
            state = .beforeUpdate
            resetAttributesForPendingAnimations()
            resetInvalidatedAttributes()
        }
    }

    // MARK: Context Invalidation

    /// Asks the layout object if changes to a self-sizing cell require a layout update.
    public override func shouldInvalidateLayout(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> Bool {
        let preferredAttributesItemPath = preferredAttributes.indexPath.itemPath
        guard let preferredMessageAttributes = preferredAttributes as? ChatLayoutAttributes,
            let item = controller.item(for: preferredAttributesItemPath, kind: preferredMessageAttributes.kind, at: state) else {
            return true
        }
        var shouldInvalidateLayout: Bool
        shouldInvalidateLayout = item.calculatedSize == nil

        if item.alignment != preferredMessageAttributes.alignment {
            controller.update(alignment: preferredMessageAttributes.alignment, for: preferredAttributesItemPath, kind: preferredMessageAttributes.kind, at: state)
            shouldInvalidateLayout = true
        }

        return shouldInvalidateLayout
    }

    /// Retrieves a context object that identifies the portions of the layout that should change in response to dynamic cell changes.
    public override func invalidationContext(forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutInvalidationContext {
        guard let preferredMessageAttributes = preferredAttributes as? ChatLayoutAttributes else {
            return super.invalidationContext(forPreferredLayoutAttributes: preferredAttributes, withOriginalAttributes: originalAttributes)
        }

        let preferredAttributesItemPath = preferredMessageAttributes.indexPath.itemPath

        if state == .afterUpdate {
            invalidatedAttributes[preferredMessageAttributes.kind]?.insert(preferredAttributesItemPath)
        }

        let layoutAttributesForPendingAnimation = attributesForPendingAnimations[preferredMessageAttributes.kind]?[preferredAttributesItemPath]

        let newItemSize = itemSize(with: preferredMessageAttributes)

        controller.update(preferredSize: newItemSize, for: preferredAttributesItemPath, kind: preferredMessageAttributes.kind, at: state)
        controller.update(alignment: preferredMessageAttributes.alignment, for: preferredAttributesItemPath, kind: preferredMessageAttributes.kind, at: state)

        let context = super.invalidationContext(forPreferredLayoutAttributes: preferredMessageAttributes, withOriginalAttributes: originalAttributes) as! ChatLayoutInvalidationContext

        let heightDifference = newItemSize.height - originalAttributes.size.height
        let isAboveBottomEdge = originalAttributes.frame.minY.rounded() <= visibleBounds.maxY.rounded()

        if heightDifference != 0,
            (keepContentOffsetAtBottomOnBatchUpdates && controller.contentHeight(at: state).rounded() + heightDifference > visibleBounds.height.rounded())
            || isUserInitiatedScrolling,
            isAboveBottomEdge {
            context.contentOffsetAdjustment.y += heightDifference
            invalidationActions.formUnion([.shouldInvalidateOnBoundsChange])
        }

        if let attributes = controller.itemAttributes(for: preferredAttributesItemPath, kind: preferredMessageAttributes.kind, at: state)?.typedCopy() {
            controller.totalProposedCompensatingOffset += heightDifference
            layoutAttributesForPendingAnimation?.frame = attributes.frame
            if keepContentOffsetAtBottomOnBatchUpdates {
                controller.offsetByTotalCompensation(attributes: layoutAttributesForPendingAnimation, for: state, backward: true)
            }
            if state == .afterUpdate,
                controller.insertedIndexes.contains(preferredMessageAttributes.indexPath) || controller.insertedSectionsIndexes.contains(preferredMessageAttributes.indexPath.section) {
                layoutAttributesForPendingAnimation.map { attributes in
                    guard let delegate = delegate else {
                        attributes.alpha = 0
                        return
                    }
                    delegate.initialLayoutAttributesForInsertedItem(self, of: .cell, at: attributes.indexPath, modifying: attributes, on: .invalidation)
                }
            }
        } else {
            layoutAttributesForPendingAnimation?.frame.size = newItemSize
        }

        if #available(iOS 13.0, *) {
            switch preferredMessageAttributes.kind {
            case .cell:
                context.invalidateItems(at: [preferredMessageAttributes.indexPath])
            case .header, .footer:
                context.invalidateSupplementaryElements(ofKind: preferredMessageAttributes.kind.supplementaryElementStringType, at: [preferredMessageAttributes.indexPath])
            }
        }

        context.invalidateLayoutMetrics = false

        return context
    }

    /// Asks the layout object if the new bounds require a layout update.
    public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        let shouldInvalidateLayout = cachedCollectionViewSize != .some(newBounds.size) || cachedCollectionViewInset != .some(adjustedContentInset) || invalidationActions.contains(.shouldInvalidateOnBoundsChange)
        invalidationActions.remove(.shouldInvalidateOnBoundsChange)
        return shouldInvalidateLayout
    }

    /// Retrieves a context object that defines the portions of the layout that should change when a bounds change occurs.
    public override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let invalidationContext = super.invalidationContext(forBoundsChange: newBounds) as! ChatLayoutInvalidationContext
        invalidationContext.invalidateLayoutMetrics = false
        return invalidationContext
    }

    /// Invalidates the current layout using the information in the provided context object.
    public override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        guard let context = context as? ChatLayoutInvalidationContext else {
            assertionFailure("`context` must be an instance of `ChatLayoutInvalidationContext`")
            return
        }

        controller.resetCachedAttributes()

        dontReturnAttributes = context.invalidateDataSourceCounts && !context.invalidateEverything

        if context.invalidateEverything {
            prepareActions.formUnion([.recreateSectionModels])
        }

        // Checking `cachedCollectionViewWidth != collectionView?.bounds.size.width` is necessary
        // because the collection view's width can change without a `contentSizeAdjustment` occurring.
        if context.contentSizeAdjustment.width != 0 || cachedCollectionViewSize != collectionView?.bounds.size {
            prepareActions.formUnion([.cachePreviousWidth])
        }

        if cachedCollectionViewInset != adjustedContentInset {
            prepareActions.formUnion([.cachePreviousContentInsets])
        }

        if context.invalidateLayoutMetrics, !context.invalidateDataSourceCounts {
            prepareActions.formUnion([.updateLayoutMetrics])
        }

        if let currentPositionSnapshot = currentPositionSnapshot,
            let collectionView = collectionView {
            let contentHeight = controller.contentHeight(at: state)
            if let frame = controller.itemFrame(for: currentPositionSnapshot.indexPath.itemPath, kind: currentPositionSnapshot.kind, at: state, isFinal: true),
                contentHeight != 0,
                contentHeight > visibleBounds.size.height {
                switch currentPositionSnapshot.edge {
                case .top:
                    let desiredOffset = frame.minY - currentPositionSnapshot.offset - collectionView.adjustedContentInset.top - settings.additionalInsets.top
                    context.contentOffsetAdjustment.y = desiredOffset - collectionView.contentOffset.y
                case .bottom:
                    let maxAllowed = max(0, contentHeight - collectionView.frame.height + collectionView.adjustedContentInset.bottom)
                    let desiredOffset = max(min(maxAllowed, frame.maxY + currentPositionSnapshot.offset - collectionView.bounds.height + collectionView.adjustedContentInset.bottom + settings.additionalInsets.bottom), -collectionView.adjustedContentInset.top)
                    context.contentOffsetAdjustment.y = desiredOffset - collectionView.contentOffset.y
                }
            }
        }
        super.invalidateLayout(with: context)
    }

    /// Invalidates the current layout and triggers a layout update.
    public override func invalidateLayout() {
        super.invalidateLayout()
    }

    /// Retrieves the content offset to use after an animated layout update or change.
    public override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        if controller.proposedCompensatingOffset != 0,
            let collectionView = collectionView {
            let minPossibleContentOffset = -collectionView.adjustedContentInset.top
            let newProposedContentOffset = CGPoint(x: proposedContentOffset.x, y: max(minPossibleContentOffset, min(proposedContentOffset.y + controller.proposedCompensatingOffset, maxPossibleContentOffset.y)))
            controller.proposedCompensatingOffset = 0
            invalidationActions.formUnion([.shouldInvalidateOnBoundsChange])
            return newProposedContentOffset
        }
        return super.targetContentOffset(forProposedContentOffset: proposedContentOffset)
    }

    // MARK: Responding to Collection View Updates

    /// Notifies the layout object that the contents of the collection view are about to change.
    public override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        let updateItems = updateItems.sorted(by: { $0.indexPathAfterUpdate?.item ?? -1 < $1.indexPathAfterUpdate?.item ?? -1 })
        controller.process(updateItems: updateItems)
        state = .afterUpdate
        dontReturnAttributes = false
        super.prepare(forCollectionViewUpdates: updateItems)
    }

    /// Performs any additional animations or clean up needed during a collection view update.
    public override func finalizeCollectionViewUpdates() {
        controller.proposedCompensatingOffset = 0

        if keepContentOffsetAtBottomOnBatchUpdates,
            controller.isLayoutBiggerThanVisibleBounds(at: state),
            controller.batchUpdateCompensatingOffset != 0,
            let collectionView = collectionView {
            let compensatingOffset: CGFloat
            if controller.contentSize(for: .beforeUpdate).height > visibleBounds.size.height {
                compensatingOffset = controller.batchUpdateCompensatingOffset
            } else {
                compensatingOffset = maxPossibleContentOffset.y - collectionView.contentOffset.y
            }
            controller.batchUpdateCompensatingOffset = 0
            let context = ChatLayoutInvalidationContext()
            context.contentOffsetAdjustment.y = compensatingOffset
            context.contentSizeAdjustment.height = controller.contentSize(for: .afterUpdate).height - controller.contentSize(for: .beforeUpdate).height
            invalidateLayout(with: context)
        } else {
            controller.batchUpdateCompensatingOffset = 0
            let context = ChatLayoutInvalidationContext()
            invalidateLayout(with: context)
        }

        prepareActions.formUnion(.switchStates)

        super.finalizeCollectionViewUpdates()
    }

    // MARK: - Cell Appearance Animation

    /// Retrieves the starting layout information for an item being inserted into the collection view.
    public override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        var attributes: ChatLayoutAttributes?

        let itemPath = itemIndexPath.itemPath
        if state == .afterUpdate {
            if controller.insertedIndexes.contains(itemIndexPath) || controller.insertedSectionsIndexes.contains(itemPath.section) {
                attributes = controller.itemAttributes(for: itemPath, kind: .cell, at: .afterUpdate)?.typedCopy()
                controller.offsetByTotalCompensation(attributes: attributes, for: state, backward: true)
                attributes.map { attributes in
                    guard let delegate = delegate else {
                        attributes.alpha = 0
                        return
                    }
                    delegate.initialLayoutAttributesForInsertedItem(self, of: .cell, at: itemIndexPath, modifying: attributes, on: .initial)
                }
                attributesForPendingAnimations[.cell]?[itemPath] = attributes
            } else if let itemIdentifier = controller.itemIdentifier(for: itemPath, kind: .cell, at: .afterUpdate),
                let initialIndexPath = controller.itemPath(by: itemIdentifier, kind: .cell, at: .beforeUpdate) {
                attributes = controller.itemAttributes(for: initialIndexPath, kind: .cell, at: .beforeUpdate)?.typedCopy() ?? ChatLayoutAttributes(forCellWith: itemIndexPath)
                attributes?.indexPath = itemIndexPath
                if #available(iOS 13.0, *) {
                } else {
                    if controller.reloadedIndexes.contains(itemIndexPath) || controller.reloadedSectionsIndexes.contains(itemPath.section) {
                        // It is needed to position the new cell in the middle of the old cell on ios 12
                        attributesForPendingAnimations[.cell]?[itemPath] = attributes
                    }
                }
            } else {
                attributes = controller.itemAttributes(for: itemPath, kind: .cell, at: .beforeUpdate)
            }
        } else {
            attributes = controller.itemAttributes(for: itemPath, kind: .cell, at: .beforeUpdate)
        }

        return attributes
    }

    /// Retrieves the final layout information for an item that is about to be removed from the collection view.
    public override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        var attributes: ChatLayoutAttributes?

        let itemPath = itemIndexPath.itemPath
        if state == .afterUpdate {
            if controller.deletedIndexes.contains(itemIndexPath) || controller.deletedSectionsIndexes.contains(itemPath.section) {
                attributes = controller.itemAttributes(for: itemPath, kind: .cell, at: .beforeUpdate)?.typedCopy() ?? ChatLayoutAttributes(forCellWith: itemIndexPath)
                controller.offsetByTotalCompensation(attributes: attributes, for: state, backward: false)
                if keepContentOffsetAtBottomOnBatchUpdates,
                    controller.isLayoutBiggerThanVisibleBounds(at: state),
                    let attributes = attributes {
                    attributes.frame = attributes.frame.offsetBy(dx: 0, dy: attributes.frame.height / 2)
                }
                attributes.map { attributes in
                    guard let delegate = delegate else {
                        attributes.alpha = 0
                        return
                    }
                    delegate.finalLayoutAttributesForDeletedItem(self, of: .cell, at: itemIndexPath, modifying: attributes)
                }
            } else if let itemIdentifier = controller.itemIdentifier(for: itemPath, kind: .cell, at: .beforeUpdate),
                let finalIndexPath = controller.itemPath(by: itemIdentifier, kind: .cell, at: .afterUpdate) {
                if controller.movedIndexes.contains(itemIndexPath) || controller.movedSectionsIndexes.contains(itemPath.section) ||
                    controller.reloadedIndexes.contains(itemIndexPath) || controller.reloadedSectionsIndexes.contains(itemPath.section) {
                    attributes = controller.itemAttributes(for: finalIndexPath, kind: .cell, at: .afterUpdate)?.typedCopy()
                } else {
                    attributes = controller.itemAttributes(for: itemPath, kind: .cell, at: .beforeUpdate)?.typedCopy()
                }
                if invalidatedAttributes[.cell]?.contains(itemPath) ?? false {
                    attributes = nil
                }

                attributes?.indexPath = itemIndexPath
                attributesForPendingAnimations[.cell]?[itemPath] = attributes
                if controller.reloadedIndexes.contains(itemIndexPath) || controller.reloadedSectionsIndexes.contains(itemPath.section) {
                    attributes?.alpha = 0
                    attributes?.transform = CGAffineTransform(scaleX: 0, y: 0)
                }
            } else {
                attributes = controller.itemAttributes(for: itemPath, kind: .cell, at: .beforeUpdate)
            }
        } else {
            attributes = controller.itemAttributes(for: itemPath, kind: .cell, at: .beforeUpdate)
        }

        return attributes
    }

    // MARK: - Supplementary View Appearance Animation

    /// Retrieves the starting layout information for a supplementary view being inserted into the collection view.
    public override func initialLayoutAttributesForAppearingSupplementaryElement(ofKind elementKind: String, at elementIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        var attributes: ChatLayoutAttributes?

        let kind = ItemKind(elementKind)
        let elementPath = elementIndexPath.itemPath
        if state == .afterUpdate {
            if controller.insertedSectionsIndexes.contains(elementPath.section) {
                attributes = controller.itemAttributes(for: elementPath, kind: kind, at: .afterUpdate)?.typedCopy()
                controller.offsetByTotalCompensation(attributes: attributes, for: state, backward: true)
                attributes.map { attributes in
                    guard let delegate = delegate else {
                        attributes.alpha = 0
                        return
                    }
                    delegate.initialLayoutAttributesForInsertedItem(self, of: kind, at: elementIndexPath, modifying: attributes, on: .initial)
                }
                attributesForPendingAnimations[kind]?[elementPath] = attributes
            } else if let itemIdentifier = controller.itemIdentifier(for: elementPath, kind: kind, at: .afterUpdate),
                let initialIndexPath = controller.itemPath(by: itemIdentifier, kind: kind, at: .beforeUpdate) {
                attributes = controller.itemAttributes(for: initialIndexPath, kind: kind, at: .beforeUpdate)?.typedCopy() ?? ChatLayoutAttributes(forSupplementaryViewOfKind: elementKind, with: elementIndexPath)
                attributes?.indexPath = elementIndexPath

                if #available(iOS 13.0, *) {
                } else {
                    if controller.reloadedSectionsIndexes.contains(elementPath.section) {
                        // It is needed to position the new cell in the middle of the old cell on ios 12
                        attributesForPendingAnimations[kind]?[elementPath] = attributes
                    }
                }
            } else {
                attributes = controller.itemAttributes(for: elementPath, kind: kind, at: .beforeUpdate)
            }
        } else {
            attributes = controller.itemAttributes(for: elementPath, kind: kind, at: .beforeUpdate)
        }

        return attributes
    }

    /// Retrieves the final layout information for a supplementary view that is about to be removed from the collection view.
    public override func finalLayoutAttributesForDisappearingSupplementaryElement(ofKind elementKind: String, at elementIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        var attributes: ChatLayoutAttributes?

        let kind = ItemKind(elementKind)
        let elementPath = elementIndexPath.itemPath
        if state == .afterUpdate {
            if controller.deletedSectionsIndexes.contains(elementPath.section) {
                attributes = controller.itemAttributes(for: elementPath, kind: kind, at: .beforeUpdate)?.typedCopy() ?? ChatLayoutAttributes(forSupplementaryViewOfKind: elementKind, with: elementIndexPath)
                controller.offsetByTotalCompensation(attributes: attributes, for: state, backward: false)
                if keepContentOffsetAtBottomOnBatchUpdates,
                    controller.isLayoutBiggerThanVisibleBounds(at: state),
                    let attributes = attributes {
                    attributes.frame = attributes.frame.offsetBy(dx: 0, dy: attributes.frame.height / 2)
                }
                attributes.map { attributes in
                    guard let delegate = delegate else {
                        attributes.alpha = 0
                        return
                    }
                    delegate.finalLayoutAttributesForDeletedItem(self, of: kind, at: elementIndexPath, modifying: attributes)
                }
            } else if let itemIdentifier = controller.itemIdentifier(for: elementPath, kind: kind, at: .beforeUpdate),
                let finalIndexPath = controller.itemPath(by: itemIdentifier, kind: kind, at: .afterUpdate) {
                attributes = controller.itemAttributes(for: finalIndexPath, kind: kind, at: .afterUpdate)?.typedCopy() ?? ChatLayoutAttributes(forSupplementaryViewOfKind: elementKind, with: elementIndexPath)
                attributes?.indexPath = elementIndexPath
                attributesForPendingAnimations[kind]?[elementPath] = attributes
                if controller.reloadedSectionsIndexes.contains(elementPath.section) || finalIndexPath != elementPath {
                    attributes?.alpha = 0
                    attributes?.transform = CGAffineTransform(scaleX: 0, y: 0)
                }
            } else {
                attributes = controller.itemAttributes(for: elementPath, kind: kind, at: .beforeUpdate)
            }
        } else {
            attributes = controller.itemAttributes(for: elementPath, kind: kind, at: .beforeUpdate)
        }
        return attributes
    }

}

extension ChatLayout {

    func configuration(for element: ItemKind, at itemPath: ItemPath) -> ItemModel.Configuration {
        let indexPath = itemPath.indexPath
        let itemSize = estimatedSize(for: element, at: indexPath)
        return ItemModel.Configuration(alignment: alignment(for: element, at: indexPath), preferredSize: itemSize.estimated, calculatedSize: itemSize.exact)
    }

    private func estimatedSize(for element: ItemKind, at indexPath: IndexPath) -> (estimated: CGSize, exact: CGSize?) {
        guard let delegate = delegate else {
            return (estimated: estimatedItemSize, exact: nil)
        }

        let itemSize = delegate.sizeForItem(self, of: element, at: indexPath)

        switch itemSize {
        case .auto:
            return (estimated: estimatedItemSize, exact: nil)
        case let .estimated(size):
            return (estimated: size, exact: nil)
        case let .exact(size):
            return (estimated: size, exact: size)
        }
    }

    fileprivate func itemSize(with preferredAttributes: ChatLayoutAttributes) -> CGSize {
        let itemSize: CGSize
        if let delegate = delegate,
            case let .exact(size) = delegate.sizeForItem(self, of: preferredAttributes.kind, at: preferredAttributes.indexPath) {
            itemSize = size
        } else {
            itemSize = preferredAttributes.size
        }
        return itemSize
    }

    private func alignment(for element: ItemKind, at indexPath: IndexPath) -> ChatItemAlignment {
        guard let delegate = delegate else {
            return .fullWidth
        }
        return delegate.alignmentForItem(self, of: element, at: indexPath)
    }

    private var estimatedItemSize: CGSize {
        guard let estimatedItemSize = settings.estimatedItemSize else {
            guard collectionView != nil else {
                return .zero
            }
            return CGSize(width: layoutFrame.width, height: 40)
        }

        return estimatedItemSize
    }

    private func resetAttributesForPendingAnimations() {
        ItemKind.allCases.forEach {
            attributesForPendingAnimations[$0] = [:]
        }
    }

    private func resetInvalidatedAttributes() {
        ItemKind.allCases.forEach {
            invalidatedAttributes[$0] = []
        }
    }

}

extension ChatLayout: ChatLayoutRepresentation {

    func numberOfItems(in section: Int) -> Int {
        guard let collectionView = collectionView else {
            return .zero
        }
        return collectionView.numberOfItems(inSection: section)
    }

    func shouldPresentHeader(at sectionIndex: Int) -> Bool {
        return delegate?.shouldPresentHeader(self, at: sectionIndex) ?? false
    }

    func shouldPresentFooter(at sectionIndex: Int) -> Bool {
        return delegate?.shouldPresentFooter(self, at: sectionIndex) ?? false
    }

}

extension ChatLayout {

    private var maxPossibleContentOffset: CGPoint {
        guard let collectionView = collectionView else {
            return .zero
        }
        let maxContentOffset = max(0 - collectionView.adjustedContentInset.top, controller.contentHeight(at: state) - collectionView.frame.height + collectionView.adjustedContentInset.bottom)
        return CGPoint(x: 0, y: maxContentOffset)
    }

    private var isUserInitiatedScrolling: Bool {
        guard let collectionView = collectionView else {
            return false
        }
        return collectionView.isDragging || collectionView.isDecelerating
    }

}
