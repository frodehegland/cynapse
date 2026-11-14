// GuideView.swift — Help ▸ Cynapse Guide: docs/guide.md, read from the
// copy inside the app so it works offline. Headings, points and numbered
// steps are laid out here; words inside a line keep their Markdown (bold,
// code).

import SwiftUI

struct GuideView: View {
    private let lines: [String] = {
        guard let url = Bundle.main.url(forResource: "Cynapse Guide", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ["The guide is missing from the app."] }
        return text.components(separatedBy: .newlines)
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in block(line) }
            }
            .textSelection(.enabled)
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 560, idealWidth: 760, minHeight: 500, idealHeight: 820)
    }

    @ViewBuilder
    private func block(_ line: String) -> some View {
        if line.hasPrefix("### ") {
            Text(inline(String(line.dropFirst(4)))).font(.headline).padding(.top, 8)
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3)))).font(.title2.weight(.semibold)).padding(.top, 14)
        } else if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2)))).font(.largeTitle.weight(.bold))
        } else if line.hasPrefix("- ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(String(line.dropFirst(2))))
            }
            .padding(.leading, 6)
        } else if let range = line.range(of: #"^\d+\. "#, options: .regularExpression) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line[range].trimmingCharacters(in: .whitespaces)).foregroundStyle(.secondary).monospacedDigit()
                Text(inline(String(line[range.upperBound...])))
            }
            .padding(.leading, 6)
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(inline(line)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
