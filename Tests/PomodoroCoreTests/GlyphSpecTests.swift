import Foundation
import Testing
@testable import PomodoroCore

struct GlyphCase: Sendable, CustomTestStringConvertible {
    let state: TimerState
    let progress: Double
    let expected: GlyphSpec

    var testDescription: String { "\(state) @ \(progress)" }
}

private let glyphTable: [GlyphCase] = [
    .init(state: .idle, progress: 0, expected: .init(style: .dimmed, arc: 0)),
    .init(state: .idle, progress: 0.7, expected: .init(style: .dimmed, arc: 0)),
    .init(state: .running(phase: .work, endDate: t0, total: 1500), progress: 0.25,
          expected: .init(style: .filled, arc: 0.25)),
    .init(state: .running(phase: .rest, endDate: t0, total: 300), progress: 0.5,
          expected: .init(style: .outlined, arc: 0.5)),
    .init(state: .paused(phase: .work, remaining: 600, total: 1500), progress: 0.6,
          expected: .init(style: .filled, arc: 0.6)),
    .init(state: .paused(phase: .rest, remaining: 60, total: 300), progress: 0.8,
          expected: .init(style: .outlined, arc: 0.8)),
    .init(state: .finished(phase: .work), progress: 0, expected: .init(style: .filled, arc: 1)),
    .init(state: .finished(phase: .rest), progress: 0, expected: .init(style: .outlined, arc: 1)),
]

@Suite(.timeLimit(.minutes(1))) struct GlyphSpecTests {
    @Test(arguments: glyphTable)
    func mapping(_ row: GlyphCase) {
        #expect(GlyphSpec.make(state: row.state, progress: row.progress) == row.expected)
    }

    @Test(arguments: glyphTable)
    func rendersTemplateImage(_ row: GlyphCase) {
        let image = StatusGlyph.image(spec: row.expected)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    }
}
