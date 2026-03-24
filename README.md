# @armadillo-ui/math-utils

Utilidades matemáticas simples: suma, resta, multiplicación y división.

## Instalación

```bash
npm install @armadillo-ui/math-utils
```

## Uso

```ts
import { add, subtract, multiply, divide } from "@armadillo-ui/math-utils";

add(2, 3);        // 5
subtract(5, 3);   // 2
multiply(2, 4);   // 8
divide(10, 2);    // 5
divide(10, 0);    // throws Error("Division by zero")
```

## Desarrollo

```bash
npm install
npm test          # tests con vitest
npm run build     # build con tsdown → dist/
```

## Releases automáticos

Este paquete usa **cocogitto** en CI para versionar automáticamente.
Los commits deben seguir [Conventional Commits](https://www.conventionalcommits.org):

| Tipo de commit                    | Bump          |
|-----------------------------------|---------------|
| `fix: ...`                        | patch `0.0.x` |
| `feat: ...`                       | minor `0.x.0` |
| `feat!: ...` o `BREAKING CHANGE:` | major `x.0.0` |
| `chore:`, `docs:`, `refactor:`    | sin release   |

### Ejemplos

```bash
git commit -m "feat: add modulo operation"      # → minor bump
git commit -m "fix: handle NaN in divide"       # → patch bump
git commit -m "feat!: rename add to sum"        # → major bump
git commit -m "chore: update readme"            # → sin release
```

## License

MIT
