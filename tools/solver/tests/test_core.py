# SPDX-License-Identifier: AGPL-3.0-or-later
"""Solver, rule checker, misreading report and generator on toy domains."""

import itertools
import unittest

from solver import Domain, Fact, check_fact_set, count_solutions, generate_facts, misreading_report, solve
from solver.generate import shuffled_answer

ITEMS = ("a", "b", "c", "d", "e")
DOMAIN = Domain(ITEMS)


def pos(item, p):
    return Fact("position", item, position=p)


def off(item, rel, k):
    return Fact("offset", item, relative_to=rel, offset=k)


def chain_set(order, anchors=(0, 4)):
    """Two anchors plus the full chain over ``order`` (items listed by position)."""
    facts = {f"anchor{i}": pos(order[i], i + 1) for i in anchors}
    for i in range(len(order) - 1):
        facts[f"link{i + 1}"] = off(order[i + 1], order[i], 1)
    return facts


def rules(results):
    return {r.rule: r.passed for r in results}


class FactTests(unittest.TestCase):
    def test_offset_semantics(self):
        assignment = {"a": 2, "b": 3, "c": 1, "d": 4, "e": 5}
        self.assertTrue(off("b", "a", 1).holds(assignment))  # b right of a
        self.assertTrue(off("c", "a", -1).holds(assignment))  # c left of a
        self.assertFalse(off("a", "b", 1).holds(assignment))
        self.assertTrue(off("a", "b", -1).as_adjacency().holds(assignment))
        self.assertTrue(Fact("adjacent", "b", relative_to="a").holds(assignment))

    def test_invalid_facts(self):
        with self.assertRaises(ValueError):
            Fact("offset", "a", relative_to="a", offset=1)
        with self.assertRaises(ValueError):
            Fact("offset", "a", relative_to="b", offset=2)
        with self.assertRaises(ValueError):
            Fact("near", "a")
        with self.assertRaises(ValueError):
            solve(DOMAIN, [pos("z", 1)])
        with self.assertRaises(ValueError):
            solve(DOMAIN, [pos("a", 6)])

    def test_round_trip(self):
        for fact in (pos("a", 3), off("b", "c", -1)):
            self.assertEqual(Fact.from_dict(fact.to_dict()), fact)


class SolverTests(unittest.TestCase):
    def test_counts(self):
        self.assertEqual(count_solutions(DOMAIN, []), 120)
        self.assertEqual(count_solutions(DOMAIN, [pos("a", 1)]), 24)
        self.assertEqual(count_solutions(DOMAIN, [off("b", "a", 1)]), 24)
        self.assertEqual(count_solutions(DOMAIN, [pos("a", 5), off("b", "a", 1)]), 0)

    def test_chain_set_passes(self):
        facts = chain_set(("c", "a", "e", "b", "d"))
        answer = {"c": 1, "a": 2, "e": 3, "b": 4, "d": 5}
        approachable = ["anchor0", "anchor4", "link1", "link4"]
        results = check_fact_set(DOMAIN, facts, approachable, answer)
        self.assertTrue(all(r.passed for r in results), rules(results))
        self.assertTrue(all(not r.failing_subsets for r in results))


