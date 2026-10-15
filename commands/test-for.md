---
description: "Write unit tests for a class file with the test-writer agent (cannot touch production code). Usage: /test-for <path/to/File.cs>"
agent: test-writer
---
Read the file $1 and write unit tests for the class it contains.

If a test file for this class already exists, add the missing cases to it instead of creating a new file.
Cover every public method. Report the tests added and the result of `dotnet test`.
