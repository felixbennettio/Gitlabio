import SwiftUI
import GitLabCore

struct MergeRequestRow: View {
    let mr: MergeRequest
    var showProject = false
    @Environment(Session.self) private var session

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(mr.title).font(.body.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(showProject ? (mr.references?.full ?? mr.reference) : mr.reference)
                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    if mr.isDraft { Text("草稿").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1).background(.secondary.opacity(0.15), in: Capsule()) }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    BranchTag(name: mr.sourceBranch)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    BranchTag(name: mr.targetBranch)
                }
                LabelRow(labels: mr.labels ?? [])
                HStack(spacing: 12) {
                    Avatar(user: mr.author, instance: session.instance, size: 18)
                    if let date = mr.updatedAt { Meta(symbol: "clock", text: date.relative) }
                    if let notes = mr.userNotesCount, notes > 0 { Meta(symbol: "bubble.left", text: "\(notes)") }
                    if let reviewers = mr.reviewers, !reviewers.isEmpty {
                        Spacer(minLength: 0)
                        AvatarStack(users: reviewers, instance: session.instance, size: 18)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch mr.state {
        case "merged": return "arrow.triangle.merge"
        case "closed": return "xmark.circle"
        default: return mr.isDraft ? "pencil.circle" : "arrow.triangle.pull"
        }
    }

    private var color: Color {
        switch mr.state {
        case "merged": return Theme.merged
        case "closed": return Theme.closed
        default: return mr.isDraft ? .secondary : Theme.opened
        }
    }
}

struct IssueRow: View {
    let issue: Issue
    var showProject = false
    @Environment(Session.self) private var session

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: issue.state == "closed" ? "checkmark.circle.fill" : "smallcircle.filled.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(issue.state == "closed" ? Theme.merged : Theme.opened)
                .frame(width: 22, height: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(issue.title).font(.body.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    if issue.confidential == true { Image(systemName: "eye.slash.fill").font(.caption).foregroundStyle(.orange) }
                }
                Text(showProject ? (issue.references?.full ?? issue.reference) : issue.reference)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                LabelRow(labels: issue.labels ?? [])
                HStack(spacing: 12) {
                    Avatar(user: issue.author, instance: session.instance, size: 18)
                    if let date = issue.updatedAt { Meta(symbol: "clock", text: date.relative) }
                    if let notes = issue.userNotesCount, notes > 0 { Meta(symbol: "bubble.left", text: "\(notes)") }
                    if let milestone = issue.milestone { Meta(symbol: "flag", text: milestone.title) }
                    if let assignees = issue.assignees, !assignees.isEmpty {
                        Spacer(minLength: 0)
                        AvatarStack(users: assignees, instance: session.instance, size: 18)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
