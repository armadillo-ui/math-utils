export const add = (a: number, b: number): number => {
  return a + b;
};

export const subtract = (a: number, b: number): number => {
  return a - b;
};

/**
 * Multiplica dos números.
 * @example multiply(2, 4) // 8
 */
export const multiply = (a: number, b: number): number => {
  return a * b;
};

/**
 * Divide dos números.
 * @throws {Error} Si el divisor es cero.
 * @example divide(10, 2) // 5
 */
export const divide = (a: number, b: number): number => {
  if (b === 0) throw new Error('Division by zero');
  return a / b;
};
