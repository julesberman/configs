---
name: notebook
description: Enforces a minimal, math-first style for self-contained Jupyter notebooks used as demos and validations of a single idea. Use when creating or editing .ipynb files meant to be run top-to-bottom as a standalone artifact — algorithm demos, sanity checks, paper reproductions, or visual validations with matplotlib plots. Optimizes for mathematical clarity, narrative flow, and the notebook actually executing end-to-end without errors.
disable-model-invocation: true
---

# code-style-notebook

For single-file Jupyter notebooks that demo or validate one idea.
A reader should be able to open the notebook, hit "Run All", and see
the idea work — with plots where they help.

## Rules

- One `.ipynb`. No imports from sibling files. Everything the
  notebook needs lives in the notebook.
- Structure: imports cell → constants cell → math/helpers →
  run/train → plots. Each section preceded by a short markdown cell
  (one or two sentences, sometimes a LaTeX equation) saying what's
  about to happen.
- Markdown cells are for the *story*, not for API docs. Say what
  the next cell is doing mathematically, not what every variable is.
- Functions only. No classes except `flax.nn.Module` / `nn.Module`
  when unavoidable. No type hints. No docstrings. No argparse.
  No config objects.
- Hyperparameters are ALL_CAPS constants in a single cell near the
  top so a reader can tweak and re-run.
- No defensive code. Let it crash. A failing cell is a clearer
  signal than a swallowed exception.
- `print(f"step {i}  loss {loss:.4f}")` for progress. Lowercase,
  one line. Don't use `tqdm` unless the loop is genuinely long.
- Plots use `matplotlib` directly. `plt.figure(); plt.plot(...);
  plt.title(...); plt.show()`. No seaborn, no plotly, no helper
  plotting functions unless the same plot is made 3+ times.
- Every plot needs a title and axis labels. That's the only
  ceremony required.
- Set a seed once near the top. Reproducibility matters for demos.
- Don't leave dead cells, commented-out experiments, or "scratch"
  cells. The notebook is the final artifact — prune as you go.

## Validation

Before declaring a notebook done, verify it's valid and runnable:

- The file must be valid notebook JSON. Quick check:
  `python -c "import nbformat; nbformat.read(open('nb.ipynb'), as_version=4)"`
- The notebook must execute top-to-bottom without errors. Run:
  `jupyter nbconvert --to notebook --execute nb.ipynb --output nb.ipynb`
  (or `--stdout` if you don't want to overwrite). Any cell error
  means the notebook isn't done.
- When authoring programmatically (e.g. building the `.ipynb` from
  Python), always construct cells via `nbformat.v4.new_code_cell` /
  `new_markdown_cell` and write with `nbformat.write`. Never
  hand-format notebook JSON — it will silently break.
- Cell execution counts and outputs from the final run should be
  saved in the notebook so a reader sees results without re-running.

## Good example — cell breakdown

**Markdown:** `# Fitting $y = \sin(3x)$ with a tiny MLP`
A 2-layer tanh network trained with SGD. Sanity check that
JAX + grad gives us the expected curve.

**Code (imports):**
```python
import jax, jax.numpy as jnp
from jax import grad, jit, random
import matplotlib.pyplot as plt
```

**Code (constants):**
```python
N = 512
LR = 1e-3
STEPS = 5000
SIGMA = 0.1
SEED = 0
```

**Markdown:** `## Data`
Noisy samples from $y = \sin(3x) + \epsilon$.

**Code:**
```python
key = random.PRNGKey(SEED)
k1, k2, k3 = random.split(key, 3)
x = random.normal(k1, (N, 1))
y = jnp.sin(3 * x) + SIGMA * random.normal(k2, (N, 1))

plt.figure()
plt.scatter(x, y, s=5)
plt.title("training data")
plt.xlabel("x"); plt.ylabel("y")
plt.show()
```

**Markdown:** `## Model and loss`

**Code:**
```python
def model(params, x):
    W1, b1, W2, b2 = params
    h = jnp.tanh(x @ W1 + b1)
    return h @ W2 + b2

def loss(params, x, y):
    return jnp.mean((model(params, x) - y) ** 2)

params = [
    random.normal(k3, (1, 64)) * 0.1, jnp.zeros(64),
    random.normal(k3, (64, 1)) * 0.1, jnp.zeros(1),
]
```

**Markdown:** `## Training`

**Code:**
```python
@jit
def step(params, x, y):
    g = grad(loss)(params, x, y)
    return [p - LR * gi for p, gi in zip(params, g)]

losses = []
for i in range(STEPS):
    params = step(params, x, y)
    losses.append(float(loss(params, x, y)))
    if i % 500 == 0:
        print(f"step {i}  loss {losses[-1]:.5f}")
```

**Markdown:** `## Results`

**Code:**
```python
xs = jnp.linspace(-3, 3, 200)[:, None]
plt.figure()
plt.scatter(x, y, s=5, label="data")
plt.plot(xs, model(params, xs), c="r", label="fit")
plt.title("fit vs data"); plt.xlabel("x"); plt.ylabel("y"); plt.legend()
plt.show()

plt.figure()
plt.plot(losses)
plt.title("training loss"); plt.xlabel("step"); plt.ylabel("mse")
plt.yscale("log")
plt.show()
```

Why it's good: linear narrative, constants in one place, plots show
the idea worked, no abstractions, runs top-to-bottom.

## Bad

Notebooks with: a `Config` cell that's actually a dataclass, util
cells defining `make_plot()` wrappers, `%load_ext` magics no one
needs, hidden state from out-of-order cell execution, swallowed
exceptions, or commented-out "old version" code. If the notebook
can't be run fresh from top to bottom, it's broken.
