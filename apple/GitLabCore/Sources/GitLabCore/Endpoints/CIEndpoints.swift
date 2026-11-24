import Foundation

public enum CIAction: String, Sendable { case retry, cancel, play }

/// Encoded verbatim: input names are user-defined and must not be snake_cased.
struct NewPipeline: Encodable, Sendable {
    struct Variable: Encodable, Sendable {
        let key: String
        let value: String
        let variableType: String
        enum CodingKeys: String, CodingKey { case key, value, variableType = "variable_type" }
    }

    var ref: String
    var variables: [Variable]
    var inputs: [String: CIInputValue]?
}

private let runFormQuery = """
query($project: ID!, $ref: String!) {
  project(fullPath: $project) {
    ciPipelineCreationInputs(ref: $ref) { name type description default options required regex }
    ciConfigVariables(ref: $ref) { key value valueOptions description }
  }
}
"""

/// For instances older than GitLab 17.10, which have prefilled variables but no inputs.
private let runFormVariablesQuery = """
query($project: ID!, $ref: String!) {
  project(fullPath: $project) { ciConfigVariables(ref: $ref) { key value valueOptions description } }
}
"""

private struct RunFormReply: Decodable {
    struct Project: Decodable {
        let ciPipelineCreationInputs: [CIInputSpec]?
        let ciConfigVariables: [CIConfigVariable]?
    }
    let project: Project?
}

extension GitLabClient {
    public func pipelines(_ project: Int, ref: String? = nil, status: CIStatus? = nil, page: Int = 1) async throws -> Page<Pipeline> {
        var query: [URLQueryItem] = []
        if let ref, !ref.isEmpty { query.append(.init(name: "ref", value: ref)) }
        if let status { query.append(.init(name: "status", value: status.rawValue)) }
        return try await list(projectPath(project) + ["pipelines"], page: page, query: query)
    }

    public func pipeline(_ project: Int, id: Int) async throws -> Pipeline {
        try await get(projectPath(project) + ["pipelines", String(id)])
    }

    /// All jobs of a pipeline (latest attempt of each), following pagination.
    public func pipelineJobs(_ project: Int, pipeline: Int) async throws -> [Job] {
        var jobs: [Job] = []
        var page: Int? = 1
        while let current = page, current <= 10 {
            let result: Page<Job> = try await list(projectPath(project) + ["pipelines", String(pipeline), "jobs"],
                                                   page: current, perPage: 100)
            jobs += result.items
            page = result.next
        }
        return jobs
    }

    public func runPipeline(_ project: Int, ref: String, variables: [PipelineVariable] = [],
                            inputs: [String: CIInputValue] = [:]) async throws -> Pipeline {
        guard !ref.isEmpty else { throw GitLabError.invalidInput("请选择分支或标签。") }
        let variables = variables.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { NewPipeline.Variable(key: $0.key, value: $0.value, variableType: $0.variableType) }
        let body = NewPipeline(ref: ref, variables: variables, inputs: inputs.isEmpty ? nil : inputs)
        let (data, _) = try await data(projectPath(project) + ["pipeline"], method: "POST", body: JSON.encodeVerbatim(body))
        return try JSON.decode(data)
    }

    /// Inputs (`spec: inputs`) and prefilled variables the CI configuration on `ref` declares.
    /// GitLab computes prefilled variables in the background and answers `null` until they are
    /// cached, so a miss is retried briefly before giving up with what is known.
    public func runPipelineForm(projectPath path: String, ref: String) async throws -> RunPipelineForm {
        var inputs: [CIInputSpec] = []
        var query = runFormQuery
        for attempt in 0..<4 {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(700 * attempt)) }
            let reply: RunFormReply
            do {
                reply = try await graphQL(query, variables: ["project": path, "ref": ref])
            } catch GitLabError.validation(let message) where query == runFormQuery && message?.contains("ciPipelineCreationInputs") == true {
                query = runFormVariablesQuery
                reply = try await graphQL(query, variables: ["project": path, "ref": ref])
            }
            guard let project = reply.project else { throw GitLabError.notFound }
            inputs = project.ciPipelineCreationInputs ?? inputs
            if let variables = project.ciConfigVariables { return RunPipelineForm(inputs: inputs, variables: variables) }
        }
        return RunPipelineForm(inputs: inputs)
    }

    public func pipelineSchedules(_ project: Int, page: Int = 1) async throws -> Page<PipelineSchedule> {
        try await list(projectPath(project) + ["pipeline_schedules"], page: page)
    }

    public func pipelineSchedule(_ project: Int, id: Int) async throws -> PipelineSchedule {
        try await get(projectPath(project) + ["pipeline_schedules", String(id)])
    }

    /// Runs a schedule now; its next scheduled run is unaffected. GitLab answers 201 without the pipeline.
    public func playPipelineSchedule(_ project: Int, id: Int) async throws {
        try await data(projectPath(project) + ["pipeline_schedules", String(id), "play"], method: "POST")
    }

    public func pipelineAction(_ project: Int, id: Int, action: CIAction) async throws -> Pipeline {
        precondition(action != .play, "Pipelines cannot be played; play individual manual jobs")
        return try await send("POST", projectPath(project) + ["pipelines", String(id), action.rawValue])
    }

    public func job(_ project: Int, id: Int) async throws -> Job {
        try await get(projectPath(project) + ["jobs", String(id)])
    }

    public func jobAction(_ project: Int, id: Int, action: CIAction) async throws -> Job {
        try await send("POST", projectPath(project) + ["jobs", String(id), action.rawValue])
    }

    /// Raw job log. GitLab has no ranged trace API, so callers poll and diff by length.
    public func jobTrace(_ project: Int, id: Int) async throws -> Data {
        try await data(projectPath(project) + ["jobs", String(id), "trace"]).0
    }
}
