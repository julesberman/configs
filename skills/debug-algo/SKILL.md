---
name: debug-algo
description: Audit research-oriented numerical and deep learning code for mathematical, algorithmic, and implementation bugs. Use whenever the user asks to debug, audit, review, sanity-check, or "find bugs in" ML / numerical / scientific computing code — especially model implementations, loss functions, training loops, attention mechanisms, normalization, samplers, optimizers, or any code implementing an algorithm from a paper. Trigger even when the user just says things like "something is off with my training", "my loss looks wrong", "is this implementation correct", "compare this to the paper", or pastes a model/loss/forward function and asks for a look. This skill is READ-ONLY: it identifies bugs and produces a ranked audit report. It does NOT write fixes, tests, or verification code. It is strictly about correctness of math and algorithm, not software engineering, performance, or safety.
---

# Numerical & Algorithmic Debug Audit

This skill audits numerical / ML / scientific code for **correctness bugs only** — places where the implementation silently computes the wrong thing relative to the algorithm it claims to implement. You are a reviewer, not a fixer. Do not edit code, do not write tests, do not propose patches. Produce a ranked audit report.

The defining property of bugs in this domain is that **the code runs fine and produces plausible-looking numbers while being mathematically wrong**. Shape broadcasting silently does the wrong thing. A `view` instead of `transpose` mixes information across the batch dimension and the network learns to ignore it. An off-by-one in an autoregressive mask leaks the target into the input. Loss is computed before masking padding tokens. The normalization axis is wrong but the model still trains. Your job is to hunt these.

## Step 1 — Establish context (ALWAYS ASK FIRST)

Before reading the code in depth, ask the user two questions in a single message. Do not skip this — the answers determine how you audit.

**Question 1 — Reference material.** Ask whether the user has any of the following, and to share whatever they have:
- A paper, preprint, blog post, or written description of the algorithm being implemented
- A reference implementation (link to a repo, file, or function known to be correct)
- Neither — in which case you will rely on your own knowledge of the algorithm and, if useful, search the web for canonical sources

Make clear that more reference material means a sharper audit. With a paper you can cite equations; with a reference implementation you can diff line-by-line in your head; with neither you are working from priors.

**Question 2 — Scope.** Ask where to focus. Offer concrete options based on what you can see in the codebase:
- A specific function or module (e.g. "just the attention block", "just the loss")
- A specific pipeline stage (data loading, forward pass, loss computation, backward/optimizer step, sampling/inference)
- The full training step end-to-end
- Global audit across the whole codebase

Suggest a default. For a single pasted file, default to "the whole file". For a repo, default to "the forward pass and loss" unless the user gives a hint about where they suspect the bug.

Wait for answers before proceeding. If the user has reference material, read it (or fetch the paper/repo) before auditing.

## Step 2 — Audit against the bug taxonomy

Read the in-scope code carefully. For each section, mentally walk through what the tensors *are* — their shapes, dtypes, semantic meaning of each axis, and what mathematical object they represent — and compare against what the algorithm requires. The taxonomy below is what to hunt for. It is not exhaustive; use it as a prompt, not a checklist to mechanically tick off.

### Tensor shape, axis, and broadcasting bugs
The single largest source of silent correctness bugs.
- **Wrong reduction axis.** `mean`, `sum`, `softmax`, `logsumexp`, `norm`, `var` over the wrong dim. Especially dangerous when the wrong axis happens to have a plausible size.
- **`view`/`reshape` instead of `transpose`/`permute`.** These are not interchangeable. `view` after a transpose-shaped operation will scramble data across what should be independent axes — most catastrophically across the batch dimension, where the network will learn to route around it and you will never notice. Whenever you see `.view(B, H, T, D)` or `.reshape(...)` after a multi-head split or attention, check whether a `transpose` was needed instead.
- **Silent broadcasting.** A tensor of shape `(B, T)` added to one of shape `(B, 1, T)` will broadcast to `(B, T, T)` without complaint. Look for arithmetic between tensors whose shapes you cannot immediately reconcile in your head.
- **Mask shape mismatch.** Attention masks, padding masks, and loss masks broadcast in ways that look right but apply along the wrong axis.
- **Batch-dimension leakage.** Any operation that could mix information across the batch dimension is a five-alarm fire. Look at every reshape, every flatten, every einsum, every matmul whose left-hand side touches B.
- **Off-by-one in slicing.** `x[:-1]` vs `x[1:]` for autoregressive shifting is the classic. Inputs and targets misaligned by one position is *the* canonical autoregressive bug — the model "trains" by reading the answer.

