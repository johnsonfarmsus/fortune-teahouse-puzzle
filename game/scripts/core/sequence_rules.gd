# SPDX-License-Identifier: AGPL-3.0-or-later
class_name SequenceRules
extends RefCounted
## Pure logic for the sequence puzzle. A sequence is an Array of step ids.


static func is_solved(sequence: Array, order: Array) -> bool:
	if order.is_empty() or sequence.size() != order.size():
		return false
	for i in order.size():
		if str(sequence[i]) != str(order[i]):
			return false
	return true


## The first position (0-based) where the sequence differs from the order, or
## the next empty position when the sequence is a correct but short prefix, or
## -1 when the sequence is complete and right.
static func first_wrong_index(sequence: Array, order: Array) -> int:
	for i in sequence.size():
		if i >= order.size() or str(sequence[i]) != str(order[i]):
			return i
	if sequence.size() < order.size():
		return sequence.size()
	return -1


## How many steps sit at the right position.
static func correct_count(sequence: Array, order: Array) -> int:
	var count := 0
	for i in mini(sequence.size(), order.size()):
		if str(sequence[i]) == str(order[i]):
			count += 1
	return count


## A copy of `sequence` with the item at `from` moved so it ends up at `to`.
static func moved(sequence: Array, from: int, to: int) -> Array:
	var out := sequence.duplicate()
	if from < 0 or from >= out.size():
		return out
	var item: Variant = out[from]
	out.remove_at(from)
	out.insert(clampi(to, 0, out.size()), item)
	return out
