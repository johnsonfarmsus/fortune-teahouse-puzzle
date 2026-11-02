# SPDX-License-Identifier: AGPL-3.0-or-later
"""Generic matching solver and the clue-set rules.

Rules checked for one machine (``threshold`` k is 4 for six clues):

* every k-subset of the clues has exactly one solution;
* every (k-1)-subset has at least two solutions;
* the approachable clues alone have exactly one solution;
* all clues hold for the declared answer and it is the only solution.

Results name clue ids and subset ids only, never items, positions or facts,
so they are safe to print in public CI logs.
"""

from __future__ import annotations

import itertools
from dataclasses import dataclass
from typing import Iterable, Mapping, Sequence

Assignment = dict[str, int]

POSITION = "position"
OFFSET = "offset"
ADJACENT = "adjacent"  # only used for the misreading report


@dataclass(frozen=True)
class Fact:
    """One machine-readable clue fact.

    position: ``item`` is at ``position`` (1-based).
    offset:   pos(item) == pos(relative_to) + offset, with offset +1 (item is
              immediately right of / after / below relative_to) or -1 (item is
              immediately left of / before / above relative_to).
    adjacent: |pos(item) - pos(relative_to)| == 1 (the misreading of an offset).
    """

    kind: str
    item: str
    position: int | None = None
    relative_to: str | None = None
    offset: int | None = None

    def __post_init__(self) -> None:
        if self.kind == POSITION:
            if self.position is None or self.relative_to is not None:
                raise ValueError("position fact needs a position and no relative_to")
        elif self.kind == OFFSET:
            if self.relative_to is None or self.offset not in (1, -1):
                raise ValueError("offset fact needs relative_to and an offset of +1 or -1")
            if self.relative_to == self.item:
                raise ValueError("offset fact cannot relate an item to itself")
        elif self.kind == ADJACENT:
            if self.relative_to is None or self.relative_to == self.item:
                raise ValueError("adjacent fact needs a different relative_to")
        else:
            raise ValueError(f"unknown fact kind {self.kind!r}")

    def holds(self, assignment: Mapping[str, int]) -> bool:
        pos = assignment[self.item]
        if self.kind == POSITION:
            return pos == self.position
        other = assignment[self.relative_to]  # type: ignore[index]
        if self.kind == OFFSET:
            return pos == other + self.offset  # type: ignore[operator]
        return abs(pos - other) == 1

    def items(self) -> tuple[str, ...]:
        if self.relative_to is None:
            return (self.item,)
        return (self.item, self.relative_to)

    def as_adjacency(self) -> "Fact":
        """The "either order" misreading of an offset fact."""
        if self.kind != OFFSET:
            raise ValueError("only offset facts have an adjacency misreading")
        return Fact(ADJACENT, self.item, relative_to=self.relative_to)

    @classmethod
    def from_dict(cls, data: Mapping[str, object]) -> "Fact":
        kind = data.get("kind")
        if kind == POSITION:
            return cls(POSITION, str(data["item"]), position=_as_int(data["position"]))
        if kind == OFFSET:
            return cls(
                OFFSET,
                str(data["item"]),
                relative_to=str(data["relative_to"]),
                offset=_as_int(data["offset"]),
            )
        raise ValueError(f"unknown fact kind {kind!r}")

    def to_dict(self) -> dict[str, object]:
        if self.kind == POSITION:
            return {"kind": POSITION, "item": self.item, "position": self.position}
        out: dict[str, object] = {"kind": self.kind, "item": self.item, "relative_to": self.relative_to}
        if self.kind == OFFSET:
            out["offset"] = self.offset
        return out


def _as_int(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"expected an integer, got {value!r}")
    return value


@dataclass(frozen=True)
class Domain:
    """Items to place and the ordered positions 1..n they go to (n = len(items))."""

    items: tuple[str, ...]

    def __post_init__(self) -> None:
        if len(set(self.items)) != len(self.items):
            raise ValueError("domain items must be unique")
        if not 2 <= len(self.items) <= 8:
            raise ValueError("domain size must be 2 to 8 for brute force")

    @property
    def size(self) -> int:
        return len(self.items)

    def assignments(self) -> Iterable[Assignment]:
        for perm in itertools.permutations(range(1, self.size + 1)):
            yield dict(zip(self.items, perm))

    def validate_fact(self, fact: Fact) -> None:
        for item in fact.items():
            if item not in self.items:
                raise ValueError(f"fact names an unknown item {item!r}")
        if fact.kind == POSITION and not 1 <= fact.position <= self.size:  # type: ignore[operator]
            raise ValueError(f"fact position {fact.position} is out of range")

    def is_assignment(self, answer: Mapping[str, int]) -> bool:
        return set(answer) == set(self.items) and sorted(answer.values()) == list(
            range(1, self.size + 1)
        )


