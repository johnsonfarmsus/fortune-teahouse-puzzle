# SPDX-License-Identifier: AGPL-3.0-or-later
class_name WiringRules
extends RefCounted
## Pure logic for the wiring puzzle. A wiring is {terminal_id: socket_id}; the
## answer has the same shape.


## True when every terminal in the answer is wired to its socket and nothing
## else is wired.
static func is_solved(wires: Dictionary, answer: Dictionary) -> bool:
	if answer.is_empty() or wires.size() != answer.size():
		return false
	for terminal: String in answer:
		if str(wires.get(terminal, "")) != str(answer[terminal]):
			return false
	return true


## Terminals (in answer order) whose wire is missing or goes to the wrong socket.
static func wrong_terminals(wires: Dictionary, answer: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for terminal: String in answer:
		if str(wires.get(terminal, "")) != str(answer[terminal]):
			out.append(terminal)
	return out


## A copy of `wires` with a wire from `terminal` to `socket`. A socket holds one
## wire and a terminal has one wire, so older wires on either end are dropped.
static func with_wire(wires: Dictionary, terminal: String, socket: String) -> Dictionary:
	var out := wires.duplicate()
	for other: String in out.keys():
		if str(out[other]) == socket:
			out.erase(other)
	out[terminal] = socket
	return out
