package wow

import "testing"

// Go allows a program about 2000 callbacks and never frees one; the check runs every 2 seconds
// while the program does, so it must not make one each time.
func TestWindowCheckRunsForever(t *testing.T) {
	for i := 0; i < 2500; i++ {
		if hasWindow(map[uint32]bool{0: true}) {
			t.Fatal("process 0 has no windows")
		}
	}
}
