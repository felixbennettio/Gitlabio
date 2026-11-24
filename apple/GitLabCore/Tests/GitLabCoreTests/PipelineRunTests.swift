import Foundation
import Testing
@testable import GitLabCore

private func client(_ transport: RecordingTransport) throws -> GitLabClient {
    GitLabClient(instance: try GitLabInstance("https://git.example.test/gitlab"), credential: .accessToken("test-only"), transport: transport)
}

@Suite struct PipelineRunTests {
    @Test func inputsKeepTheirNamesAndVariablesKeepTheirType() async throws {
        let transport = RecordingTransport { _ in (201, [:], Data(#"{"id":9,"status":"created","ref":"main"}"#.utf8)) }
        _ = try await client(transport).runPipeline(3, ref: "main",
                                                    variables: [PipelineVariable(key: "CONFIG", value: "a=1", variableType: "file")],
                                                    inputs: ["deployTarget": .string("staging"), "shards": .number(3), "ui": .bool(false)])
        let json = try #require(try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as? [String: Any])
        let inputs = try #require(json["inputs"] as? [String: Any])
        #expect(inputs["deployTarget"] as? String == "staging")
        #expect(inputs["shards"] as? Int == 3)
        #expect(inputs["ui"] as? Bool == false)
        let variable = try #require((json["variables"] as? [[String: Any]])?.first)
        #expect(variable["variable_type"] as? String == "file")
    }

    @Test func noInputsKeyWithoutInputs() async throws {
        let transport = RecordingTransport { _ in (201, [:], Data(#"{"id":9,"status":"created","ref":"main"}"#.utf8)) }
        _ = try await client(transport).runPipeline(3, ref: "main")
        let json = try #require(try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as? [String: Any])
        #expect(json["inputs"] == nil)
    }

    @Test func runFormUsesGraphQLAndRetriesUncachedVariables() async throws {
        var calls = 0
        let transport = RecordingTransport { _ in
            calls += 1
            let variables = calls == 1 ? "null" : #"[{"key":"UPLOAD_TESTFLIGHT","value":"false","valueOptions":["false","true"],"description":"Upload"}]"#
            let body = """
            {"data":{"project":{"ciPipelineCreationInputs":[
              {"name":"environment","type":"STRING","description":null,"default":"staging","options":["staging","production"],"required":false,"regex":null},
              {"name":"shards","type":"NUMBER","default":2,"options":null,"required":true}
            ],"ciConfigVariables":\(variables)}}}
            """
            return (200, [:], Data(body.utf8))
        }
        let form = try await client(transport).runPipelineForm(projectPath: "group/app", ref: "main")
        #expect(calls == 2)
        #expect(form.inputs.map(\.name) == ["environment", "shards"])
        #expect(form.inputs[0].options == [.string("staging"), .string("production")])
        #expect(form.inputs[1].default == .number(2))
        #expect(form.inputs[1].required)
        #expect(form.variables.first?.valueOptions == ["false", "true"])
        let request = transport.requests[0]
        #expect(request.url?.absoluteString == "https://git.example.test/gitlab/api/graphql")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "test-only")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect((body["variables"] as? [String: String])?["project"] == "group/app")
    }

    @Test func graphQLErrorsSurfaceAsValidation() async throws {
        let transport = RecordingTransport { _ in (200, [:], Data(#"{"data":null,"errors":[{"message":"Field 'x' doesn't exist"}]}"#.utf8)) }
        await #expect(throws: GitLabError.validation("Field 'x' doesn't exist")) {
            _ = try await client(transport).runPipelineForm(projectPath: "g/a", ref: "main")
        }
    }

    @Test func schedulesDecodeAndPlay() async throws {
        let list = """
        [{"id":13,"description":"Nightly build","ref":"refs/heads/main","cron":"0 2 * * *","cron_timezone":"Asia/Shanghai",
          "next_run_at":"2026-10-30T18:00:00.000Z","active":true,"created_at":"2026-10-01T00:00:00.000Z",
          "owner":{"id":1,"username":"u","name":"U"},"inputs":"unexpected shape"}]
        """
        let transport = RecordingTransport { request in
            request.httpMethod == "POST" ? (201, [:], Data(#"{"message":"201 Created"}"#.utf8)) : (200, [:], Data(list.utf8))
        }
        let api = try client(transport)
        let schedule = try #require(try await api.pipelineSchedules(4).items.first)
        #expect(schedule.title == "Nightly build")
        #expect(schedule.refName == "main")
        #expect(schedule.cronTimezone == "Asia/Shanghai")
        #expect(schedule.nextRunAt != nil)
        #expect(schedule.inputs == nil)
        try await api.playPipelineSchedule(4, id: 13)
        #expect(transport.requests[1].httpMethod == "POST")
        #expect(transport.requests[1].url!.path.hasSuffix("/projects/4/pipeline_schedules/13/play"))
    }

    @Test(arguments: [("refs/merge-requests/9/head", "!9"), ("refs/merge-requests/12/train", "!12"), ("refs/heads/main", "main"),
                      ("refs/tags/v1.0", "v1.0"), ("feat/x", "feat/x"), ("refs/merge-requests/x/head", "refs/merge-requests/x/head")])
    func refNames(raw: String, short: String) {
        #expect(GitRef(raw).shortName == short)
    }

    @Test func inputTextConversion() throws {
        #expect(try CIInputSpec(name: "n", type: .number).value(from: " 3 ") == .number(3))
        #expect(try CIInputSpec(name: "b", type: .boolean).value(from: "TRUE") == .bool(true))
        #expect(try CIInputSpec(name: "a", type: .array).value(from: "x, y,") == .array([.string("x"), .string("y")]))
        #expect(throws: GitLabError.self) { try CIInputSpec(name: "n", type: .number).value(from: "many") }
        #expect(CIInputValue.number(2).text == "2")
    }

    @Test func demoServesScheduleAndForm() async throws {
        let demo = DemoTransport.client(latency: .zero)
        let form = try await demo.runPipelineForm(projectPath: "aurora/mobile-app", ref: "main")
        #expect(form.inputs.count == 4)
        #expect(form.variables.contains { $0.key == "UPLOAD_TESTFLIGHT" })
        let schedules = try await demo.pipelineSchedules(101).items
        #expect(schedules.count == 3)
        #expect(schedules[0].variables == nil)
        let detail = try await demo.pipelineSchedule(101, id: schedules[0].id)
        #expect(detail.variables?.count == 2)
        try await demo.playPipelineSchedule(101, id: schedules[0].id)
    }
}

@Suite struct CronTests {
    @Test(arguments: [("0 2 * * *", "每天 02:00"), ("0 9 * * 1", "每周一 09:00"), ("30 6 1 * *", "每月 1 日 06:30"),
                      ("*/15 * * * *", "每 15 分钟"), ("0 8 * * 1-5", "工作日 08:00"), ("5 * * * *", "每小时第 5 分"),
                      ("0 */6 * * *", "每 6 小时（第 0 分）"), ("0 9 * * 1,3", "每周一、周三 09:00"), ("0 0 1 1 *", "0 0 1 1 *"),
                      ("@daily", "@daily")])
    func describes(cron: String, text: String) {
        #expect(CronDescription.describe(cron) == text)
    }
}

@Suite struct RunFormFallbackTests {
    @Test func olderInstancesStillGetPrefilledVariables() async throws {
        let transport = RecordingTransport { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            if body.contains("ciPipelineCreationInputs") {
                return (200, [:], Data(#"{"errors":[{"message":"Field 'ciPipelineCreationInputs' doesn't exist on type 'Project'"}]}"#.utf8))
            }
            return (200, [:], Data(#"{"data":{"project":{"ciConfigVariables":[{"key":"A","value":"1","valueOptions":null,"description":null}]}}}"#.utf8))
        }
        let api = GitLabClient(instance: try GitLabInstance("https://h.test"), credential: .accessToken("t"), transport: transport)
        let form = try await api.runPipelineForm(projectPath: "g/a", ref: "main")
        #expect(form.inputs.isEmpty)
        #expect(form.variables.map(\.key) == ["A"])
        #expect(form.variables[0].valueOptions.isEmpty)
    }
}
