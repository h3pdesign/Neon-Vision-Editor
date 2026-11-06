# Offline math preview

Inline fractions and subscripts: $\frac{x_i}{y_j} + \alpha_0$.

Bracket notation also works: \(\mathbb{E}[X] = \mu\).

## Display equations

$$\boxed{\mathcal{J}(k) = \frac{1}{2}k^2 - \delta k}$$

$$
\begin{aligned}
\mathbb{E}[X_t] &= (1-t)\mu_0 + t\mu_1 \\
\mathrm{Var}(X_t) &= (1-t)^2 + t^2
\end{aligned}
$$

\[
\int_0^1 a(t)\,\mathrm{d}t = 1
\]

## Markdown stays Markdown

- **Bold text** around a formula: $x_i^2$.
- Prices stay literal: $5 and $10; a formula follows: $z_k$.

| Symbol | Meaning |
| --- | --- |
| $\mu$ | Mean |
| $\sigma^2$ | Variance |

> $$
> \sum_{i=1}^n x_i
> $$

Code remains literal: `$x_i$`.

```text
$$
\frac{x_i}{y_j}
$$
```

An invalid formula shows its error in place: $\frac{1$.

A valid formula after the error still renders: $\sqrt{2}$.
