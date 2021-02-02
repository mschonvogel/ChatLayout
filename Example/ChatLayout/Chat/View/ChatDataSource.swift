//
//  ChatDataSource.swift
//  ChatLayout_Example
//
//  Created by Malte Schonvogel on 02.02.21.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import Foundation
import RxDataSources
import ChatLayout

class RxChatDataSource: RxCollectionViewSectionedAnimatedDataSource<Section>, UICollectionViewDelegate {

    init() {
        super.init { dataSource, collectionView, indexPath, item -> UICollectionViewCell in
            (dataSource as! RxChatDataSource).cell(collectionView, cellForItemAt: indexPath)
        }

        animationConfiguration = AnimationConfiguration(
            insertAnimation: .none,
            reloadAnimation: .none,
            deleteAnimation: .none
        )
        decideViewTransition = { _, collectionView, _ in
            let isInitialLoad = collectionView.numberOfSections > 0
                && collectionView.numberOfItems(inSection: 0) > 0
            return isInitialLoad ? .animated : .reload
        }
    }
}


extension RxChatDataSource {

    private func createTextCell(collectionView: UICollectionView, messageId: UUID, indexPath: IndexPath, text: String, alignment: ChatItemAlignment, user: User, bubbleType: Cell.BubbleType, status: MessageStatus, messageType: MessageType) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TextMessageCollectionCell.reuseIdentifier, for: indexPath) as! TextMessageCollectionCell
        setupMessageContainerView(cell.customView, messageId: messageId, alignment: alignment)
        setupCellLayoutView(cell.customView.customView, user: user, alignment: alignment, bubble: bubbleType, status: status)

        let bubbleView = cell.customView.customView.customView
        let controller = TextMessageController(text: text,
                                               type: messageType,
                                               bubbleController: buildTextBubbleController(bubbleView: bubbleView, messageType: messageType, bubbleType: bubbleType))
        bubbleView.customView.setup(with: controller)
        controller.view = bubbleView.customView
        cell.delegate = bubbleView.customView

        return cell
    }

    @available(iOS 13, *)
    private func createURLCell(collectionView: UICollectionView, messageId: UUID, indexPath: IndexPath, url: URL, alignment: ChatItemAlignment, user: User, bubbleType: Cell.BubbleType, status: MessageStatus, messageType: MessageType) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: URLCollectionCell.reuseIdentifier, for: indexPath) as! URLCollectionCell
        setupMessageContainerView(cell.customView, messageId: messageId, alignment: alignment)
        setupCellLayoutView(cell.customView.customView, user: user, alignment: alignment, bubble: bubbleType, status: status)

        let bubbleView = cell.customView.customView.customView
        let controller = URLController(url: url,
                                       messageId: messageId,
                                       bubbleController: buildDefaultBubbleController(for: bubbleView, messageType: messageType, bubbleType: bubbleType))

        bubbleView.customView.setup(with: controller)
        controller.view = bubbleView.customView
//        controller.delegate = reloadDelegate
        cell.delegate = bubbleView.customView

        return cell
    }

    private func createImageCell(collectionView: UICollectionView, messageId: UUID, indexPath: IndexPath, alignment: ChatItemAlignment, user: User, source: ImageMessageSource, bubbleType: Cell.BubbleType, status: MessageStatus, messageType: MessageType) -> ImageCollectionCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ImageCollectionCell.reuseIdentifier, for: indexPath) as! ImageCollectionCell

        setupMessageContainerView(cell.customView, messageId: messageId, alignment: alignment)
        setupCellLayoutView(cell.customView.customView, user: user, alignment: alignment, bubble: bubbleType, status: status)

        let bubbleView = cell.customView.customView.customView
        let controller = ImageController(source: source,
                                         messageId: messageId,
                                         bubbleController: buildDefaultBubbleController(for: bubbleView, messageType: messageType, bubbleType: bubbleType))