### Normalization bugs
- **Wrong axis for LayerNorm / RMSNorm / GroupNorm / BatchNorm.** LayerNorm normalizes over the *feature* dimension (last), not the sequence or batch dimension. Easy to get wrong with custom implementations.
- **Normalizing statistics computed with the wrong reduction.** `mean` and `var` axes must match.
- **Train/eval mode mismatch for BatchNorm and Dropout.** Running stats updated at eval, dropout active at eval, etc.
- **Missing or doubled normalization.** Pre-norm vs post-norm transformer variants applied inconsistently. Output projection after attention normalized when it shouldn't be.
- **Wrong normalization constant.** `1/sqrt(d_k)` in attention — is `d_k` the per-head dim or the full model dim? Off by a factor of `sqrt(num_heads)` is a common silent bug.
- **Bessel correction (`unbiased=True/False`).** Matters for small sample sizes and for matching reference implementations exactly.

### Loss function bugs
- **Wrong reduction.** `mean` vs `sum` vs `none`. `mean` over a tensor that includes padding tokens divides by the wrong denominator.
- **Padding/ignore tokens not masked out.** Cross-entropy over padded positions silently inflates or deflates the loss.
- **Logits vs probabilities confusion.** Passing softmax outputs to a loss that expects logits, or vice versa. `BCELoss` vs `BCEWithLogitsLoss`. Double softmax.
- **Label smoothing applied wrong** (to one-hot rather than as target distribution; wrong epsilon split).
- **Wrong sign.** Negative log-likelihood missing the negative. KL divergence with arguments swapped (KL is asymmetric).
- **Reduction over wrong axis** before the final scalar.
- **Loss computed on wrong slice.** Especially in seq2seq: computing loss including the BOS token, or excluding the EOS token.
- **Detached tensor in the loss.** A `.detach()` somewhere in the loss path silently kills gradients to part of the model.

### Gradient flow and backward bugs
- **In-place operations** (`x += y`, `x.relu_()`, indexing assignment) breaking autograd silently. PyTorch will sometimes warn, often won't.
- **`torch.no_grad()` / `with torch.inference_mode()`** wrapping something that needs gradients.
- **Detached tensors.** `.detach()`, `.data`, `.numpy()`, `.item()` cutting the graph.
- **Stop-gradient asymmetries** in algorithms like target networks, EMA teachers, contrastive losses, GANs — these are *intentional* in the algorithm, so check whether the implementation matches the paper's stop-gradient placement exactly.
- **`zero_grad()` missing or in the wrong place.** Gradients accumulate across steps unexpectedly.
- **Optimizer constructed before model moved to device** or before parameters that should be optimized are added — optimizer holds references to the wrong tensors.
- **Clipping the wrong thing.** Clipping the loss instead of the gradients. Clipping by norm vs by value confusion. Clipping after the optimizer step.

### Numerical stability bugs
- **`log(softmax(x))` instead of `log_softmax(x)`.** The fused version is numerically stable; the unfused version is not.
- **`exp` of large values without subtracting the max.** Standard logsumexp trick missing.
- **Division by something that can be zero** without epsilon, or with epsilon added in the wrong place (inside vs outside the sqrt).
- **`sqrt(0)` gradient is `inf`.** Always `sqrt(x + eps)`, not `sqrt(x) + eps`.
- **Mixed precision (fp16/bf16) overflow** in attention scores, loss accumulators, or running statistics that should be in fp32.
- **Catastrophic cancellation** in `a - b` where `a ≈ b`.
- **NaN/Inf propagation** through masked-out positions that aren't actually masked in the gradient.

### Algorithm-specific correctness
This is where the reference material from Step 1 matters most. For whatever algorithm the code implements, check the implementation against what you know (or can find) about the canonical version. Examples of what to verify:
- **Transformers / attention.** Causal mask shape and direction (upper vs lower triangular). Mask applied as `-inf` before softmax, not `0` after. RoPE frequency base and the cos/sin application order. Position IDs starting from 0. KV cache indexing. Multi-head split direction (`(B,T,H,D)` vs `(B,H,T,D)`). Scaling by `sqrt(d_head)` not `sqrt(d_model)`.
- **Diffusion models.** Noise schedule conventions (β vs ᾱ vs σ), v-prediction vs ε-prediction vs x0-prediction matching the loss target, sign of the noise added at each step, EMA update direction, classifier-free guidance scale applied to the right delta.
- **RL.** GAE sign and discount conventions, value bootstrap on terminal vs truncated states (these are different!), advantage normalization scope, importance-sampling ratio direction, target network update timing, log-prob of the *taken* action vs the policy distribution.
- **Optimizers (custom).** Bias correction in Adam, momentum buffer initialization, weight decay applied to the right parameters (not biases or norms typically), update step sign.
- **Numerical methods.** ODE/PDE timestep convention, boundary conditions, stencil indexing, conservation properties.
- **Generic.** Whatever the paper's key equation is, find the line of code that implements it and verify term-by-term.

