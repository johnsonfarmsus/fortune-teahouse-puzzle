# SPDX-License-Identifier: AGPL-3.0-or-later
class_name SfxSynth
extends RefCounted
## Builds retro sound effects in code (PLAN.md D12): no audio files are
## committed. A definition from data/sfx.json is
##   {wave: square|triangle|saw|sine|noise, freq, freq_end?, notes?, note_len?,
##    duration, attack?, decay?, volume?, duty?, vibrato?, loop?, lfo?, seed?}
## `notes` plays a little tune (frequencies in Hz, `note_len` seconds each)
## instead of one slide from `freq` to `freq_end`. `lfo` swells the volume
## (Hz) for ambient loops; `loop` makes the stream loop. Output is 16-bit mono.

const WAVES: Array[String] = ["square", "triangle", "saw", "sine", "noise"]
const DEFAULT_RATE := 22050
const MAX_SECONDS := 6.0


## The samples as floats in -1..1 (tests read these).
static func samples(def: Dictionary, rate: int = DEFAULT_RATE) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var notes: Array = def.get("notes", [])
	var note_len := float(def.get("note_len", 0.06))
	var duration := float(def.get("duration", 0.1))
	if not notes.is_empty():
		duration = note_len * notes.size()
	duration = clampf(duration, 0.005, MAX_SECONDS)
	var count := int(duration * rate)
	out.resize(count)
	var wave := str(def.get("wave", "square"))
	var freq := float(def.get("freq", 440.0))
	var freq_end := float(def.get("freq_end", freq))
	var volume := clampf(float(def.get("volume", 0.4)), 0.0, 1.0)
	var duty := clampf(float(def.get("duty", 0.5)), 0.05, 0.95)
	var attack := maxf(float(def.get("attack", 0.005)), 0.0005)
	var decay := maxf(float(def.get("decay", duration)), 0.001)
	var vibrato := float(def.get("vibrato", 0.0))
	var lfo := float(def.get("lfo", 0.0))
	var looped := bool(def.get("loop", false))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(def.get("seed", 7))
	var phase := 0.0
	var noise_value := 0.0
	var noise_hold := 0
	for n in count:
		var t := float(n) / rate
		var f := freq
		var env := 1.0
		if not notes.is_empty():
			var index := mini(int(t / note_len), notes.size() - 1)
			f = float(notes[index])
			var local := t - index * note_len
			env = minf(1.0, local / attack) * clampf(1.0 - local / note_len, 0.0, 1.0)
		else:
			f = lerpf(freq, freq_end, t / duration)
			if looped:
				env = 1.0
			else:
				env = minf(1.0, t / attack) * clampf(1.0 - (t - attack) / decay, 0.0, 1.0)
		if vibrato > 0.0:
			f *= 1.0 + 0.03 * sin(TAU * vibrato * t)
		if lfo > 0.0:
			env *= 0.55 + 0.45 * sin(TAU * lfo * t)
		if f <= 0.0:
			out[n] = 0.0  # a rest in a tune
			continue
		phase = fmod(phase + f / rate, 1.0)
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if phase < duty else -1.0
			"triangle":
				s = 4.0 * absf(phase - 0.5) - 1.0
			"saw":
				s = 2.0 * phase - 1.0
			"sine":
				s = sin(TAU * phase)
			"noise":
				# Sample-and-hold noise: the hold length follows the pitch.
				if noise_hold <= 0:
					noise_value = rng.randf_range(-1.0, 1.0)
					noise_hold = maxi(1, int(rate / maxf(f, 1.0)))
				noise_hold -= 1
				s = noise_value
		out[n] = s * env * volume
	if looped and count > 64:
		# Fade the seam so the loop does not click.
		for n in 64:
			var k := float(n) / 64.0
			out[n] *= k
			out[count - 1 - n] *= k
	return out


static func build(def: Dictionary, rate: int = DEFAULT_RATE) -> AudioStreamWAV:
	var floats := samples(def, rate)
	var bytes := PackedByteArray()
	bytes.resize(floats.size() * 2)
	for n in floats.size():
		bytes.encode_s16(n * 2, int(clampf(floats[n], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	if bool(def.get("loop", false)):
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = floats.size()
	return stream
