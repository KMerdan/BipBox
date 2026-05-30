import BipboxCore
import Foundation

public final class PipelineIntakeService: IntakeService, @unchecked Sendable {
    private let pipeline: DefaultOrganizationPipeline
    private let configurationProvider: () -> OrganizationPipelineConfiguration

    public init(
        pipeline: DefaultOrganizationPipeline,
        configurationProvider: @escaping () -> OrganizationPipelineConfiguration
    ) {
        self.pipeline = pipeline
        self.configurationProvider = configurationProvider
    }

    public func submit(_ request: OrganizationRequest) async throws -> IntakeResult {
        let result = await pipeline.process(request, configuration: configurationProvider())
        let accepted = result.status != .failed
        return IntakeResult(request: result.request, accepted: accepted, message: result.message)
    }
}
