#include <algorithm>
#include <atomic>
#include <cstdint>
#include <fstream>
#include <future>
#include <iostream>
#include <optional>
#include <vector>

#include <NTL/LLL.h>

namespace {

std::string hex(uint64_t a) {
  std::string s = "";
  while(a != 0) {
    s = "0123456789abcdef"[a & 0xf] + s;
    a >>= 4;
  }
  return s;
}

struct SpectralTest {
  /*  Written in 2019-2021 by Sebastiano Vigna (vigna@acm.org)

  To the extent possible under law, the author has dedicated all copyright
  and related and neighboring rights to this software to the public domain
  worldwide. This software is distributed without any warranty.

  See <http://creativecommons.org/publicdomain/zero/1.0/>. */

  /* Prints approximated figures of merit using the LLL lattice-reduction
     algorithm. If MULT is defined, computes figures of merit for an MCG with
     power-of-two modulus; otherwise, for a full-period congruential generator,
     including LCGs with power-of-two moduli and MCGs with prime moduli (note
     that in the latter case no primitivity check is performed).

     See also Karl Entacher & Thomas Schell's code associated with the paper

     Karl Entacher, Thomas Schell, and Andreas Uhl. Efficient lattice assessment
     for LCG and GLP parameter searches. Mathematics of Computation,
     71(239):1231–1242, 2002.

     at

     https://web.archive.org/web/20181128022136/http://random.mat.sbg.ac.at/results/karl/spectraltest/
  */
  static constexpr int dim_max = 24;

  /* These are the values of gamma_t in Knuth, taken from L'Ecuyer's Lattice Tester. */
  static constexpr double norm[dim_max - 1] = {
    1.1547005383793, // gamma_2
    1.2599210498949,
    1.4142135623731,
    1.5157165665104,
    1.6653663553112,
    1.8114473285278,
    2.0,
    2.0,
    2.0583720179295,
    2.140198065871,
    2.3094010767585,
    2.3563484301065,
    2.4886439198224,
    2.6390158215458,
    2.8284271247462,
    2.8866811540599,
    2.986825999361,
    3.0985192845333,
    3.2490095854249,
    3.3914559675101,
    3.5727801951422,
    3.7660273525956,
    4.0,
  };

  struct Result { double harm_score; double min_fm; };

  int max_dim;
  NTL::ZZ mod;

  static SpectralTest create(const NTL::ZZ &mod) {
    SpectralTest test = { 24, mod };

    return test;
  }

  std::optional<Result> test(const NTL::ZZ &a, NTL::mat_ZZ &mat) {
    double tnorm[dim_max - 1];

    for(int d = 2; d <= dim_max; d++) {
      tnorm[d - 2] = NTL::to_double(NTL::to_RR(1) / (NTL::pow(NTL::to_RR(norm[d - 2]), NTL::to_RR(1./2)) * NTL::pow(NTL::to_RR(mod), NTL::to_RR(1) / NTL::to_RR(d))));
    }

    double harm_norm = 0, min_fm = std::numeric_limits<double>::infinity(), harm_score = 0, cur_fm[dim_max];

    for (int d = 2; d <= this->max_dim; d++) {
      mat.SetDims(d, d);
      // Dual lattice (see Knuth TAoCP Vol. 2, 3.3.4/B*).
      mat[0][0] = mod;
      for (int i = 1; i < d; i++) mat[i][i] = 1;
      for (int i = 1; i < d; i++) mat[i][0] = -NTL::power(a, i);
      NTL::ZZ det2;
      // LLL reduction with delta = 0.999999999
      NTL::LLL(det2, mat, 999999999, 1000000000);

      double min2 = std::numeric_limits<double>::infinity();

      for (int i = 0; i < d; i++) {
        min2 = std::min(min2, NTL::to_double(mat[i] * mat[i]));
      }
      cur_fm[d - 2] = tnorm[d - 2] * sqrt(min2);
      min_fm = std::min(min_fm, cur_fm[d - 2]);
      harm_score += cur_fm[d - 2] / (d - 1);
      harm_norm += 1. / (d - 1);
    }

    if (min_fm < 0.5) return std::nullopt;
    return Result { harm_score / harm_norm, min_fm };
  }
};

uint64_t splitmix(uint64_t z) {
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
  z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
  return z ^ (z >> 31);
}

struct Candidate {
  uint64_t multiplier;
  double spectral_b;
  double min_fm_b;
  double spectral_m;
  double min_fm_m;
};

std::vector<Candidate> search(std::atomic<size_t> &counter, size_t total, size_t thread_id, uint64_t seed) {
  std::vector<Candidate> result;
  size_t update_step = 1 << 24;
  size_t found = 0;
  size_t local_iter = 0;

  NTL::ZZ b = NTL::conv<NTL::ZZ>(1) << 64;
  SpectralTest test_b = SpectralTest::create(b / 4);

  NTL::mat_ZZ mat;

  while (true) {
    size_t i = counter.fetch_add(1, std::memory_order_relaxed);
    if (i >= total) break;

    ++local_iter;
    if (local_iter % update_step == 0) {
      std::cout << "[Thread #" << thread_id << "]:\t";
      std::cout << "Progress: " << local_iter << '\t';
      std::cout << "Found:    " << found << '\n';
    }

    uint64_t state = seed + i * 0x9e3779b97f4a7c15;
    uint64_t x = (splitmix(state) | 0xfff0000000000007) ^ 0x2;
    NTL::ZZ a = NTL::conv<NTL::ZZ>(x);
    NTL::ZZ m = (a << 192) - 1;
    NTL::ZZ p = m / 2;

    if (!NTL::ProbPrime(m)) continue;
    if (!NTL::ProbPrime(p)) continue;

    std::optional<SpectralTest::Result> score_b = test_b.test(a, mat);
    if (!score_b.has_value()) continue;

    SpectralTest test_m = SpectralTest::create(p);
    std::optional<SpectralTest::Result> score_m = test_m.test(NTL::PowerMod(b, 6, p), mat);
    if (!score_m.has_value()) continue;

    ++found;
    result.emplace_back(Candidate { x, score_b->harm_score, score_b->min_fm, score_m->harm_score, score_m->min_fm });
  }

  return result;
}

}

int main(void) {
  size_t thread_count = std::thread::hardware_concurrency() - 1;
  size_t total = 4294967296;

  uint64_t seed = splitmix(42);

  std::atomic<size_t> counter = 0;

  using Result = std::future<std::vector<Candidate>>;
  std::unique_ptr<Result[]> threads = std::make_unique<Result[]>(thread_count);
  for (size_t i = 0; i < thread_count; ++i) {
    size_t thread_id = i + 1;
    threads[i] = std::async(std::launch::async, search, std::ref(counter), total, thread_id, seed);
  }

  std::ofstream fout("candidates.csv");
  fout << "Multiplier,Spectral mod B,MinFM mod B,Spectral mod M,MinFM mod M\n";

  std::vector main_result = search(counter, total, 0, seed);

  for (size_t i = 0; i < thread_count; ++i) {
    for (const Candidate &candidate : threads[i].get()) {
      fout << hex(candidate.multiplier) << ',' << candidate.spectral_b << ',' << candidate.min_fm_b << ',' << candidate.spectral_m << ',' << candidate.min_fm_m << '\n';
    }
  }

  for (const Candidate &candidate : main_result) {
    fout << hex(candidate.multiplier) << ',' << candidate.spectral_b << ',' << candidate.min_fm_b << ',' << candidate.spectral_m << ',' << candidate.min_fm_m << '\n';
  }

  return 0;
}
