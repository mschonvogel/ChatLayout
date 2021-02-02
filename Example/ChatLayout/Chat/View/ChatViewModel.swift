//
//  ChatViewModel.swift
//  ChatLayout_Example
//
//  Created by Malte Schonvogel on 02.02.21.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import RxSwift
import RxCocoa
import RxDataSources
import RxSwiftExt

struct ChatViewModelInputs {
    let viewDidLoad = PublishSubject<Void>()
    let newMessage = PublishSubject<String>()
}

struct ChatViewModelOutputs {
    let sections: Driver<[Section]>
}

struct ChatViewModel {
    private let disposeBag = DisposeBag()
    let inputs = ChatViewModelInputs()
    let outputs: ChatViewModelOutputs

    init() {
        let messages = BehaviorSubject<[RawMessage]>(value: [])

        let provider = DefaultRandomDataProvider(receiverId: 0, usersIds: [1, 2, 3])

        Observable
            .merge(
                inputs.newMessage
                    .map {
                        [
                            RawMessage(
                                id: .init(),
                                date: Date(),
                                data: .text($0),
                                userId: 1,
                                status: .sent
                            )
                        ]
                    },
                Observable<Int>
                    .interval(.seconds(1), scheduler: MainScheduler.asyncInstance)
                    .map { _ in
                        provider.createBunchOfMessages(number: 1)
                    }
            )
            .withLatestFrom(
                messages,
                resultSelector: { $1 + $0 }
            )
            .bind(to: messages)
            .disposed(by: disposeBag)

        let sections = messages.map(transformSections)

        outputs = .init(
            sections: sections.asDriver(onErrorJustReturn: [])
        )
    }
}

extension Section: AnimatableSectionModelType {
    var items: [Cell] {
        cells
    }

    var identity: String {
        differenceIdentifier.description
    }

    typealias Item = Cell
    typealias Identity = String

    init(original: Section, items: [Cell]) {
        self.init(id: original.id, title: original.title, cells: items)
    }
}

extension Cell: IdentifiableType {
    typealias Identity = String
    var identity: String {
        self.differenceIdentifier.description
    }
}

func transformSections(messages: [RawMessage]) -> [Section] {
    var lastMessageStorage: Message?

    let messagesSplitByDay = messages
        .map { Message(id: $0.id,
                       date: $0.date,
                       data: convert($0.data),
                       owner: User(id: $0.userId),
                       type: $0.userId == 1 ? .outgoing : .incoming,
                       status: $0.status) }
        .reduce(into: [[Message]]()) { result, message in
            guard var section = result.last,
                  let prevMessage = section.last else {
                let section = [message]
                result.append(section)
                return
            }
            if Calendar.current.isDate(prevMessage.date, equalTo: message.date, toGranularity: .hour) {
                section.append(message)
                result[result.count - 1] = section
            } else {
                let section = [message]
                result.append(section)
            }
        }

    let cells = messagesSplitByDay.enumerated().map { index, messages -> [Cell] in
        var cells: [Cell] = Array(messages.enumerated().map { index, message -> [Cell] in
            let bubble: Cell.BubbleType
            if index < messages.count - 1 {
                let nextMessage = messages[index + 1]
                bubble = nextMessage.owner == message.owner ? .normal : .tailed
            } else {
                bubble = .tailed
            }
            guard message.type != .outgoing else {
                lastMessageStorage = message
                return [.message(message, bubbleType: bubble)]
            }

            let titleCell = Cell.messageGroup(MessageGroup(id: message.id, title: "\(message.owner.name)", type: message.type))

            if let lastMessage = lastMessageStorage {
                if lastMessage.owner != message.owner {
                    lastMessageStorage = message
                    return [titleCell, .message(message, bubbleType: bubble)]
                } else {
                    lastMessageStorage = message
                    return [.message(message, bubbleType: bubble)]
                }
            } else {
                lastMessageStorage = message
                return [titleCell, .message(message, bubbleType: bubble)]
            }
        }.joined())

        if let firstMessage = messages.first {
            let dateCell = Cell.date(DateGroup(id: firstMessage.id, date: firstMessage.date))
            cells.insert(dateCell, at: 0)
        }

//        if typingState == .typing,
//           index == messagesSplitByDay.count - 1 {
//            cells.append(.typingIndicator)
//        }

        return cells // Section(id: sectionTitle.hashValue, title: sectionTitle, cells: cells)
    }.joined()

    return [Section(id: 0, title: "Loading...", cells: Array(cells))]
}

private func convert(_ data: RawMessage.Data) -> Message.Data {
    switch data {
    case let .url(url):
        let isLocallyStored: Bool
        if #available(iOS 13, *) {
            isLocallyStored = metadataCache.isEntityCached(for: url)
        } else {
            isLocallyStored = true
        }
        return .url(url, isLocallyStored: isLocallyStored)
    case let .image(source):
        func isPresentLocally(_ source: ImageMessageSource) -> Bool {
            switch source {
            case .image:
                return true
            case let .imageURL(url):
                return imageCache.isEntityCached(for: CacheableImageKey(url: url))
            }
        }
        return .image(source, isLocallyStored: isPresentLocally(source))
    case let .text(text):
        return .text(text)
    }
}
