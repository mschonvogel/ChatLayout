//
// ChatLayout
// DefaultChatCollectionDataSource.swift
// https://github.com/ekazaev/ChatLayout
//
// Created by Eugene Kazaev in 2020-2021.
// Distributed under the MIT license.
//

import ChatLayout
import Foundation
import UIKit

typealias TextMessageCollectionCell = ContainerCollectionViewCell<MessageContainerView<EditingAccessoryView, CellLayoutContainerView<AvatarView, ImageMaskedView<TextMessageView>, StatusView>>>
@available(iOS 13, *)
typealias URLCollectionCell = ContainerCollectionViewCell<MessageContainerView<EditingAccessoryView, CellLayoutContainerView<AvatarView, ImageMaskedView<URLView>, StatusView>>>
typealias ImageCollectionCell = ContainerCollectionViewCell<MessageContainerView<EditingAccessoryView, CellLayoutContainerView<AvatarView, ImageMaskedView<ImageView>, StatusView>>>
typealias TitleCollectionCell = ContainerCollectionViewCell<UILabel>
typealias TypingIndicatorCollectionCell = ContainerCollectionViewCell<MessageContainerView<EditingAccessoryView, CellLayoutContainerView<AvatarPlaceholderView, ImageMaskedView<TextMessageView>, VoidViewFactory>>>

typealias TextTitleView = ContainerCollectionReusableView<UILabel>

//final class DefaultChatCollectionDataSource: NSObject, ChatCollectionDataSource {
//
//    private unowned var reloadDelegate: ReloadDelegate
//
//    private unowned var editingDelegate: EditingAccessoryControllerDelegate
//
//    private let editNotifier: EditNotifier
//
//    var sections: [Section] = [] {
//        didSet {
//            oldSections = oldValue
//        }
//    }
//
//    private var oldSections: [Section] = []
//
//    init(editNotifier: EditNotifier, reloadDelegate: ReloadDelegate, editingDelegate: EditingAccessoryControllerDelegate) {
//        self.reloadDelegate = reloadDelegate
//        self.editingDelegate = editingDelegate
//        self.editNotifier = editNotifier
//    }
//
//
//}
