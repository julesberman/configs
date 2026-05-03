---
name: code-walk
description: This skill should be used when the user asks to explain, walk through, or understand a piece of code or a codebase. Triggers on phrases like "explain this", "walk me through", "how does this work", "what does this do", "help me understand", or when the user pastes code without a specific edit request. Optimized for academic and research code — prioritizes mathematical intuition, design intent, and data/shape flow over surface-level line-by-line narration.
---

# code-walkthrough

Produce explanations that build genuine understanding, not just
surface narration. The audience is a researcher or technically
sophisticated reader who can follow math and wants to know *why*,
not just *what*.

## Core philosophy

The goal is to transfer a working mental model, not to describe
syntax. A good walkthrough lets the reader close the file and
correctly predict what would happen if they changed something.

Three layers every explanation must hit:

1. **Intent** — what problem is this solving and why this approach?
2. **Mechanics** — how does it actually work, concretely?
3. **Gotchas** — what's non-obvious, fragile, or easy to misread?

Never do pure line-by-line narration. That's just reading the code
aloud. Narration without insight adds noise.

## Structure

Start with the big picture before touching any code. The reader
needs a map before they can follow a route.

### 1. One-sentence purpose

Lead with what this code *does*, stated plainly. Not what it *is*
(a function, a class, a module) — what it *accomplishes*.

### 2. Mathematical or conceptual framing

Before showing code, state the underlying idea in math or plain
English. If the code implements an algorithm, write out the key
equation or recurrence first. If it's a data transformation, describe
the mapping. The code should feel like a *translation* of something
the reader already understands, not the first thing they encounter.

Example structure:
```
This computes the ELBO, which decomposes as:

    L(θ, φ) = E_q[log p(x|z)] − KL(q(z|x) || p(z))

The first term is reconstruction quality; the second penalizes
the posterior from drifting far from the prior. The code below
evaluates both and returns their sum.
```

### 3. ASCII diagram (when structure or flow is non-trivial)

Use ASCII art to show:
- Data flow (shapes through a pipeline)
- Execution order (especially when it's non-linear or parallel)
- Object relationships (e.g. what calls what, what owns what)
- Tensor shapes at key stages

Keep diagrams tight. Label shapes explicitly — `(B, T, D)` not
"batch of sequences". Show transformations between stages.

Example:
```
inputs (B, T, D)
     │
  LayerNorm
     │
  Attention ──── keys (B, T, D_k)
     │        └─ queries (B, T, D_k)
     │        └─ values (B, T, D_v)
     │
  residual add
     │
  MLP(D → 4D → D)
     │
outputs (B, T, D)
```

### 4. Walk through the code in logical units

Group lines into meaningful chunks — not one comment per line.
Each chunk should correspond to a step in the conceptual story.
Name the chunks. For each:

- State what's happening and why (not just what)
- Call out any non-obvious choices or constraints
- If a shape changes, say so: `# (B, T, D) → (B, T, 1)`

Prefer annotated code blocks over prose when the code is short
enough to show inline:

```python
# project to query/key/value spaces — shared dim D_k
q = self.Wq(x)   # (B, T, D_k)
k = self.Wk(x)   # (B, T, D_k)
v = self.Wv(x)   # (B, T, D_v)

# scaled dot-product attention
# divide by sqrt(D_k) to stabilize gradients at init
scores = jnp.einsum('btd,bsd->bts', q, k) / jnp.sqrt(D_k)
weights = jax.nn.softmax(scores, axis=-1)  # (B, T, T)
```

### 5. Highlight one or two key design decisions

Pick the choices that matter most — things the reader might
question, might want to change, or might stumble on later:

- Why this parameterization over alternatives?
- Why this numerical trick?
- What invariant does this code rely on that isn't stated?
- What would break first if you scaled this up?

These should be labeled clearly:

> **Design choice:** The stop-gradient here prevents the target
> network from receiving gradients through the Bellman target.
> Removing it makes training unstable — the moving target problem.

### 6. Gotcha / non-obvious behavior

End each major section (or the whole walkthrough for short code)
with what's most likely to bite the reader:

- Silent shape broadcasting that masks bugs
- An assumption baked into the math that the code doesn't check
- A performance trap that's invisible until scale
- Behavior that differs from what the name implies

## Calibrate to scope

**Single function:** lead with purpose + math, annotate the body,
one gotcha. Skip the diagram unless data flow is complex.

**Module or file:** overview diagram first, then walk each
component in dependency order (leaves before roots). Call out the
public interface explicitly.

**Whole codebase:** start with the execution entry point and the
main data structures. Describe the "spine" — the critical path
from input to output. Don't try to cover everything; map the
territory and let the reader explore.

## Tone and style

- Write as a knowledgeable colleague explaining at a whiteboard,
  not as documentation.
- Use math when it's cleaner than prose. Don't shy away from
  notation — the reader can handle it.
- Be direct about what's good, fragile, or surprising.
  "This is a standard trick for..." and "This will silently
  misbehave if..." are both useful.
- Skip hedging and filler. No "essentially", "basically", or
  "as you can see".
- Match the depth to the question. "What does this do?" gets a
  paragraph. "Walk me through everything" gets the full structure.

## What not to do

- Don't restate the code in English word-for-word.
- Don't explain language features the reader obviously knows
  (list comprehensions, argument unpacking, etc.).
- Don't add false confidence — if a design choice is unclear or
  looks like it might be a bug, say so.
- Don't pad with background the reader didn't ask for.
- Don't skip the math to seem more accessible. The math is
  the point.
