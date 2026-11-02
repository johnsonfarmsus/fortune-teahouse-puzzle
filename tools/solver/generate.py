# SPDX-License-Identifier: AGPL-3.0-or-later
"""Generate a clue fact set: two anchors plus a four-link chain.

Over a shuffled answer a1..an (a_i is the item at position i):

* two anchors fix the items at both ends: a1 at position 1, an at position n;
* n - 1 links tie each neighbouring pair: a_{i+1} is one position after a_i
  (written either way round, so some links say "before" and some "after").

For n = 5 this is six facts where every 4 give exactly one answer and no 3
do. Anchors anywhere other than the two ends fail the rule, so the generator
always uses the ends; it still verifies the result with the solver.
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from typing import Sequence

from .core import OFFSET, POSITION, Domain, Fact, check_fact_set


@dataclass
class Generated:
    answer: dict[str, int]
    facts: list[tuple[str, Fact]]  # (role, fact); roles: anchor-first, anchor-last, link-1..


def shuffled_answer(items: Sequence[str], rng: random.Random) -> dict[str, int]:
    """A random order that is neither the listed order nor its reverse."""
    items = list(items)
    order = items[:]
    while order in (items, items[::-1]):
        rng.shuffle(order)
    return {item: i + 1 for i, item in enumerate(order)}


def facts_for_answer(answer: dict[str, int], rng: random.Random) -> list[tuple[str, Fact]]:
    order = sorted(answer, key=answer.__getitem__)
    n = len(order)
    facts: list[tuple[str, Fact]] = [
        ("anchor-first", Fact(POSITION, order[0], position=1)),
        ("anchor-last", Fact(POSITION, order[-1], position=n)),
    ]
    for i in range(n - 1):
        left, right = order[i], order[i + 1]
        if rng.random() < 0.5:
            fact = Fact(OFFSET, right, relative_to=left, offset=1)
        else:
            fact = Fact(OFFSET, left, relative_to=right, offset=-1)
        facts.append((f"link-{i + 1}", fact))
    return facts


def generate_facts(
    items: Sequence[str],
    seed: int | None = None,
    answer: dict[str, int] | None = None,
    threshold: int = 4,
) -> Generated:
    """Generate and verify a fact set. Pass ``answer`` to keep a chosen answer."""
    rng = random.Random(seed)
    domain = Domain(tuple(items))
    if answer is None:
        answer = shuffled_answer(items, rng)
    elif not domain.is_assignment(answer):
        raise ValueError("answer must place every item at a distinct position 1..n")
    facts = facts_for_answer(answer, rng)
    keyed = {role: fact for role, fact in facts}
    # The approachable rule depends on which styles carry which facts, so it is
    # checked on the machine file; here any 4 must already be unique.
    results = check_fact_set(domain, keyed, approachable=list(keyed)[:threshold], answer=answer, threshold=threshold)
    failed = [r.rule for r in results if not r.passed]
    if failed:
        raise RuntimeError(f"generated set failed: {', '.join(failed)}")
    return Generated(answer=dict(answer), facts=facts)
