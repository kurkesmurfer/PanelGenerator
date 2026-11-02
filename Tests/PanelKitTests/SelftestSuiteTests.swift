import XCTest
@testable import PanelKit

/// The built-in `--selftest` check groups, one XCTest case each, so a failure
/// is reported against the area it belongs to rather than as one red line.
/// `--selftest` itself stays as the end-to-end smoke test (it also renders
/// Docs/pg_demo.{svg,png}).
final class SelftestSuiteTests: XCTestCase {
    private func assertClean(_ failures: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"), file: file, line: line)
    }

    func testPersistence()   { assertClean(Selftest.persistenceChecks()) }
    func testStamps()        { assertClean(Selftest.stampChecks()) }
    func testTextExport()    { assertClean(Selftest.textExportChecks()) }
    func testBinding()       { assertClean(Selftest.bindingChecks()) }
    func testSymbols()       { assertClean(Selftest.symbolChecks()) }
    func testWidgets()       { assertClean(Selftest.widgetChecks()) }
    func testUniform()       { assertClean(Selftest.uniformChecks()) }
    func testPresets()       { assertClean(Selftest.presetChecks()) }
    func testColours()       { assertClean(Selftest.colourChecks()) }
    func testAlign()         { assertClean(Selftest.alignChecks()) }
    func testBulkBind()      { assertClean(Selftest.bulkBindChecks()) }
    func testLabels()        { assertClean(Selftest.labelChecks()) }
    func testSVGPath()       { assertClean(Selftest.svgPathChecks()) }
    func testSVGImport()     { assertClean(Selftest.svgImportChecks()) }
    func testCppImport()     { assertClean(Selftest.cppImportChecks()) }
    func testCompare()       { assertClean(Selftest.compareChecks()) }
    func testSwitch()        { assertClean(Selftest.switchChecks()) }
    func testIdentifiers()   { assertClean(Selftest.identifierChecks()) }
    func testCodegen()       { assertClean(Selftest.codegenChecks()) }
}
