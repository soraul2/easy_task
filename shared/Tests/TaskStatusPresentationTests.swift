import Testing
@testable import EasyTaskCore

@Test
func taskStatusPresentationMetadataIsCompleteAndDistinct() {
    let statuses = TaskStatus.allCases

    #expect(Set(statuses.map(\.systemImage)).count == statuses.count)
    #expect(statuses.allSatisfy { !$0.guidanceText.isEmpty })
    #expect(statuses.allSatisfy { !$0.emptyStateTitle.isEmpty })
    #expect(statuses.allSatisfy { !$0.emptyStateDescription.isEmpty })
    #expect(statuses.allSatisfy { !$0.primaryActionTitle.isEmpty })
    #expect(statuses.allSatisfy { $0.primaryActionStatus != $0 })
    #expect(statuses.allSatisfy { !$0.transitionNotice.isEmpty })
}

@Test
func taskStatusPrimaryActionsFollowTheExpectedWorkflow() {
    #expect(TaskStatus.todo.primaryActionStatus == .doing)
    #expect(TaskStatus.doing.primaryActionStatus == .done)
    #expect(TaskStatus.done.primaryActionStatus == .doing)
}