//        controller.delegate = reloadDelegate
        bubbleView.customView.setup(with: controller)
        controller.view = bubbleView.customView
        cell.delegate = bubbleView.customView

        return cell
    }

    private func createTypingIndicatorCell(collectionView: UICollectionView, indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TypingIndicatorCollectionCell.reuseIdentifier, for: indexPath) as! TypingIndicatorCollectionCell
        let alignment = ChatItemAlignment.leading
        cell.customView.alignment = alignment
        cell.customView.customView.alignment = .bottom
        let bubbleView = cell.customView.customView.customView
        let controller = TextMessageController(text: "Typing...",
                                               type: .incoming,
                                               bubbleController: buildTextBubbleController(bubbleView: bubbleView, messageType: .incoming, bubbleType: .tailed))
        bubbleView.customView.setup(with: controller)
        controller.view = bubbleView.customView
        cell.customView.accessoryView?.isHidden = true
        cell.delegate = bubbleView.customView

        return cell
    }

    private func createGroupTitle(collectionView: UICollectionView, indexPath: IndexPath, alignment: ChatItemAlignment, title: String) -> TitleCollectionCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TitleCollectionCell.reuseIdentifier, for: indexPath) as! TitleCollectionCell
        cell.customView.text = title
        cell.customView.preferredMaxLayoutWidth = (collectionView.collectionViewLayout as? ChatLayout)?.layoutFrame.width ?? collectionView.frame.width
        cell.customView.textColor = .gray
        cell.customView.numberOfLines = 0
        cell.customView.font = .preferredFont(forTextStyle: .caption2)
        cell.contentView.layoutMargins = UIEdgeInsets(top: 2, left: 40, bottom: 2, right: 40)
        return cell
    }

    private func createDateTitle(collectionView: UICollectionView, indexPath: IndexPath, alignment: ChatItemAlignment, title: String) -> TitleCollectionCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TitleCollectionCell.reuseIdentifier, for: indexPath) as! TitleCollectionCell
        cell.customView.preferredMaxLayoutWidth = (collectionView.collectionViewLayout as? ChatLayout)?.layoutFrame.width ?? collectionView.frame.width
        cell.customView.text = title
        cell.customView.textColor = .gray
        cell.customView.numberOfLines = 0
        cell.customView.font = .preferredFont(forTextStyle: .caption2)
        cell.contentView.layoutMargins = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        return cell
    }

    private func setupMessageContainerView<CustomView>(_ messageContainerView: MessageContainerView<EditingAccessoryView, CustomView>, messageId: UUID, alignment: ChatItemAlignment) {
        messageContainerView.alignment = alignment
        if let accessoryView = messageContainerView.accessoryView {
//            editNotifier.add(delegate: accessoryView)
            accessoryView.setIsEditing(false)

            let controller = EditingAccessoryController(messageId: messageId)
            controller.view = accessoryView
//            controller.delegate = editingDelegate
            accessoryView.setup(with: controller)
        }
    }

    private func setupCellLayoutView<CustomView>(_ cellView: CellLayoutContainerView<AvatarView, CustomView, StatusView>,
                                                 user: User,
                                                 alignment: ChatItemAlignment,
                                                 bubble: Cell.BubbleType,
                                                 status: MessageStatus) {
        cellView.alignment = .bottom
        cellView.leadingView?.isHidden = !alignment.isIncoming
        cellView.leadingView?.alpha = alignment.isIncoming ? 1 : 0
        cellView.trailingView?.isHidden = alignment.isIncoming
        cellView.trailingView?.alpha = alignment.isIncoming ? 0 : 1
        cellView.trailingView?.setup(with: status)

        if let avatarView = cellView.leadingView {
            let avatarViewController = AvatarViewController(user: user, bubble: bubble)
            avatarView.setup(with: avatarViewController)
            avatarViewController.view = avatarView
        }
    }

    private func buildTextBubbleController<CustomView>(bubbleView: ImageMaskedView<CustomView>, messageType: MessageType, bubbleType: Cell.BubbleType) -> BubbleController {
        let textBubbleController = TextBubbleController(bubbleView: bubbleView, type: messageType, bubbleType: bubbleType)
        let bubbleController = DefaultBubbleController(bubbleView: bubbleView, controllerProxy: textBubbleController, type: messageType, bubbleType: bubbleType)
        return bubbleController
    }

    private func buildDefaultBubbleController<CustomView>(for bubbleView: ImageMaskedView<CustomView>, messageType: MessageType, bubbleType: Cell.BubbleType) -> BubbleController {
        let contentBubbleController = FullCellContentBubbleController(bubbleView: bubbleView)
        let bubbleController = DefaultBubbleController(bubbleView: bubbleView, controllerProxy: contentBubbleController, type: messageType, bubbleType: bubbleType)
        return bubbleController
    }

}

extension RxChatDataSource {

