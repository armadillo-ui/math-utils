import { expect, test } from 'vitest'
import { add, subtract, multiply, divide } from "../src/index.ts";

test("add: suma dos números", () => {
  expect(add(2, 3)).toBe(5);
  expect(add(-1, 1)).toBe(0);
  expect(add(0, 0)).toBe(0);
});

test("subtract: resta dos números", () => {
  expect(subtract(5, 3)).toBe(2);
  expect(subtract(0, 5)).toBe(-5);
});

test("multiply: multiplica dos números", () => {
  expect(multiply(2, 4)).toBe(8);
  expect(multiply(-2, 3)).toBe(-6);
  expect(multiply(0, 100)).toBe(0);
});

test("divide: divide dos números", () => {
  expect(divide(10, 2)).toBe(5);
  expect(divide(7, 2)).toBe(3.5);
});

test("divide: lanza error al dividir por cero", () => {
  expect(() => divide(10, 0)).toThrow(/Division by zero/);
});