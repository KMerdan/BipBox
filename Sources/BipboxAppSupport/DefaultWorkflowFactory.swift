import BipboxCore
import Foundation

public enum DefaultWorkflowFactory {
    public static func aiReadyReviewWorkflow() -> Workflow {
        Workflow(
            name: "AI-ready review workflow",
            root: WorkflowNode(
                kind: .aiClassify,
                name: "Classify with AI placeholder"
            )
        )
    }

    public static func extensionRouter(libraryRootURL: URL) -> Workflow {
        let pdfDestination = libraryRootURL
            .appendingPathComponent("Documents", isDirectory: true)
            .path + "/"
        let imageDestination = libraryRootURL
            .appendingPathComponent("Images", isDirectory: true)
            .path + "/"

        let pdfNode = WorkflowNode(
            kind: .action,
            name: "Move PDFs",
            actions: [
                ActionDescriptor(
                    operationKind: .move,
                    parameters: ["destination": pdfDestination]
                )
            ]
        )
        let imageNode = WorkflowNode(
            kind: .action,
            name: "Move Images",
            actions: [
                ActionDescriptor(
                    operationKind: .move,
                    parameters: ["destination": imageDestination]
                )
            ]
        )

        return Workflow(
            name: "Default extension router",
            root: WorkflowNode(
                kind: .router,
                name: "Route by extension",
                branches: [
                    WorkflowBranch(
                        name: "PDF",
                        conditions: [
                            ConditionDescriptor(field: .fileExtension, operation: .equals, value: "pdf")
                        ],
                        node: pdfNode
                    ),
                    WorkflowBranch(
                        name: "Images",
                        conditions: [
                            ConditionDescriptor(field: .fileExtension, operation: .matchesRegex, value: "jpe?g|png|gif|heic|webp")
                        ],
                        node: imageNode
                    )
                ],
                fallback: WorkflowNode(
                    kind: .review,
                    name: "Review unmatched items"
                )
            )
        )
    }
}