    public func cell(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = self[indexPath]
        switch cell {
        case let .message(message, bubbleType: bubbleType):
            switch message.data {
            case let .text(text):
                let cell = createTextCell(collectionView: collectionView, messageId: message.id, indexPath: indexPath, text: text, alignment: cell.alignment, user: message.owner, bubbleType: bubbleType, status: message.status, messageType: message.type)
                return cell
            case let .url(url, isLocallyStored: _):
                if #available(iOS 13.0, *) {
                    return createURLCell(collectionView: collectionView, messageId: message.id, indexPath: indexPath, url: url, alignment: cell.alignment, user: message.owner, bubbleType: bubbleType, status: message.status, messageType: message.type)
                } else {
                    return createTextCell(collectionView: collectionView, messageId: message.id, indexPath: indexPath, text: url.absoluteString, alignment: cell.alignment, user: message.owner, bubbleType: bubbleType, status: message.status, messageType: message.type)
                }
            case let .image(source, isLocallyStored: _):
                let cell = createImageCell(collectionView: collectionView, messageId: message.id, indexPath: indexPath, alignment: cell.alignment, user: message.owner, source: source, bubbleType: bubbleType, status: message.status, messageType: message.type)
                return cell
            }
        case let .messageGroup(group):
            let cell = createGroupTitle(collectionView: collectionView, indexPath: indexPath, alignment: cell.alignment, title: group.title)
            return cell
        case let .date(group):
            let cell = createDateTitle(collectionView: collectionView, indexPath: indexPath, alignment: cell.alignment, title: group.value)
            return cell
        case .typingIndicator:
            return createTypingIndicatorCell(collectionView: collectionView, indexPath: indexPath)
        default:
            fatalError()
        }
    }
//
//    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
//        switch kind {
//        case UICollectionView.elementKindSectionHeader:
//            let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
//                                                                       withReuseIdentifier: TextTitleView.reuseIdentifier,
//                                                                       for: indexPath) as! TextTitleView
//            view.customView.text = sections[indexPath.section].title
//            view.customView.preferredMaxLayoutWidth = 300
//            view.customView.textColor = .lightGray
//            view.customView.numberOfLines = 0
//            view.customView.font = .preferredFont(forTextStyle: .caption2)
//            return view
//        case UICollectionView.elementKindSectionFooter:
//            let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
//                                                                       withReuseIdentifier: TextTitleView.reuseIdentifier,
//                                                                       for: indexPath) as! TextTitleView
//            view.customView.text = "Made with ChatLayout"
//            view.customView.preferredMaxLayoutWidth = 300
//            view.customView.textColor = .lightGray
//            view.customView.numberOfLines = 0
//            view.customView.font = .preferredFont(forTextStyle: .caption2)
//            return view
//        default:
//            fatalError()
//        }
//    }

}

extension RxChatDataSource: ChatLayoutDelegate {

    public func shouldPresentHeader(_ chatLayout: ChatLayout, at sectionIndex: Int) -> Bool {
        return false
    }

    public func shouldPresentFooter(_ chatLayout: ChatLayout, at sectionIndex: Int) -> Bool {
        return false
    }

    public func sizeForItem(_ chatLayout: ChatLayout, of kind: ItemKind, at indexPath: IndexPath) -> ItemSize {
        switch kind {
        case .cell:
            let item = self[indexPath]
            switch item {
            case let .message(message, bubbleType: _):
                switch message.data {
                case .text:
                    return .estimated(CGSize(width: chatLayout.layoutFrame.width, height: 36))
                case let .image(_, isLocallyStored: isDownloaded):
                    return .estimated(CGSize(width: chatLayout.layoutFrame.width, height: isDownloaded ? 120 : 80))
                case let .url(_, isLocallyStored: isDownloaded):
                    return .estimated(CGSize(width: chatLayout.layoutFrame.width, height: isDownloaded ? 60 : 36))
                }
            case .date:
                return .estimated(CGSize(width: chatLayout.layoutFrame.width, height: 18))
            case .typingIndicator:
                return .estimated(CGSize(width: 60, height: 36))
            case .messageGroup:
                return .estimated(CGSize(width: chatLayout.layoutFrame.width / 3, height: 18))
            case .deliveryStatus:
                return .estimated(CGSize(width: chatLayout.layoutFrame.width, height: 18))
            }
        case .footer, .header:
            return .auto
        }
    }

    public func alignmentForItem(_ chatLayout: ChatLayout, of kind: ItemKind, at indexPath: IndexPath) -> ChatItemAlignment {
        switch kind {
        case .header:
            return .center
        case .cell:
            let item = self[indexPath]
            switch item {
            case .date:
                return .center
            case .message, .deliveryStatus:
                return .fullWidth
            case .messageGroup, .typingIndicator:
                return .leading
            }
        case .footer:
            return .trailing
        }
    }
}
