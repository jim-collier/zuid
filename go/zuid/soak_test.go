//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	SPDX-License-Identifier: Apache-2.0

package zuid_test

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"runtime/pprof"
	"strings"
	"sync"
	"testing"

	"github.com/jim-collier/zuid/go/zuid"
)

// The rounds before the first reading, and again before the second. A round
// is about 120 ms, nearly all of it in the 2 calls to New.
const soakRounds = 80

// Bytes of growth allowed between the readings. Quiet runs moved by up to
// 64 KB, down as often as up.
const soakMarginBytes = 128 << 10

// Everything a caller does, round after round: a new generator, every vector,
// the refusals, and live identifiers from several goroutines at once. The heap
// and the goroutine count after round N and round 2N have to match, within
// the margin. The first rounds fill caches, which is why it's N against 2N.
//
// Skipped unless ZUID_SOAK_DIR names a folder for its 2 heap profiles, as
// cicd.bash --leakcheck does. go tool pprof -base heap-n.pprof heap-2n.pprof
// shows what grew.
//
// test-id: de5cg
func TestSoak(t *testing.T) {
	dir := os.Getenv("ZUID_SOAK_DIR")
	if dir == "" {
		t.Skip("ZUID_SOAK_DIR isn't set; cicd.bash --leakcheck sets it")
	}
	vectors := loadVectors(t)

	var heapN uint64
	var goroutinesN int
	for round := 1; round <= 2*soakRounds; round++ {
		soakRound(t, vectors)
		if round == soakRounds {
			heapN, goroutinesN = soakReading(t, filepath.Join(dir, "heap-n.pprof"))
		}
	}
	heap2N, goroutines2N := soakReading(t, filepath.Join(dir, "heap-2n.pprof"))

	summary := fmt.Sprintf("heap in use after round %d: %d bytes, after round %d: %d bytes\ngoroutines: %d, then %d\n",
		soakRounds, heapN, 2*soakRounds, heap2N, goroutinesN, goroutines2N)
	if err := os.WriteFile(filepath.Join(dir, "summary.txt"), []byte(summary), 0o644); err != nil {
		t.Fatalf("write summary: %v", err)
	}
	t.Log(summary)
	if goroutines2N > goroutinesN {
		t.Errorf("%d goroutines more after round %d than after round %d", goroutines2N-goroutinesN, 2*soakRounds, soakRounds)
	}
	if heap2N > heapN && heap2N-heapN > soakMarginBytes {
		t.Errorf("the heap grew %d bytes, past the %d byte margin", heap2N-heapN, soakMarginBytes)
	}
}

func soakRound(t *testing.T, vectors []vector) {
	t.Helper()
	generator, err := zuid.New()
	if err != nil {
		t.Fatalf("new generator: %v", err)
	}
	for _, v := range vectors {
		got, err := replayVector(t, generator, v)
		if err != nil || got != v.expected {
			t.Fatalf("line %d (%s): got %q, %v; want %q", v.line, v.name, got, err, v.expected)
		}
	}
	for _, req := range []zuid.Request{
		{Base: "nonesuch"},
		{Format: "%d%"},
		{Precision: 2},
		{Format: "%h", HashChars: 65},
		{Format: "%h", Salt: strings.Repeat("s", zuid.MaxSaltBytes+1)},
		{Base: "bytes"},
	} {
		if _, err := generator.Generate(req); err == nil {
			t.Fatalf("%+v: want an error, got none", req)
		}
	}

	live, err := zuid.New()
	if err != nil {
		t.Fatalf("new generator: %v", err)
	}
	var wg sync.WaitGroup
	errs := make(chan error, 4)
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for _, base := range zuid.CuratedBases() {
				if _, err := live.Generate(zuid.Request{Format: "%d%h%u%f%m%g%r", Base: base}); err != nil {
					errs <- fmt.Errorf("live, base %s: %w", base, err)
					return
				}
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}
}

// One GC can leave garbage a second one clears, so the reading takes 2. The
// stats come first, since writing the profile allocates.
func soakReading(t *testing.T, path string) (uint64, int) {
	t.Helper()
	runtime.GC()
	runtime.GC()
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	goroutines := runtime.NumGoroutine()
	file, err := os.Create(path)
	if err != nil {
		t.Fatalf("heap profile: %v", err)
	}
	defer file.Close()
	if err := pprof.WriteHeapProfile(file); err != nil {
		t.Fatalf("heap profile: %v", err)
	}
	return stats.HeapInuse, goroutines
}
