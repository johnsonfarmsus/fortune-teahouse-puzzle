# SPDX-License-Identifier: AGPL-3.0-or-later
class_name PixelGlyphs
extends RefCounted
## A 3x5 pixel font for placeholder art: letters, digits and a few signs, drawn
## straight into an Image so placeholders need no font file. Each glyph is 15
## characters, row by row, "1" for ink.

const W := 3
const H := 5
const GLYPHS := {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
	"E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
	"I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
	"Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
	"U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111",
	"0": "111101101101111", "1": "010110010010111", "2": "110001010100111", "3": "110001010001110",
	"4": "101101111001001", "5": "111100110001110", "6": "011100111101111", "7": "111001010010010",
	"8": "111101111101111", "9": "111101111001110",
	"?": "110001010000010", "!": "010010010000010", ".": "000000000000010", "-": "000000111000000",
	"+": "000010111010000", "=": "000111000111000", "~": "000011110000000", "\"": "101101000000000",
	"*": "101010101000000", "#": "101111101111101", "o": "000010101010000", "|": "010010010010010",
	"/": "001001010100100", "^": "010101000000000", "@": "010101111100011", "%": "101001010100101",
	",": "000000000010100", ":": "000010000010000",
}


static func has_glyph(ch: String) -> bool:
	return GLYPHS.has(ch) or GLYPHS.has(ch.to_upper())


## Draws `text` centred in `rect`, each font pixel `scale` image pixels big.
## Unknown characters draw as "?".
static func draw_text(image: Image, text: String, rect: Rect2i, ink: Color, scale: int = 1) -> void:
	if text == "":
		return
	var width := text.length() * (W + 1) * scale - scale
	var origin := rect.position + Vector2i((rect.size.x - width) / 2, (rect.size.y - H * scale) / 2)
	for i in text.length():
		draw_glyph(image, text[i], origin + Vector2i(i * (W + 1) * scale, 0), ink, scale)


static func draw_glyph(image: Image, ch: String, at: Vector2i, ink: Color, scale: int = 1) -> void:
	var bits: String = GLYPHS.get(ch, GLYPHS.get(ch.to_upper(), GLYPHS["?"]))
	for row in H:
		for col in W:
			if bits[row * W + col] != "1":
				continue
			for dy in scale:
				for dx in scale:
					var p := at + Vector2i(col * scale + dx, row * scale + dy)
					if p.x >= 0 and p.y >= 0 and p.x < image.get_width() and p.y < image.get_height():
						image.set_pixelv(p, ink)
