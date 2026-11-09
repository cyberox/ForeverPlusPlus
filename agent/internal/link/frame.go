// Package link reads the frames Forever++'s Agent Chat writes into a character's AddOns.txt.
//
// The game can't write files, but C_AddOns.SaveAddOns() writes AddOns.txt at once. So the addon
// turns Bits helper addons on and off: helper i holds bit i of a Frame, least significant bit
// first. A frame is Frame bytes: a sequence number (1-255; 0 only in the all-off idle frame that
// starts a session), a flags byte (First, Last, and the payload's length), Payload bytes of the
// message, and a Fletcher-16 checksum (mod 255) of the rest.
//
// ForeverPlusPlus_AgentChat/Lib/AgentLink.lua writes the same format; change both together.
package link

const (
	Bits    = 256 // helper addons, one bit each
	Frame   = 32  // bytes in a frame
	Payload = 28  // message bytes in a frame

	First = 64  // flag: the frame starts a message
	Last  = 128 // flag: the frame ends a message
)

// Checksum is Fletcher-16 (mod 255) of data.
func Checksum(data []byte) (byte, byte) {
	var a, b int
	for _, v := range data {
		a = (a + int(v)) % 255
		b = (b + a) % 255
	}
	return byte(a), byte(b)
}

// FromBits packs Bits on/off states into a frame.
func FromBits(bits []bool) []byte {
	frame := make([]byte, Frame)
	for i, on := range bits {
		if on {
			frame[i/8] |= 1 << (i % 8)
		}
	}
	return frame
}

// Valid says whether a frame's checksum holds. A half-written AddOns.txt usually fails it.
func Valid(frame []byte) bool {
	if len(frame) != Frame {
		return false
	}
	a, b := Checksum(frame[:Frame-2])
	return a == frame[Frame-2] && b == frame[Frame-1]
}

// Reader joins frames into messages. It reads each frame once by its sequence number, so the
// same frame seen twice (AddOns.txt written again for another reason) is ignored.
type Reader struct {
	seq     int // last sequence number read; -1 before the first frame
	buf     []byte
	reading bool
}

// NewReader returns a Reader that takes the first frame it's given as where things stand, not
// as news: a frame left over from before the program started is never read as a message.
func NewReader() *Reader {
	return &Reader{seq: -1}
}

// Read takes a valid frame and returns a message when the frame ends one. dropped is true when
// a frame was missed and a message lost.
func (r *Reader) Read(frame []byte) (message []byte, done bool, dropped bool) {
	seq := int(frame[0])
	if r.seq == -1 {
		r.seq = seq
		return nil, false, false
	}
	if seq == r.seq {
		return nil, false, false
	}
	if seq == 0 { // a new session
		r.seq, r.buf, r.reading = 0, nil, false
		return nil, false, false
	}
	expected := r.seq%255 + 1
	if r.seq == 0 {
		expected = seq // a session's first frame can be any number
	}
	r.seq = seq
	flags := int(frame[1])
	length := flags & 63
	if length > Payload {
		r.buf, r.reading = nil, false
		return nil, false, true
	}
	if seq != expected && r.reading {
		dropped = true
		r.buf, r.reading = nil, false
	}
	if flags&First != 0 {
		r.buf, r.reading = nil, true
	}
	if !r.reading {
		return nil, false, dropped || seq != expected
	}
	r.buf = append(r.buf, frame[2:2+length]...)
	if flags&Last != 0 {
		message, r.buf, r.reading = r.buf, nil, false
		return message, true, dropped
	}
	return nil, false, dropped
}
