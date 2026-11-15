// GuideView.swift — Help ▸ User Guide: docs/guide.md, read from the copy
// inside the app so it works offline. Headings, points, numbered steps and
// code are laid out here; words inside a line keep their Markdown (bold,
// code, links). A link to "#a-heading" scrolls to that heading, as on
// GitHub; any other link opens in the browser. The source on GitHub, and
// the contents, stay pinned above.

import SwiftUI

struct GuideView: View {
    static let source = URL(string: "https://github.com/frodehegland/cynapse")!

    /// The guide as blocks: a heading, a point, a step, a paragraph or code.
    private enum Block {
        case title(String), heading(String), subheading(String)
        case point(String), step(String, String), paragraph(String), code(String)
    }

    private let blocks: [Block] = {
        guard let url = Bundle.main.url(forResource: "Cynapse Guide", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [.paragraph("The guide is missing from the app.")] }
        var blocks: [Block] = []
        var code: [String]?
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))); code = nil } else { code = [] }
            } else if code != nil {
                code?.append(line)
            } else if line.hasPrefix("### ") {
                blocks.append(.subheading(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                blocks.append(.point(String(line.dropFirst(2))))
            } else if let range = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                blocks.append(.step(line[range].trimmingCharacters(in: .whitespaces), String(line[range.upperBound...])))
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                blocks.append(.paragraph(line))
            }
        }
        return blocks
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in view(block, proxy: proxy) }
                }
                .padding(32)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .top, spacing: 0) { bar(proxy) }
            // "#heading" links scroll within the guide; the rest open in the browser.
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == nil, let anchor = url.fragment else { return .systemAction }
                withAnimation { proxy.scrollTo(anchor, anchor: .top) }
                return .handled
            })
        }
        .frame(minWidth: 560, idealWidth: 780, minHeight: 500, idealHeight: 860)
    }

    /// Pinned above the guide: its source on GitHub, and the way back to the contents.
    private func bar(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 14) {
            Link(destination: Self.source) {
                Label("Source on GitHub: github.com/frodehegland/cynapse", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .help("The code, the questions and every prompt, open for anyone to read")
            Spacer()
            Button("Contents", systemImage: "list.bullet") { withAnimation { proxy.scrollTo("contents", anchor: .top) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func view(_ block: Block, proxy: ScrollViewProxy) -> some View {
        switch block {
        case .title(let text):
            Text(inline(text)).font(.largeTitle.weight(.bold))
        case .heading(let text):
            HStack(alignment: .firstTextBaseline) {
                Text(inline(text)).font(.title2.weight(.semibold))
                Spacer()
                if Self.slug(text) != "contents" {
                    Button("Contents ↑") { withAnimation { proxy.scrollTo("contents", anchor: .top) } }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .padding(.top, 18)
            .id(Self.slug(text))
        case .subheading(let text):
            Text(inline(text)).font(.headline).padding(.top, 8).id(Self.slug(text))
        case .point(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
        case .step(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number).foregroundStyle(.secondary).monospacedDigit()
                Text(inline(text)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
        case .paragraph(let text):
            Text(inline(text)).fixedSize(horizontal: false, vertical: true)
        case .code(let text):
            ScrollView(.horizontal) {
                Text(text).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 8))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// A heading's anchor, as GitHub makes it: lower case, punctuation
    /// dropped, spaces as hyphens ("The Live View" → "the-live-view").
    static func slug(_ heading: String) -> String {
        let plain = heading.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        return String(plain.lowercased().unicodeScalars.compactMap { c -> Character? in
            if CharacterSet.alphanumerics.contains(c) || c == "-" { return Character(c) }
            if c == " " { return "-" }
            return nil
        })
    }
}
