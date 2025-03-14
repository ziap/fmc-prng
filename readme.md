# Folded Multiply-With-Carry PRNG

An implementation of Marsaglia's Multiply-With-Carry generators, with an extra
scrambling operation of folding the upper and lower halves of the
multiplication result.

## Usage

If you just want the generator, here it is in C, porting to other languages
should be pretty trivial.

```c
typedef struct {
  uint64_t state[3];
  uint64_t carry; // For simplicity, initialize with 1
} Fmc256;

#define MUL 0xfce44986bf155cc5

uint64_t Fmc256_next(Fmc256 *rng) {
  uint64_t result = rng->state[2] ^ rng->carry;
  __uint128_t m = (__uint128_t)rng->state[0] * MUL + rng->carry;
  rng->state[0] = rng->state[1];
  rng->state[1] = rng->state[2];
  rng->state[2] = m;
  rng->carry = m >> 64;
  return result;
}
```

The rest of this repository contains code for configuring and testing the PRNG.
They are not important unless you want to reproduce the result or check for
correctness.

## TODO

- [ ] 128-bit state, 64-bit output variant
- [ ] 128-bit state, 32-bit output variant
- [ ] Speed comparison with other fast PRNGs
- [ ] Statistical quality assessment

## License

This project is licensed under the [MIT License](LICENCE).