### Data pipeline bugs
- **Train/test leakage** through normalization stats fit on the full dataset, through shuffling, through preprocessing.
- **Wrong dtype** at the boundary (e.g., labels as float when they should be long for cross-entropy).
- **Augmentation applied to inputs but not targets** when targets should also be transformed (segmentation masks, keypoints).
- **Label/input misalignment** after shuffling, filtering, or batching.
- **Normalization stats** (mean/std) wrong for the dataset — using ImageNet stats on non-ImageNet data is so common it's worth flagging on sight.

## Step 3 — When to consult external sources

Use the web only when it sharpens the audit:
- The user gave you a paper link → fetch and read the relevant equations.
- The user gave you a reference implementation → fetch and compare the specific function.
- You suspect a bug but want to confirm the canonical form of the algorithm before flagging it (e.g. "I think the RoPE base should be 10000 but want to verify against the original").
- The code claims to implement a named technique you only partially remember.

Do not search speculatively. Every search should answer a specific question that lets you confirm or rule out a specific suspected bug.

## Step 4 — Produce the audit report

Output a ranked report. Use this exact structure:

```
# Numerical Debug Audit

**Scope audited:** <what you actually looked at>
**Reference material used:** <paper / repo / Claude's own knowledge>

## Suspected bugs (ranked by severity)

### 🔴 [Critical] <one-line title>
**Location:** `path/to/file.py:LINE` (function/class name)
**What the code does:** <describe the actual behavior in 1–2 sentences>
**What it should do:** <describe correct behavior, citing paper eq. / reference impl. / canonical form>
**Why this is wrong:** <the mathematical or algorithmic reason>
**How it manifests:** <what you'd observe — silent wrong gradients, off-by-one, etc. Crucially, note whether training would still appear to "work">
**Confidence:** High / Medium / Low — and why

### 🟡 [Likely] <title>
... same structure ...

### 🟢 [Possible / worth checking] <title>
... same structure ...

## Things I checked and that look correct
<brief bullet list — this builds trust and tells the user what's been ruled out>

## Things I could not verify without more context
<list — e.g. "couldn't verify the noise schedule matches the paper without seeing the schedule definition", "the einsum string looks right but I'd want to confirm the convention matches your data layout">
```

### Severity rubric
- **🔴 Critical** — definitely wrong, or wrong with high confidence; would corrupt training silently or produce mathematically incorrect outputs. Examples: loss sign flipped, attention mask off-by-one in causal direction, gradient detached on the main path, wrong reduction axis on the loss.
- **🟡 Likely** — looks wrong but you cannot be 100% sure without the user confirming intent or providing reference material. Examples: normalization axis that *might* be intentional for an unusual variant, scaling factor that depends on a convention.
- **🟢 Possible** — smells off, or is a known footgun pattern, but you don't have enough evidence to flag harder. These are leads for the user to investigate, not accusations.

### Confidence calibration
Be honest about confidence. False alarms erode trust. If you're not sure, say "low confidence" and explain what additional information (a paper reference, a printout of a tensor shape, the user's intent) would let you decide. It is better to flag 3 high-confidence bugs and 5 leads than to dump 20 speculative complaints.

### What NOT to put in the report
- Style suggestions, refactoring ideas, performance improvements, type hint additions, naming nitpicks.
- "You should add a test for this." (You're the auditor, not the test author.)
- Fixed code. (Describe the bug, do not patch it.)
- Anything about security, dependency hygiene, or general software engineering.
- Praise padding. Skip the "overall this is a great codebase" preamble.

## Operating principles

- **Think about tensor semantics, not just shapes.** Two tensors can have matching shapes and still be the wrong things to add. Always ask "what does this axis *mean*?"
- **Bias toward "the code runs but is wrong" bugs.** Anything that crashes, the user already knows about. Your value is finding what doesn't crash.
- **Trace data flow end-to-end in your head.** Pick a single example and follow it from data loader → model input → each layer → loss → gradient. Most bugs surface when you can't reconcile what the tensor *should be* at some point with what the code makes it.
- **Distrust comments.** Comments lie. Read what the code does, not what the comment says it does. If they disagree, that itself is worth flagging.
- **Distrust variable names.** A variable called `logits` is not necessarily logits.
- **The paper is the source of truth, not the code.** When the user provides reference material, anchor your audit on the math, not on what looks reasonable.
- **One pass is not enough on a complex codebase.** Read the forward pass. Then read the loss. Then read the forward pass again with the loss in mind.
- **If you find nothing, say so.** A clean audit report that says "I checked the following things and they look correct, here are the things I couldn't verify" is a valid and useful output. Do not invent bugs to feel productive.