def solve(domain: Domain, facts: Iterable[Fact], limit: int | None = None) -> list[Assignment]:
    """All assignments satisfying every fact (stop early once ``limit`` are found)."""
    facts = list(facts)
    for fact in facts:
        domain.validate_fact(fact)
    found: list[Assignment] = []
    for assignment in domain.assignments():
        if all(f.holds(assignment) for f in facts):
            found.append(assignment)
            if limit is not None and len(found) >= limit:
                break
    return found


def count_solutions(domain: Domain, facts: Iterable[Fact], limit: int | None = None) -> int:
    return len(solve(domain, facts, limit))


def subset_id(clue_ids: Iterable[str]) -> str:
    """Stable, answer-free name for a subset of clues."""
    return "+".join(sorted(clue_ids))


@dataclass
class RuleResult:
    rule: str
    passed: bool
    detail: str
    failing_subsets: list[str]

    def to_dict(self) -> dict[str, object]:
        return {
            "rule": self.rule,
            "passed": self.passed,
            "detail": self.detail,
            "failing_subsets": self.failing_subsets,
        }


def check_fact_set(
    domain: Domain,
    facts: Mapping[str, Fact],
    approachable: Sequence[str],
    answer: Mapping[str, int] | None = None,
    threshold: int = 4,
) -> list[RuleResult]:
    """Apply the clue-set rules to one machine's facts, keyed by clue id."""
    ids = sorted(facts)
    results: list[RuleResult] = []

    full = solve(domain, facts.values(), limit=2)
    if answer is not None:
        ok = (
            domain.is_assignment(answer)
            and all(f.holds(answer) for f in facts.values())
            and len(full) == 1
            and full[0] == dict(answer)
        )
        results.append(
            RuleResult(
                "answer-consistent",
                ok,
                "every clue holds for the declared answer and it is the only solution"
                if ok
                else "the declared answer is not the unique solution of all clues",
                [] if ok else [subset_id(ids)],
            )
        )
    else:
        ok = len(full) == 1
        results.append(
            RuleResult(
                "full-set-unique",
                ok,
                "all clues together have exactly one solution" if ok else "all clues together are not unique",
                [] if ok else [subset_id(ids)],
            )
        )

    subsets_k = list(itertools.combinations(ids, threshold))
    bad_k = [
        subset_id(sub)
        for sub in subsets_k
        if count_solutions(domain, (facts[c] for c in sub), limit=2) != 1
    ]
    results.append(
        RuleResult(
            f"every-{threshold}-unique",
            bool(subsets_k) and not bad_k,
            f"{len(subsets_k) - len(bad_k)} of {len(subsets_k)} {threshold}-subsets have exactly one solution",
            bad_k,
        )
    )

    k1 = threshold - 1
    subsets_k1 = list(itertools.combinations(ids, k1))
    bad_k1 = [
        subset_id(sub)
        for sub in subsets_k1
        if count_solutions(domain, (facts[c] for c in sub), limit=2) < 2
    ]
    results.append(
        RuleResult(
            f"no-{k1}-enough",
            not bad_k1,
            f"{len(subsets_k1) - len(bad_k1)} of {len(subsets_k1)} {k1}-subsets leave at least two solutions",
            bad_k1,
        )
    )

    appr = sorted(approachable)
    unknown = [c for c in appr if c not in facts]
    if unknown or len(appr) != threshold:
        results.append(
            RuleResult(
                "approachable-unique",
                False,
                f"expected {threshold} approachable clues, got {len(appr)}"
                + (f" (unknown ids: {', '.join(unknown)})" if unknown else ""),
                [subset_id(appr)],
            )
        )
    else:
        n = count_solutions(domain, (facts[c] for c in appr), limit=2)
        results.append(
            RuleResult(
                "approachable-unique",
                n == 1,
                "the approachable clues alone have "
                + ("exactly one solution" if n == 1 else "more than one solution" if n > 1 else "no solution"),
                [] if n == 1 else [subset_id(appr)],
            )
        )
    return results


def misreading_report(
    domain: Domain,
    facts: Mapping[str, Fact],
    approachable: Sequence[str] = (),
    threshold: int = 4,
) -> list[dict[str, object]]:
    """Read each offset clue as plain adjacency ("either order") and list broken subsets.

    Informational, never failing: a clue whose misreading breaks many subsets
    carries a lot of weight, so its direction word must be unmistakable.
    """
    ids = sorted(facts)
    appr_id = subset_id(approachable) if approachable else None
    out: list[dict[str, object]] = []
    for cid in ids:
        fact = facts[cid]
        if fact.kind != OFFSET:
            continue
        misread = dict(facts)
        misread[cid] = fact.as_adjacency()
        containing = [sub for sub in itertools.combinations(ids, threshold) if cid in sub]
        broken = [
            subset_id(sub)
            for sub in containing
            if count_solutions(domain, (misread[c] for c in sub), limit=2) != 1
        ]
        out.append(
            {
                "clue": cid,
                "subsets_containing_clue": len(containing),
                "broken_subsets": broken,
                "breaks_approachable": appr_id in broken if appr_id else False,
            }
        )
    return out
