//
//  ActiveBlocksDetailView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct ActiveBlocksDetailView: View {
    var viewModel: WillpowerViewModel

    /// Groups visit-count trigger blocks by their parent trigger
    private var groupedTriggerBlocks: [(trigger: IndependentTrigger, blocks: [ActiveBlock])] {
        var result: [(trigger: IndependentTrigger, blocks: [ActiveBlock])] = []

        for trigger in viewModel.independentTriggers {
            let patternIds = Set(trigger.urlPatterns.map(\.id))
            let matchingBlocks = viewModel.activeBlocks.filter { block in
                block.reason == .visitCountTrigger && patternIds.contains(block.blocklistId)
            }
            if !matchingBlocks.isEmpty {
                result.append((trigger: trigger, blocks: matchingBlocks))
            }
        }
        return result
    }

    /// Blocks not associated with an independent trigger (blocklist-based blocks)
    private var blocklistBlocks: [ActiveBlock] {
        let triggerPatternIds = Set(viewModel.independentTriggers.flatMap { $0.urlPatterns.map(\.id) })
        return viewModel.activeBlocks.filter { block in
            block.reason != .visitCountTrigger || !triggerPatternIds.contains(block.blocklistId)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Trigger-based blocks (grouped by trigger)
                ForEach(groupedTriggerBlocks, id: \.trigger.id) { group in
                    TriggerBlockGroupView(
                        trigger: group.trigger,
                        blocks: group.blocks
                    )
                }

                // Blocklist-based blocks
                ForEach(blocklistBlocks) { block in
                    BlocklistBlockView(
                        block: block,
                        blocklist: viewModel.blocklists.first { $0.id == block.blocklistId }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Trigger Block Group View

struct TriggerBlockGroupView: View {
    let trigger: IndependentTrigger
    let blocks: [ActiveBlock]

    private var blockedDomains: [String] {
        blocks.flatMap(\.domains)
    }

    private var firstBlock: ActiveBlock? {
        blocks.first
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(trigger.name)
                    .font(.headline)

                ForEach(blockedDomains, id: \.self) { domain in
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(domain)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(ActiveBlock.BlockReason.visitCountTrigger.displayName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let block = firstBlock {
                    if let expiresAt = block.expiresAt {
                        HStack {
                            Text("Expires:")
                            TimeRemainingView(expiresAt: expiresAt)
                        }
                    }

                    if block.isLocked {
                        StatusBadge(text: "LOCKED", color: .red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Blocklist Block View

struct BlocklistBlockView: View {
    let block: ActiveBlock
    let blocklist: BlocklistConfig?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let blocklist {
                    Text(blocklist.name)
                        .font(.headline)
                }

                Text("\(block.domains.count) domains blocked")
                    .foregroundStyle(.secondary)

                Text(block.reason.displayName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let expiresAt = block.expiresAt {
                    HStack {
                        Text("Expires:")
                        TimeRemainingView(expiresAt: expiresAt)
                    }
                }

                if block.isLocked {
                    StatusBadge(text: "LOCKED", color: .red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - BlockReason Display Name

extension ActiveBlock.BlockReason {
    var displayName: String {
        switch self {
        case .manualActivation, .timeBasedTrigger:
            return "Manual activation"
        case .scheduleBasedTrigger:
            return "Scheduled"
        case .visitCountTrigger:
            return "Visit threshold exceeded"
        }
    }
}

#Preview {
    ActiveBlocksDetailView(viewModel: WillpowerViewModel())
}
