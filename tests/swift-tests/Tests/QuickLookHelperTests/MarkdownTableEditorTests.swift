import XCTest
@testable import QuickLookHelpers

final class MarkdownTableEditorTests: XCTestCase {

    func testReplacesEditedCellAndPreservesSurroundingMarkdown() {
        let markdown = """
        # Title

        | Name | Count |
        | --- | --- |
        | Alpha | 1 |
        | Beta | 2 |

        After
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Name", "Count"],
                ["Alpha Prime", "1"],
                ["Beta", "2"],
            ])
        )

        XCTAssertEqual(updated, """
        # Title

        | Name | Count |
        | --- | --- |
        | Alpha Prime | 1 |
        | Beta | 2 |

        After
        """)
    }

    func testReplacesRequestedTableWhenMultipleTablesExist() {
        let markdown = """
        | A | B |
        | --- | --- |
        | 1 | 2 |

        | C | D |
        | --- | --- |
        | 3 | 4 |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 1, rows: [
                ["C", "D", "E"],
                ["3", "4", "5"],
            ])
        )

        XCTAssertEqual(updated, """
        | A | B |
        | --- | --- |
        | 1 | 2 |

        | C | D | E |
        | --- | --- | --- |
        | 3 | 4 | 5 |
        """)
    }

    func testIgnoresPipeTablesInsideFencedCode() {
        let markdown = """
        ```
        | Not | A Table |
        | --- | --- |
        | x | y |
        ```

        | Real | Table |
        | --- | --- |
        | old | value |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Real", "Table"],
                ["new", "value"],
            ])
        )

        XCTAssertEqual(updated, """
        ```
        | Not | A Table |
        | --- | --- |
        | x | y |
        ```

        | Real | Table |
        | --- | --- |
        | new | value |
        """)
    }

    func testFenceCloseRequiresMatchingLength() {
        let markdown = """
        ````
        | Not | A Table |
        | --- | --- |
        | x | y |
        ```

        | Real | Table |
        | --- | --- |
        | old | value |
        ````
        """

        XCTAssertNil(MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Real", "Table"],
                ["new", "value"],
            ])
        ))
    }

    func testIgnoresIndentedCodeTables() {
        let markdown = """
            | Not | A Table |
            | --- | --- |
            | x | y |

        | Real | Table |
        | --- | --- |
        | old | value |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Real", "Table"],
                ["new", "value"],
            ])
        )

        XCTAssertEqual(updated, """
            | Not | A Table |
            | --- | --- |
            | x | y |

        | Real | Table |
        | --- | --- |
        | new | value |
        """)
    }

    func testIndentedFenceOpenerDoesNotHideFollowingTable() {
        let markdown = """
            ```

        | Real | Table |
        | --- | --- |
        | old | value |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Real", "Table"],
                ["new", "value"],
            ])
        )

        XCTAssertEqual(updated, """
            ```

        | Real | Table |
        | --- | --- |
        | new | value |
        """)
    }

    func testReplacesBlockquotedTableByRenderedIndex() {
        let markdown = """
        > | A | B |
        > | --- | --- |
        > | old | y |

        | Real | Table |
        | --- | --- |
        | keep | value |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["A", "B"],
                ["new", "y"],
            ])
        )

        XCTAssertEqual(updated, """
        > | A | B |
        > | --- | --- |
        > | new | y |

        | Real | Table |
        | --- | --- |
        | keep | value |
        """)
    }

    func testPreservesUneditedInlineMarkdownCells() {
        let markdown = """
        | Link | Bold | Plain |
        | --- | --- | --- |
        | [site](https://example.com) | **bold** | old |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(
                tableIndex: 0,
                rows: [
                    ["Link", "Bold", "Plain"],
                    ["site", "bold", "new"],
                ],
                dirtyRows: [
                    [false, false, false],
                    [false, false, true],
                ]
            )
        )

        XCTAssertEqual(updated, """
        | Link | Bold | Plain |
        | --- | --- | --- |
        | [site](https://example.com) | **bold** | new |
        """)
    }

    func testPreservesExistingColumnAlignment() {
        let markdown = """
        | Left | Center | Right |
        | :--- | :---: | ---: |
        | a | b | c |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Left", "Center", "Right", "New"],
                ["aa", "bb", "cc", "dd"],
            ])
        )

        XCTAssertEqual(updated, """
        | Left | Center | Right | New |
        | :--- | :---: | ---: | --- |
        | aa | bb | cc | dd |
        """)
    }

    func testDoesNotAcceptSeparatorWithDifferentColumnCount() {
        let markdown = """
        a | b
        ---

        | Real | Table |
        | --- | --- |
        | old | value |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Real", "Table"],
                ["new", "value"],
            ])
        )

        XCTAssertEqual(updated, """
        a | b
        ---

        | Real | Table |
        | --- | --- |
        | new | value |
        """)
    }

    func testEscapesPipesAndFlattensNewlinesInCells() {
        let markdown = """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["A", "B"],
                ["a | b", "line\nbreak"],
            ])
        )

        XCTAssertEqual(updated, """
        | A | B |
        | --- | --- |
        | a \\| b | line break |
        """)
    }
}
