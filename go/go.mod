module github.com/jim-collier/zuid/go

go 1.24

require github.com/jim-collier/convert-base-v2/lib v0.0.0

// convertbase sits on an unmerged `lib` branch with no tag, so it is not
// fetchable. Drop this once lib/v0.1.0 exists upstream.
replace github.com/jim-collier/convert-base-v2/lib => ../../../convert-base-v2/github/lib
