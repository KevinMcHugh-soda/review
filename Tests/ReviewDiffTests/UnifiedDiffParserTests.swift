import Testing
@testable import ReviewDiff

@Suite
struct UnifiedDiffParserTests {
    @Test("Numbers context, added and removed lines on both sides")
    func numbersLines() throws {
        let diff = """
            diff --git a/main.go b/main.go
            index 1111111..2222222 100644
            --- a/main.go
            +++ b/main.go
            @@ -10,4 +10,5 @@ func main() {
             a
            -b
            +B
            +C
             d
             e

            """
        let file = try #require(try UnifiedDiffParser.parse(diff).first)
        #expect(file.status == .modified)
        #expect(file.path == "main.go")
        let hunk = try #require(file.hunks.first)
        #expect(hunk.section == "func main() {")
        #expect(hunk.lines.map(\.kind) == [.context, .removed, .added, .added, .context, .context])
        #expect(hunk.lines.map(\.oldLine) == [10, 11, nil, nil, 12, 13])
        #expect(hunk.lines.map(\.newLine) == [10, nil, 11, 12, 13, 14])
        #expect(file.additions == 2)
        #expect(file.deletions == 1)
    }

    @Test("Reads an omitted count as one")
    func omittedCount() throws {
        let diff = """
            diff --git a/x b/x
            --- a/x
            +++ b/x
            @@ -3 +3 @@
            -old
            +new

            """
        let hunk = try #require(try UnifiedDiffParser.parse(diff).first?.hunks.first)
        #expect((hunk.oldStart, hunk.oldCount, hunk.newStart, hunk.newCount) == (3, 1, 3, 1))
        #expect(hunk.header == "@@ -3,1 +3,1 @@")
    }

    @Test("Treats /dev/null as an added or deleted file")
    func addedAndDeleted() throws {
        let diff = """
            diff --git a/new.ts b/new.ts
            new file mode 100644
            index 0000000..3333333
            --- /dev/null
            +++ b/new.ts
            @@ -0,0 +1,2 @@
            +one
            +two
            diff --git a/gone.ts b/gone.ts
            deleted file mode 100644
            index 4444444..0000000
            --- a/gone.ts
            +++ /dev/null
            @@ -1 +0,0 @@
            -bye

            """
        let files = try UnifiedDiffParser.parse(diff)
        #expect(files.map(\.status) == [.added, .deleted])
        #expect(files[0].oldPath == nil)
        #expect(files[0].newPath == "new.ts")
        #expect(files[0].newMode == "100644")
        #expect(files[1].path == "gone.ts")
        #expect(files[1].newPath == nil)
    }

    @Test("Reads a pure rename, which has no hunks and no ---/+++ lines")
    func pureRename() throws {
        let diff = """
            diff --git a/old name.go b/new name.go
            similarity index 100%
            rename from old name.go
            rename to new name.go

            """
        let file = try #require(try UnifiedDiffParser.parse(diff).first)
        #expect(file.status == .renamed)
        #expect(file.oldPath == "old name.go")
        #expect(file.newPath == "new name.go")
        #expect(file.similarity == 100)
        #expect(file.hunks.isEmpty)
    }

    @Test("Strips the tab git appends to a path containing a space")
    func trailingTab() throws {
        let diff = "diff --git a/my file.go b/my file.go\n--- a/my file.go\t\n+++ b/my file.go\t\n@@ -1 +1 @@\n-a\n+b\n"
        #expect(try UnifiedDiffParser.parse(diff).first?.path == "my file.go")
    }

    @Test("Unquotes C-style quoted paths, including UTF-8 octal escapes")
    func quotedPaths() throws {
        let diff = #"""
            diff --git "a/caf\303\251 \"menu\".go" "b/caf\303\251 \"menu\".go"
            --- "a/caf\303\251 \"menu\".go"
            +++ "b/caf\303\251 \"menu\".go"
            @@ -1 +1 @@
            -a
            +b

            """#
        #expect(try UnifiedDiffParser.parse(diff).first?.path == #"café "menu".go"#)
    }

    @Test("Takes a binary file's path from the header")
    func binary() throws {
        let diff = """
            diff --git a/logo.png b/logo.png
            index 5555555..6666666 100644
            Binary files a/logo.png and b/logo.png differ

            """
        let file = try #require(try UnifiedDiffParser.parse(diff).first)
        #expect(file.isBinary)
        #expect(file.path == "logo.png")
        #expect(file.status == .modified)
    }

    @Test("Records a mode-only change")
    func modeOnly() throws {
        let diff = """
            diff --git a/run.sh b/run.sh
            old mode 100644
            new mode 100755

            """
        let file = try #require(try UnifiedDiffParser.parse(diff).first)
        #expect(file.path == "run.sh")
        #expect((file.oldMode, file.newMode) == ("100644", "100755"))
        #expect(file.hunks.isEmpty)
    }

    @Test("Marks the line before a no-newline marker")
    func missingNewline() throws {
        let diff = """
            diff --git a/x b/x
            --- a/x
            +++ b/x
            @@ -1 +1 @@
            -a
            \\ No newline at end of file
            +a
            \\ No newline at end of file

            """
        let lines = try #require(try UnifiedDiffParser.parse(diff).first?.hunks.first?.lines)
        #expect(lines.map(\.isMissingNewline) == [true, true])
    }

    /// Content that looks like diff syntax must stay content: the hunk's
    /// counts, not the line's prefix, decide where it ends.
    @Test("Keeps lines that look like headers inside a hunk")
    func headerLookalikes() throws {
        let diff = """
            diff --git a/notes.md b/notes.md
            --- a/notes.md
            +++ b/notes.md
            @@ -1,2 +1,2 @@
            --- a/not-a-header
            +++ b/not-a-header
             @@ -1 +1 @@

            """
        let files = try UnifiedDiffParser.parse(diff)
        #expect(files.count == 1)
        #expect(files[0].hunks[0].lines.map(\.text) == ["-- a/not-a-header", "++ b/not-a-header", "@@ -1 +1 @@"])
    }

    @Test("Keeps a carriage return as part of its line")
    func crlf() throws {
        let diff = "diff --git a/w.txt b/w.txt\n--- a/w.txt\n+++ b/w.txt\n@@ -1,2 +1,2 @@\n-a\r\n+b\r\n c\r\n"
        let lines = try #require(try UnifiedDiffParser.parse(diff).first?.hunks.first?.lines)
        #expect(lines.map(\.text) == ["a\r", "b\r", "c\r"])
    }

    @Test("Rejects a hunk that ends before its counts are met")
    func truncated() {
        let diff = "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,3 +1,3 @@\n a\n"
        #expect(throws: UnifiedDiffParser.ParseError.truncatedHunk(line: 4)) {
            try UnifiedDiffParser.parse(diff)
        }
    }

    @Test("Parses empty output as no files")
    func empty() throws {
        #expect(try UnifiedDiffParser.parse("").isEmpty)
    }
}
