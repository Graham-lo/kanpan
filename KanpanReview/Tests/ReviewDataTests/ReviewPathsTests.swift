import XCTest
import ReviewData

final class ReviewPathsTests: XCTestCase {
  /// 搬老目录按这张表搬：三个 JSON 一个都不许漏（草稿和重温进度是用户产出）。
  func testTheFileTableCoversEveryJSONTheStoreWrites() {
    let paths = ReviewPaths(directory: URL(fileURLWithPath: "/tmp/x"))
    XCTAssertEqual(Set(ReviewPaths.files), [paths.archive.lastPathComponent, paths.draft.lastPathComponent, paths.replay.lastPathComponent])
    XCTAssertEqual(ReviewPaths.legacy(in: URL(fileURLWithPath: "/tmp/root")).directory.lastPathComponent, "local")
    let id = UUID()
    XCTAssertEqual(paths.shot(id).deletingLastPathComponent(), paths.shots)
    XCTAssertEqual(paths.shot(id).lastPathComponent, id.uuidString + ".png")
  }
}
