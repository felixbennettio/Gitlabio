import SwiftUI
import GitLabCore

/// Manual pipeline run: ref, the inputs and prefilled variables the CI configuration declares for
/// that ref, and any extra variables. Only values the user changed are sent, so projects that
/// forbid pipeline variables still accept a plain run.
struct RunPipelineView: View {
    let project: Project
    var initialRef: String?
    var onStarted: (Pipeline) async -> Void

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var ref = ""
    @State private var picking = false
    @State private var busy = false
    @State private var error: String?
    @State private var started: Pipeline?

    @State private var form: RunPipelineForm?
    @State private var formNote: String?
    @State private var loadingForm = false
    @State private var inputText: [String: String] = [:]
    @State private var inputFlags: [String: Bool] = [:]
    @State private var prefilled: [String: String] = [:]
    @State private var extra: [DraftVariable] = []

    struct DraftVariable: Identifiable {
        let id = UUID()
        var key = ""
        var value = ""
        var type = "env_var"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("运行于") {
                    PickerRow(title: "分支或标签", value: ref) { picking = true }
                }
                if loadingForm {
                    Section {
                        HStack(spacing: 10) { ProgressView(); Text("正在读取 CI 配置…").foregroundStyle(.secondary) }
                    }
                }
                if let form, !form.inputs.isEmpty {
                    Section {
                        ForEach(form.inputs) { inputRow($0) }
                    } header: { Text("输入") } footer: { Text("来自 \(ref) 上 .gitlab-ci.yml 的 spec: inputs。未改动的输入使用默认值。") }
                }
                if let form, !form.variables.isEmpty {
                    Section {
                        ForEach(form.variables) { prefilledRow($0) }
                    } header: { Text("预设变量") } footer: { Text("CI 配置为手动运行预设的变量。只有改过的值会作为流水线变量发送。") }
                }
                if let formNote {
                    Section { Label(formNote, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    ForEach($extra) { $variable in extraRow($variable) }
                    Button { extra.append(DraftVariable()) } label: { Label("添加变量", systemImage: "plus.circle") }
                } header: { Text("其他变量") } footer: { Text("只用于这次运行，会覆盖同名的项目变量。项目可能限制谁能设置流水线变量。") }
                if let error { Section { InlineError(message: error).listRowInsets(EdgeInsets()) } }
                if let started {
                    Section {
                        NavigationLink(value: Route.pipeline(projectID: project.id, id: started.id)) {
                            Label("流水线 #\(String(started.id)) 已创建", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.opened)
                        }
                    }
                }
            }
            .navigationTitle("运行流水线")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(started == nil ? "取消" : "完成") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: submit) { if busy { ProgressView() } else { Text("运行").bold() } }
                        .disabled(busy || ref.isEmpty || started != nil)
                        .accessibilityIdentifier("run-pipeline-submit")
                }
            }
            .sheet(isPresented: $picking) { RefPicker(project: project, selection: $ref) }
            .onAppear {
                if ref.isEmpty { ref = initialRef ?? project.defaultBranch ?? "main" }
                // Screenshot route: show one filled and one empty field.
                if session.isDemo, LaunchOptions.screen == "run-pipeline", extra.isEmpty { extra = [DraftVariable(key: "DEPLOY_NOTE")] }
            }
            .task(id: ref) { await loadForm() }
            .routeDestinations()
        }
    }

    // MARK: Rows

    private func inputTitle(_ spec: CIInputSpec) -> some View {
        HStack(spacing: 6) {
            Text(spec.name).font(.body.monospaced())
            if spec.required { Text("必填").font(.caption2.bold()).foregroundStyle(Theme.orange) }
        }
    }

    @ViewBuilder
    private func inputRow(_ spec: CIInputSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if spec.type == .boolean {
                Toggle(isOn: flag(spec)) { inputTitle(spec) }
            } else if let options = spec.options, !options.isEmpty {
                Picker(selection: text(spec)) {
                    if spec.default == nil { Text("未选择").tag("") }
                    ForEach(options, id: \.self) { Text($0.text).tag($0.text) }
                } label: { inputTitle(spec) }
            } else {
                inputTitle(spec)
                TextField(spec.type == .array ? "多个值用逗号分隔" : "值", text: text(spec), axis: .vertical)
                    .technicalInput()
                    .numericInput(spec.type == .number)
                    .font(.body.monospaced())
                    .lineLimit(1...4)
                    .fieldBox()
            }
            if let description = spec.description, !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func prefilledRow(_ variable: CIConfigVariable) -> some View {
        let binding = Binding(get: { prefilled[variable.key] ?? variable.value ?? "" }, set: { prefilled[variable.key] = $0 })
        VStack(alignment: .leading, spacing: 6) {
            if variable.valueOptions.count > 1 {
                Picker(selection: binding) {
                    ForEach(variable.valueOptions, id: \.self) { Text($0).tag($0) }
                } label: { Text(variable.key).font(.body.monospaced()) }
            } else {
                Text(variable.key).font(.body.monospaced())
                TextField("值", text: binding, axis: .vertical).technicalInput().font(.body.monospaced()).lineLimit(1...4).fieldBox()
            }
            if let description = variable.description, !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Name and value share one boxed field style so their edges line up; type and delete sit beside the name.
    private func extraRow(_ variable: Binding<DraftVariable>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("变量名", text: variable.key).technicalInput().font(.body.monospaced()).fieldBox()
                Picker("类型", selection: variable.type) {
                    Text("变量").tag("env_var")
                    Text("文件").tag("file")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Button(role: .destructive) {
                    let id = variable.wrappedValue.id
                    withAnimation { extra.removeAll { $0.id == id } }
                } label: { Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(.red) }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除变量")
            }
            TextField("值", text: variable.value, axis: .vertical)
                .technicalInput()
                .font(.body.monospaced())
                .lineLimit(1...6)
                .fieldBox()
        }
        .padding(.vertical, 4)
    }

    private func text(_ spec: CIInputSpec) -> Binding<String> {
        Binding(get: { inputText[spec.name] ?? "" }, set: { inputText[spec.name] = $0 })
    }

    private func flag(_ spec: CIInputSpec) -> Binding<Bool> {
        Binding(get: { inputFlags[spec.name] ?? spec.default?.bool ?? false }, set: { inputFlags[spec.name] = $0 })
    }

    // MARK: Loading and submitting

    private func loadForm() async {
        let client = session.client, path = project.pathWithNamespace, ref = ref
        guard !ref.isEmpty else { return }
        loadingForm = true
        defer { loadingForm = false }
        do {
            let loaded = try await client.runPipelineForm(projectPath: path, ref: ref)
            guard !Task.isCancelled else { return }
            form = loaded
            formNote = nil
            inputText = Dictionary(uniqueKeysWithValues: loaded.inputs.map { ($0.name, $0.default?.text ?? "") })
            inputFlags = [:]
            prefilled = [:]
        } catch is CancellationError {
        } catch {
            form = nil
            formNote = "无法读取这个分支 CI 配置里的输入和预设变量（\(error.localizedDescription)）。仍可手动添加变量。"
        }
    }

    private func submit() {
        error = nil
        var inputs: [String: CIInputValue] = [:]
        var variables: [PipelineVariable] = []
        do {
            for spec in form?.inputs ?? [] {
                if spec.type == .boolean {
                    let value = CIInputValue.bool(inputFlags[spec.name] ?? spec.default?.bool ?? false)
                    if value != spec.default || spec.required { inputs[spec.name] = value }
                    continue
                }
                let text = inputText[spec.name] ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if spec.required && spec.default == nil { throw GitLabError.invalidInput("请填写必填输入「\(spec.name)」。") }
                    continue
                }
                let value = try spec.value(from: text)
                if value != spec.default { inputs[spec.name] = value }
            }
        } catch {
            self.error = error.localizedDescription
            return
        }
        for variable in form?.variables ?? [] {
            if let value = prefilled[variable.key], value != (variable.value ?? "") {
                variables.append(PipelineVariable(key: variable.key, value: value))
            }
        }
        variables += extra.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { PipelineVariable(key: $0.key.trimmingCharacters(in: .whitespaces), value: $0.value, variableType: $0.type) }

        busy = true
        let client = session.client, id = project.id, ref = ref
        Task {
            defer { busy = false }
            do {
                let pipeline = try await client.runPipeline(id, ref: ref, variables: variables, inputs: inputs)
                started = pipeline
                Haptics.success()
                await onStarted(pipeline)
            } catch { self.error = error.localizedDescription }
        }
    }
}
