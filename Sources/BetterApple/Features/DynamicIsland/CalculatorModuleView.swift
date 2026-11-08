import SwiftUI
import BetterAppleCore

struct CalculatorModuleView: View {
    @ObservedObject var calculator: CalculatorService
    var compact = false
    @State private var showingHistory = false
    @FocusState private var expressionFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.workspaceMotionDisabled) private var localMotionDisabled
    private var reduceMotion: Bool { systemReduceMotion || localMotionDisabled }
    @Environment(\.islandFocusRequest) private var focusRequest
    private var hasExpression: Bool { !calculator.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var status: String {
        if let message = calculator.errorMessage { return message }
        if calculator.copied { return "Result copied" }
        if compact { return calculator.historyEnabled ? "Return saves this calculation" : "Calculates as you type" }
        return calculator.historyEnabled ? "+  −  ×  ÷  ^  %  ( )  ·  Return to save" : "+  −  ×  ÷  ^  %  ( )  ·  Calculates as you type"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                TextField("(24 + 18) / 6", text: $calculator.expression)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: compact ? 17 : 21, design: .monospaced))
                    .focused($expressionFocused)
                    .accessibilityLabel("Mathematical expression")
                    .accessibilityHint("Results update as you type. Press Return to save when history is enabled.")
                    .onSubmit { calculator.commit() }
                HStack(spacing: 8) {
                    Text(calculator.resultText)
                        .font(.system(size: compact ? 29 : 34, weight: .medium, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.5).textSelection(.enabled)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.quick), value: calculator.resultText)
                        .accessibilityLabel("Result: \(calculator.resultText)")
                    Spacer(minLength: 0)
                    Button { calculator.copyResult() } label: {
                        Image(systemName: calculator.copied ? "checkmark" : "doc.on.doc")
                            .frame(width: 18, height: 18)
                    }.buttonStyle(SurfaceButtonStyle())
                        .disabled(calculator.errorMessage != nil || !hasExpression)
                        .help(calculator.copied ? "Result copied" : "Copy result")
                        .accessibilityLabel(calculator.copied ? "Result copied" : "Copy result")
                    Button { showingHistory.toggle() } label: {
                        Image(systemName: "clock.arrow.circlepath").frame(width: 18, height: 18)
                    }.buttonStyle(SurfaceButtonStyle())
                        .help("Calculation history").accessibilityLabel("Calculation history")
                        .popover(isPresented: $showingHistory) { historyContent }
                }
                // Reserve the feedback line so typing an incomplete expression does not move controls.
                Text(status).font(.caption)
                    .foregroundStyle(calculator.errorMessage != nil ? Color.orange : calculator.copied ? Color.green : Color.secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, minHeight: compact ? 28 : 28, alignment: .topLeading)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .onChange(of: focusRequest, initial: true) { _, request in
                if request > 0 { expressionFocused = true }
            }
    }
    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calculation history").font(.headline)
                Spacer()
                Button("Clear", role: .destructive) { calculator.clearHistory() }.disabled(calculator.history.isEmpty)
            }
            Toggle("Save calculations locally", isOn: $calculator.historyEnabled)
            Text("Keeps the last 30 calculations. Turning this off deletes saved history.")
                .font(.caption).foregroundStyle(.secondary)
            if calculator.history.isEmpty {
                Label(calculator.historyEnabled ? "Press Return or copy a result to save it." : "History is off.", systemImage: "clock.arrow.circlepath")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(calculator.history) { entry in
                            HStack(spacing: 6) {
                                Button {
                                    calculator.use(entry); showingHistory = false
                                    expressionFocused = true
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.expression).font(.system(.caption, design: .monospaced)).lineLimit(2)
                                        Text("= " + Calculator.formatted(entry.result)).font(.callout.weight(.medium))
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("Reuse \(entry.expression)")
                                Button { calculator.removeHistory(id: entry.id) } label: {
                                    Image(systemName: "xmark").frame(width: 16, height: 16)
                                }.buttonStyle(SurfaceButtonStyle())
                                    .help("Remove calculation").accessibilityLabel("Remove \(entry.expression)")
                            }.background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                                .transition(WorkspaceMotion.transition(reduceMotion: reduceMotion))
                        }
                    }.animation(WorkspaceMotion.animation(reduceMotion: reduceMotion, duration: WorkspaceMotion.content), value: calculator.history.map(\.id))
                }.frame(maxHeight: 280).scrollBounceBehavior(.basedOnSize)
            }
        }.padding(18).frame(width: 340)
            .onExitCommand { showingHistory = false }
    }
}