class BrokenSetTests(unittest.TestCase):
    """Deliberately broken clue sets must fail the right rule."""

    order = ("c", "a", "e", "b", "d")
    answer = {"c": 1, "a": 2, "e": 3, "b": 4, "d": 5}

    def test_anchors_not_at_ends(self):
        for anchors in itertools.combinations(range(5), 2):
            if anchors == (0, 4):
                continue
            facts = chain_set(self.order, anchors)
            appr = list(facts)[:4]
            results = rules(check_fact_set(DOMAIN, facts, appr, self.answer))
            self.assertFalse(results["every-4-unique"] and results["no-3-enough"], anchors)

    def test_position_heavy_set_makes_three_enough(self):
        facts = {
            "p1": pos("c", 1),
            "p2": pos("a", 2),
            "p3": pos("e", 3),
            "p4": pos("b", 4),
            "l1": off("a", "c", 1),
            "l2": off("d", "b", 1),
        }
        results = check_fact_set(DOMAIN, facts, ["p1", "p2", "p3", "p4"], self.answer)
        r = rules(results)
        self.assertFalse(r["no-3-enough"])
        failing = next(x for x in results if x.rule == "no-3-enough").failing_subsets
        self.assertIn("l1+p3+p4", failing)

    def test_wrong_answer(self):
        facts = chain_set(self.order)
        wrong = dict(self.answer, a=3, e=2)
        r = rules(check_fact_set(DOMAIN, facts, list(facts)[:4], wrong))
        self.assertFalse(r["answer-consistent"])
        self.assertTrue(r["every-4-unique"])

    def test_approachable_not_unique(self):
        # anchors at positions 1 and 3: these four leave the last two items open
        facts = chain_set(self.order, anchors=(0, 2))
        r = rules(check_fact_set(DOMAIN, facts, ["anchor0", "anchor2", "link1", "link2"], self.answer))
        self.assertFalse(r["approachable-unique"])
        # the wrong number of approachable clues also fails
        facts = chain_set(self.order)
        r = rules(check_fact_set(DOMAIN, facts, ["anchor0", "link1"], self.answer))
        self.assertFalse(r["approachable-unique"])

    def test_random_sets_usually_fail(self):
        # Sanity check of the design note: arbitrary six facts rarely work.
        import random

        rng = random.Random(7)
        passing = 0
        for _ in range(40):
            facts = {}
            for i in range(6):
                if rng.random() < 0.3:
                    item = rng.choice(ITEMS)
                    facts[f"f{i}"] = pos(item, self.answer[item])
                else:
                    a, b = rng.sample(ITEMS, 2)
                    if abs(self.answer[a] - self.answer[b]) != 1:
                        b = next(x for x in ITEMS if abs(self.answer[x] - self.answer[a]) == 1)
                    facts[f"f{i}"] = off(a, b, self.answer[a] - self.answer[b])
            results = check_fact_set(DOMAIN, facts, list(facts)[:4], self.answer)
            passing += all(r.passed for r in results)
        self.assertLess(passing, 10)


class MisreadingTests(unittest.TestCase):
    def test_end_links_are_robust_for_the_approachable_four(self):
        facts = chain_set(("c", "a", "e", "b", "d"))
        report = misreading_report(DOMAIN, facts, ["anchor0", "anchor4", "link1", "link4"])
        self.assertEqual({m["clue"] for m in report}, {"link1", "link2", "link3", "link4"})
        self.assertFalse(any(m["breaks_approachable"] for m in report))
        for m in report:
            self.assertEqual(m["subsets_containing_clue"], 10)

    def test_middle_link_in_approachable_four_is_fragile(self):
        facts = chain_set(("c", "a", "e", "b", "d"))
        approachable = ["anchor0", "anchor4", "link1", "link3"]
        report = {m["clue"]: m for m in misreading_report(DOMAIN, facts, approachable)}
        self.assertTrue(report["link3"]["breaks_approachable"])


class GeneratorTests(unittest.TestCase):
    def test_many_seeds(self):
        for seed in range(30):
            g = generate_facts(ITEMS, seed=seed)
            order = sorted(g.answer, key=g.answer.__getitem__)
            self.assertNotEqual(tuple(order), ITEMS)
            self.assertNotEqual(tuple(order), ITEMS[::-1])
            roles = [role for role, _ in g.facts]
            self.assertEqual(roles, ["anchor-first", "anchor-last", "link-1", "link-2", "link-3", "link-4"])
            facts = {role: fact for role, fact in g.facts}
            self.assertEqual(solve(DOMAIN, facts.values()), [g.answer])

    def test_deterministic(self):
        self.assertEqual(generate_facts(ITEMS, seed=3).answer, generate_facts(ITEMS, seed=3).answer)

    def test_keeps_given_answer(self):
        answer = {"a": 2, "b": 1, "c": 5, "d": 3, "e": 4}
        self.assertEqual(generate_facts(ITEMS, seed=1, answer=answer).answer, answer)
        with self.assertRaises(ValueError):
            generate_facts(ITEMS, answer={"a": 1})

    def test_shuffle_never_identity(self):
        import random

        rng = random.Random(0)
        for _ in range(50):
            order = sorted(shuffled_answer(ITEMS, rng).items(), key=lambda kv: kv[1])
            self.assertNotEqual(tuple(k for k, _ in order), ITEMS)


if __name__ == "__main__":
    unittest.main()
