# SPDX-License-Identifier: AGPL-3.0-or-later
# Brute-force check of the sample Cookie Machine clue set in DESIGN.md:
# any 4 of 6 clues give one answer, no 3 do, plus misreading tests,
# character counts and the pack arithmetic. Run: python3 -I verify_sample_clues.py
import itertools, codecs
J=["sugar","flour","butter","vanilla","egg"]
perms=[dict(zip(J,p)) for p in itertools.permutations(range(1,6))]
print("perms",len(perms))
print("ROT13:",codecs.decode("Fhtne vf va wne bar.","rot13"))
base={
 1:lambda s:s["sugar"]==1,
 2:lambda s:s["butter"]==s["vanilla"]+1,
 3:lambda s:s["flour"]==s["sugar"]+1,
 4:lambda s:s["egg"]==len("Linux"),
 5:lambda s:s["vanilla"]==s["flour"]+1,
 6:lambda s:s["butter"]==s["egg"]-1,
}
def run(C,label):
    print("==",label)
    full=[s for s in perms if all(C[i](s) for i in C)]
    print("full solutions:",[tuple(s[j] for j in J) for s in full])
    for k in (3,4,5,6):
        cnts={}
        for sub in itertools.combinations(sorted(C),k):
            cnts[sub]=sum(all(C[i](s) for i in sub) for s in perms)
        if k==4:
            bad=[(a,b) for a,b in cnts.items() if b!=1]
            print("4-subsets: all exactly 1?",not bad,"viol:",bad, "counts:",sorted(set(cnts.values())))
        elif k==3:
            bad=[(a,b) for a,b in cnts.items() if b<2]
            print("3-subsets: all >=2?",not bad,"viol:",bad,"min count",min(cnts.values()))
            if label=="formal": print({a:b for a,b in cnts.items()})
        else:
            print(f"{k}-subsets counts:",sorted(set(cnts.values())))
    return full
run(base,"formal")
adj=lambda a,b:(lambda s:abs(s[a]-s[b])==1)
alt=dict(base); alt[3]=adj("flour","sugar"); run(alt,"penguin adjacent either order")
alt=dict(base); alt[6]=adj("butter","egg"); run(alt,"hardware adjacent either order")
alt=dict(base); alt[3]=adj("flour","sugar"); alt[6]=adj("butter","egg"); run(alt,"both adjacent")
alt=dict(base); alt[2]=adj("butter","vanilla"); run(alt,"poem adjacent")
alt=dict(base); alt[5]=adj("vanilla","flour"); run(alt,"code adjacent")
# 0-based code reading: jar.index 0-based, relation same offset -> identical. Check jar numbering shift
# Reading where "egg's jar"=5 but code interpreted with 0-based positions numbers? not affecting relative.
# Character counts
F={
"Security":"ROT13 says: Fhtne vf va wne bar. Lucky word: CIPHER",
"Poem":"Vanilla came first, then butter so near: one jar to the right, and the butter is here. Lucky word: SPRINKLE",
"Penguin":"Like a penguin and her chick, sugar and flour stand close: sugar on the left, flour just beside. Lucky word: HUDDLE",
"Open source":"Count the letters in the kernel Linus Torvalds wrote. That number is the egg's jar. Lucky word: TUX",
"Code":'`assert jar.index("vanilla") == jar.index("flour") + 1` Lucky word: PATCH',
"Hardware":"Read the jars like resistor bands, left to right: butter's band comes just before egg's. Lucky word: SOLDER",
}
claim={"Security":51,"Poem":107,"Penguin":115,"Open source":99,"Code":71,"Hardware":107}
for k,v in F.items():
    nb=v.replace("`","")
    print(f"{k:12} with-ticks={len(v)} no-ticks={len(nb)} claimed={claim[k]}")
A="Fix the gnu's fortune machine! Play at fortune.ataary.com  Lucky numbers: 3 1 4 1 5"
B="Fix the gnu's fortune machine! Play at fortune.ataary.com  Lucky numbers: 9 2 6 5 3"
print("A",len(A),"B",len(B), "all<140:",all(len(x)<140 for x in list(F.values())+[A,B]))
print("single-space A",len(A.replace("  "," ")))
# Arithmetic
print("fortunes",2*9,"copies/fortune",100/18,"per crew",100/3,"after hold10",90/18,"per crew",90/3)
# pi
import decimal
digits="3"+"14159265358979"
print("pi digits 1-11:",digits[:11], "claimed","31415"+"92653"+"?", )
print("A+B concat:", "31415"+"92653", "pi first 10:", digits[:10])
print("claimed string '3.14159 26535' vs actual pi 3.14159 26535 89793:", "3.14159 26535 89793")
print("Pack A digits '31415', Pack B '92653' -> 3.1415 92653 ; doc writes 3.14159 26535")
