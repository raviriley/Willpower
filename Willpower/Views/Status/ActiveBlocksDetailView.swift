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
        ActiveBlockCard(
            title: trigger.name,
            reason: .visitCountTrigger,
            domains: blockedDomains,
            expiresAt: firstBlock?.expiresAt,
            isLocked: firstBlock?.isLocked ?? false
        )
    }
}

// MARK: - Blocklist Block View

struct BlocklistBlockView: View {
    let block: ActiveBlock
    let blocklist: BlocklistConfig?

    var body: some View {
        ActiveBlockCard(
            title: blocklist?.name ?? "Unknown",
            reason: block.reason,
            domains: block.domains,
            expiresAt: block.expiresAt,
            isLocked: block.isLocked,
            isAllowList: block.mode == .allow
        )
    }
}

// MARK: - Active Block Card

struct ActiveBlockCard: View {
    let title: String
    let reason: ActiveBlock.BlockReason
    let domains: [String]
    let expiresAt: Date?
    let isLocked: Bool
    var isAllowList: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Title + Reason on left, Badge + Timer on right
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    if isAllowList {
                        StatusBadge(text: "ALLOW LIST", color: .green)
                    } else {
                        ReasonBadge(reason: reason)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let expiresAt {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TimeRemainingView(expiresAt: expiresAt)
                        }
                    } else {
                        Text("Indefinite")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    StatusBadge(
                        text: isLocked ? "LOCKED" : "ACTIVE",
                        color: isLocked ? .red : (isAllowList ? .green : .orange)
                    )
                }
            }

            // Divider
            Divider()
                .padding(.vertical, 10)

            // Domains list
            if isAllowList {
                Text("\(domains.count) domain\(domains.count == 1 ? "" : "s") allowed")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .padding(.bottom, 4)
            }
            DomainsListView(domains: domains)
        }
        .padding()
        .background {
            if isAllowList {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.05))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.background.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isAllowList ? Color.green.opacity(0.3) : .clear, lineWidth: 1)
        )
    }
}

// MARK: - Domains List View

struct DomainsListView: View {
    let domains: [String]

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading)
    ]

    var body: some View {
        if domains.count <= 4 {
            // Single column for few domains
            VStack(alignment: .leading, spacing: 6) {
                ForEach(domains, id: \.self) { domain in
                    DomainRow(domain: domain)
                }
            }
        } else {
            // Two-column grid for many domains
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(domains, id: \.self) { domain in
                    DomainRow(domain: domain)
                }
            }
        }
    }
}

struct DomainRow: View {
    let domain: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(domain)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.8))
        }
    }
}

// MARK: - Reason Badge

struct ReasonBadge: View {
    let reason: ActiveBlock.BlockReason

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: reason.iconName)
                .font(.caption)
            Text(reason.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(reason.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(reason.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - BlockReason Display Properties

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

    var iconName: String {
        switch self {
        case .manualActivation, .timeBasedTrigger:
            return "play.fill"
        case .scheduleBasedTrigger:
            return "calendar.badge.clock"
        case .visitCountTrigger:
            return "eye.trianglebadge.exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .manualActivation, .timeBasedTrigger:
            return .blue
        case .scheduleBasedTrigger:
            return .purple
        case .visitCountTrigger:
            return .orange.opacity(0.8)
        }
    }
}

#Preview {
    ActiveBlocksDetailView(viewModel: WillpowerViewModel())
}
