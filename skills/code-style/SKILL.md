---
name: code-style
description: Enforces a functional, math-forward code style for personal JAX/Flax/Optax research code with Hydra configs. Use when writing, editing, or refactoring any Python code in this repo — including model definitions, training loops, loss functions, data loading, config dataclasses, and scripts. Covers jax, flax, nn.Module, optax, train_step, loss_fn, jit, vmap, pmap, hydra, ConfigStore, and @hydra.main entrypoints. Prioritizes readability and mathematical clarity over defensive coding, type annotations, and OOP patterns.
---

# research-code-style

Apply this style to all Python code in this repo. It's personal
JAX/Flax/Optax research code with Hydra-based configs. Optimize for
readability and mathematical clarity. Crashes are fine — I'll rerun
the experiment.

## Core rules

- Functions over classes. No class hierarchies, no manager/service
  classes, no inheritance. Exceptions: `flax.nn.Module`, and
  `@dataclass` configs for Hydra.
- No defensive coding. No input validation, no try/except for
  robustness. A few `assert`s for shape checks in core logic is fine.
- Type hints are optional. Use them when they clarify something
  non-obvious (e.g. config dataclass fields). Never add Protocol,
  Generic, TypeVar, or complex unions beyond `X | None`.
- Logging is `print()`. Lowercase, one line, progress-oriented.
  Print key metrics (loss, accuracy) as they come.
- Functional JAX: explicit inputs (params, batch, rng_key), explicit
  outputs. Keep `loss_fn` and `train_step` small and readable.
- Don't reformat or reorganize code unrelated to the requested change.
- Don't add new dependencies unless asked. Stick to jax, flax, optax,
  hydra, and the stdlib.

## Hydra conventions

This repo uses Hydra with structured configs registered via
`ConfigStore`. Follow these patterns exactly when adding or editing
configs.

### Config structure

- Each logical group (network, optimizer, data, loss, ...) is a
  separate `@dataclass` with plain-field defaults.
- List/dict defaults use `field(default_factory=lambda: [...])`.
- Optional fields are typed `X | None = None`, not `Optional[X]`.
- The top-level `Config` composes groups with
  `field(default_factory=GroupName)`.
- Per-dataset configs are built by instantiating `Config(...)` with
  overrides and registered via `cs.store(name=..., node=...)`.
- Keep per-dataset configs as flat constructor calls — don't factor
  shared pieces into helper functions unless there's a lot of reuse.

### Entrypoint pattern

Scripts are launched through `@hydra.main`:

```python
@hydra.main(version_base=None, config_name="default")
def run(cfg: Config) -> None:
    # main code here
    ...

if __name__ == "__main__":
    run()
```

- The decorated function takes `cfg: Config` and returns `None`.
- Use `cfg.net.arch`, `cfg.optimizer.lr`, etc. directly. Don't copy
  fields into local variables just to shorten names unless it
  genuinely helps readability.
- Output paths come from `get_outpath()` in `gmfm/config/__init__.py`
  (or wherever it lives). Don't reconstruct paths from `cfg.name`.

### Adding a new dataset config

Match the existing shape:

```python
new_cfg = Config(
    dataset="newds",
    net=Network(arch='mlp'),
    data=Data(normalize=True, norm_method='-11', n_samples=1024),
    sample=Sample(bs_n=-1, bs_o=-1),
    loss=Loss(n_functions=50_000, b_min=0.5, b_max=4.0, normalize='sym'),
    test=Test(n_samples=16),
)
cs.store(name="newds", node=new_cfg)
```

Only set fields that differ from the group defaults. Don't restate
defaults for "clarity."

## Good example — training code

```python
def loss_fn(params, batch, rng_key, apply_fn):
    """mean squared error on a batch."""
    inputs, targets = batch
    preds = apply_fn(params, rng=rng_key, inputs=inputs)
    return jnp.mean((preds - targets) ** 2)


def train_step(state, batch, rng_key):
    grads = jax.grad(loss_fn)(state.params, batch, rng_key, state.apply_fn)
    updates, new_opt_state = state.tx.update(grads, state.opt_state, state.params)
    new_params = optax.apply_updates(state.params, updates)
    return state.replace(params=new_params, opt_state=new_opt_state)


@hydra.main(version_base=None, config_name="default")
def run(cfg: Config) -> None:
    print(f"starting run {cfg.name} on {cfg.dataset}")
    rng = jax.random.PRNGKey(cfg.seed)
    state = init_state(cfg, rng)

    for it in range(cfg.optimizer.iters):
        rng, step_rng = jax.random.split(rng)
        batch = next_batch(cfg)
        state = train_step(state, batch, step_rng)

        if it % 500 == 0:
            loss = loss_fn(state.params, batch, step_rng, state.apply_fn)
            print(f"iter {it}  loss {loss:.4f}")

    print(f"done. final loss {loss:.4f}")
```

Why it's good: flat functions, explicit rng handling, lowercase
one-line prints with key metrics, no try/except, no type annotations
where they'd be noise, config accessed directly.

## Bad example — do not write code like this

```python
@dataclass
class TrainStepConfig:
    learning_rate: float
    gradient_clip: Optional[float] = None

class Trainer:
    def __init__(self, config: TrainStepConfig, model: nn.Module,
                 optimizer: optax.GradientTransformation) -> None:
        self._config = config
        self._model = model
        self._optimizer = optimizer
        self._validate_config()
        self._logger = logging.getLogger(__name__)

    def train_step(self, state: TrainState, batch: Batch) -> TrainState:
        try:
            grads = self._compute_gradients(state, batch)
            if self._config.gradient_clip is not None:
                grads = self._clip_gradients(grads)
            return self._apply_gradients(state, grads)
        except Exception as e:
            self._logger.error(f"training step failed: {e}")
            raise TrainingError("step failed") from e
```

Why it's bad: class wrapper adds nothing over a function, underscore-
prefixed private methods are ceremony, type annotations are noise,
try/except hides real failures, custom exception and logger are
enterprise patterns, gradient clipping is split into its own method
for no reason.

## Layout

Keep these separated into their own files or clearly-marked sections:

- model definition (Flax modules)
- data loading / preprocessing
- loss and train_step
- training loop
- evaluation / metrics
- config dataclasses (one file, as in the example config)

Names: `logits`, `params`, `grads`, `state`, `batch`, `rng_key`,
`apply_fn`, `loss`. Don't invent new abbreviations.